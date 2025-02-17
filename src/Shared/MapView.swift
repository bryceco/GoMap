//
//  MapView.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import Foundation
import QuartzCore
import SafariServices
import StoreKit
import UIKit

/// The main map display: Editor, Aerial, Basemap etc.
enum MapViewState: Int {
	case EDITOR
	case EDITORAERIAL
	case AERIAL
	case BASEMAP
}

/// Overlays on top of the map: Locator when zoomed, GPS traces, etc.
struct MapViewOverlays: OptionSet {
	let rawValue: Int
	static let LOCATOR = MapViewOverlays(rawValue: 1 << 0)
	static let GPSTRACE = MapViewOverlays(rawValue: 1 << 1)
	static let NOTES = MapViewOverlays(rawValue: 1 << 2)
	static let QUESTS = MapViewOverlays(rawValue: 1 << 4)
	static let DATAOVERLAY = MapViewOverlays(rawValue: 1 << 5)
}

enum GPS_STATE: Int {
	case NONE
	case LOCATION
	case HEADING
}

enum EDIT_ACTION: Int {
	// used by edit control:
	case EDITTAGS
	case ADDNOTE
	case DELETE
	case MORE
	// used for action sheet edits:
	case SPLIT
	case RECTANGULARIZE
	case STRAIGHTEN
	case REVERSE
	case DUPLICATE
	case ROTATE
	case JOIN
	case DISCONNECT
	case EXTRACTNODE
	case CIRCULARIZE
	case COPYTAGS
	case PASTETAGS
	case RESTRICT
	case CREATE_RELATION

	/// Localized names of edit actions
	func actionTitle(abbreviated: Bool = false) -> String {
		switch self {
		case .SPLIT: return NSLocalizedString("Split", comment: "Edit action")
		case .RECTANGULARIZE: return NSLocalizedString("Make Rectangular", comment: "Edit action")
		case .STRAIGHTEN: return NSLocalizedString("Straighten", comment: "Edit action")
		case .REVERSE: return NSLocalizedString("Reverse", comment: "Edit action")
		case .DUPLICATE: return NSLocalizedString("Duplicate", comment: "Edit action")
		case .ROTATE: return NSLocalizedString("Rotate", comment: "Edit action")
		case .CIRCULARIZE: return NSLocalizedString("Make Circular", comment: "Edit action")
		case .JOIN: return NSLocalizedString("Join", comment: "Edit action")
		case .DISCONNECT: return NSLocalizedString("Disconnect", comment: "Edit action")
		case .EXTRACTNODE: return NSLocalizedString("Extract Node", comment: "Edit action")
		case .COPYTAGS: return NSLocalizedString("Copy Tags", comment: "Edit action")
		case .PASTETAGS: return NSLocalizedString("Paste", comment: "Edit action")
		case .EDITTAGS: return NSLocalizedString("Tags", comment: "Edit action")
		case .ADDNOTE: return NSLocalizedString("Add Note", comment: "Edit action")
		case .DELETE: return NSLocalizedString("Delete", comment: "Edit action")
		case .MORE: return NSLocalizedString("More...", comment: "Edit action")
		case .RESTRICT: return abbreviated
			? NSLocalizedString("Restrict", comment: "Edit action")
			: NSLocalizedString("Turn Restrictions", comment: "Edit action")
		case .CREATE_RELATION: return NSLocalizedString("Create Relation", comment: "Edit action")
		}
	}
}

private enum ZLAYER: CGFloat {
	case AERIAL = -100
	case BASEMAP = -98
	case LOCATOR = -50
	case DATA = -30
	case EDITOR = -20
	case QUADDOWNLOAD = -18
	case GPX = -15
	case ROTATEGRAPHIC = -3
	case BLINK = 4
	case CROSSHAIRS = 5
	case D_PAD = 6
	case LOCATION_BALL = 10
	case TOOLBAR = 90
	case PUSHPIN = 105
	case FLASH = 110
}

// how close to an object do we need to tap to select it
let DefaultHitTestRadius: CGFloat = 10.0

// how close to an object do we need to drag a node to connect to it
let DragConnectHitTestRadius = (DefaultHitTestRadius * 0.6)

struct MapLocation {
	var longitude = 0.0
	var latitude = 0.0
	var zoom = 0.0
	var direction = 0.0 // degrees clockwise from north
	var viewState: MapViewState? = nil
}

protocol MapViewProgress {
	func progressIncrement(_ delta: Int)
	func progressDecrement()
}

// MARK: Gestures

private let DisplayLinkHeading = "Heading"
private let DisplayLinkPanning = "Panning" // disable gestures inside toolbar buttons

final class MapView: UIView, MapViewProgress, CLLocationManagerDelegate, UIActionSheetDelegate,
	UIGestureRecognizerDelegate, SKStoreProductViewControllerDelegate, DPadDelegate,
	UISheetPresentationControllerDelegate
{
	var lastMouseDragPos = CGPoint.zero
	var progressActive = AtomicInt(0)
	var locationBallLayer: LocationBallLayer
	var addWayProgressLayer: CAShapeLayer?
	var blinkObject: OsmBaseObject? // used for creating a moving dots animation during selection
	var blinkSegment = 0
	var blinkLayer: CAShapeLayer?
	var isZoomScroll = false // Command-scroll zooms instead of scrolling (desktop only)

	var isRotateObjectMode: (rotateObjectOverlay: CAShapeLayer, rotateObjectCenter: LatLon)?

	var lastErrorDate: Date? // to prevent spamming of error dialogs
	var ignoreNetworkErrorsUntilDate: Date?
	var voiceAnnouncement: VoiceAnnouncement?
	var tapAndDragGesture: TapAndDragGesture!

	var addNodeButtonLongPressGestureRecognizer: UILongPressGestureRecognizer?
	var plusButtonTimestamp: TimeInterval = 0.0

	var windowPresented = false
	var locationManagerExtraneousNotification = false

	var mainViewController = MainViewController()
	@IBOutlet var fpsLabel: FpsLabel!
	@IBOutlet var userInstructionLabel: UILabel!
	@IBOutlet var compassButton: CompassButton!
	@IBOutlet var flashLabel: UILabel!
	@IBOutlet var aerialServiceLogo: UIButton!
	@IBOutlet var helpButton: UIButton!
	@IBOutlet var centerOnGPSButton: UIButton!
	@IBOutlet var addNodeButton: UIButton!
	@IBOutlet var rulerView: RulerView!
	@IBOutlet var progressIndicator: UIActivityIndicatorView!
	@IBOutlet var editControl: UISegmentedControl!
	@IBOutlet var aerialAlignmentButton: UIButton!
	@IBOutlet var dPadView: DPadView!

	private var magnifyingGlass: MagnifyingGlass!

	private var editControlActions: [EDIT_ACTION] = []

	let locationManager = CLLocationManager()
	private(set) var currentLocation = CLLocation()

	public var viewState: MapViewState = .EDITORAERIAL {
		willSet(newValue) {
			viewStateWillChangeTo(newValue, overlays: viewOverlayMask, zoomedOut: viewStateZoomedOut)
		}
	}

	public var viewOverlayMask: MapViewOverlays = [] {
		willSet(newValue) {
			viewStateWillChangeTo(viewState, overlays: newValue, zoomedOut: viewStateZoomedOut)
		}
	}

	private var viewStateZoomedOut = false { // override layer because we're zoomed out
		willSet(newValue) {
			viewStateWillChangeTo(viewState, overlays: viewOverlayMask, zoomedOut: newValue)
		}
	}

	public var userOverrodeLocationPosition = false {
		didSet {
			centerOnGPSButton.isHidden = !userOverrodeLocationPosition || gpsState == .NONE
		}
	}

	public var userOverrodeLocationZoom = false {
		didSet {
			centerOnGPSButton.isHidden = !userOverrodeLocationZoom || gpsState == .NONE
		}
	}

	public var basemapServer: TileServer {
		get {
			let ident = UserPrefs.shared.currentBasemapSelection.value
			return BasemapServerList.first(where: { $0.identifier == ident }) ?? BasemapServerList.first!
		}
		set {
			let oldServerId = basemapServer.identifier
			backgroundLayers.removeAll(where: {
				switch $0 {
				case let .tileLayer(layer):
					if layer.tileServer.identifier == oldServerId {
						layer.removeFromSuperlayer()
						return true
					}
				case let .tileView(view):
					if view.tileServer.identifier == oldServerId {
						view.removeFromSuperview()
						return true
					}
				case .otherLayer:
					break
				}
				return false
			})

			if newValue.isVector {
				let view = MapLibreVectorTilesView(mapView: self, tileServer: newValue)
				view.styleURL = URL(string: newValue.url)!
				view.layer.zPosition = ZLAYER.BASEMAP.rawValue
				insertSubview(view, at: 0) // place at bottom so MapMarkers are above it
				basemapLayer = .tileView(view)
			} else {
				let layer = MercatorTileLayer(mapView: self)
				layer.tileServer = newValue
				layer.supportDarkMode = true
				layer.zPosition = ZLAYER.BASEMAP.rawValue
				self.layer.addSublayer(layer)
				basemapLayer = .tileLayer(layer)
			}
			backgroundLayers.append(basemapLayer)

			UserPrefs.shared.currentBasemapSelection.value = newValue.identifier

			basemapLayer.isHidden = viewState != .BASEMAP
		}
	}

	private(set) lazy var mapMarkerDatabase = MapMarkerDatabase()

	private(set) lazy var aerialLayer = MercatorTileLayer(mapView: self)
	private(set) lazy var basemapLayer: LayerOrView = .tileLayer(MercatorTileLayer(mapView: self))
	private(set) lazy var noNameLayer = MercatorTileLayer(mapView: self)
	private(set) lazy var editorLayer = EditorMapLayer(owner: self)
	private(set) lazy var gpxLayer = GpxLayer(mapView: self)
	private(set) lazy var dataOverlayLayer = DataOverlayLayer(mapView: self)
	private(set) var quadDownloadLayer: QuadDownloadLayer?

	// overlays
	private(set) lazy var locatorLayer = MercatorTileLayer(mapView: self)

	enum LayerOrView: Equatable {
		case otherLayer(CALayer)
		case tileLayer(MercatorTileLayer)
		case tileView(MapLibreVectorTilesView)

		var isHidden: Bool {
			get {
				switch self {
				case let .otherLayer(layer): return layer.isHidden
				case let .tileLayer(layer): return layer.isHidden
				case let .tileView(view): return view.isHidden
				}
			}
			set {
				switch self {
				case let .otherLayer(layer): layer.isHidden = newValue
				case let .tileLayer(layer): layer.isHidden = newValue
				case let .tileView(view): view.isHidden = newValue
				}
			}
		}
	}

	private(set) var backgroundLayers: [LayerOrView] = [] // list of all layers that need to be resized, etc.

	var mapTransform = MapTransform()
	var screenFromMapTransform: OSMTransform {
		get {
			return mapTransform.transform
		}
		set(t) {
			if t == mapTransform.transform {
				return
			}
			var t = t

			// save pushpinView coordinates
			var pp: LatLon?
			if let pushpinView = pushPin {
				pp = mapTransform.latLon(forScreenPoint: pushpinView.arrowPoint)
			}
			// we could move the blink outline similar to pushpin, but it's complicated and less important
			unblinkObject()

			// Wrap around if we translate too far longitudinally
			let unitX = t.unitX()
			let unitY = OSMPoint(x: -unitX.y, y: unitX.x)
			let tran = t.translation()
			let dx = Dot(tran, unitX) // translation distance in x direction
			let dy = Dot(tran, unitY)
			let scale = t.scale()
			let mapSize = 256 * scale
			if dx > 0 {
				let mul = ceil(dx / mapSize)
				t = t.translatedBy(dx: -mul * mapSize / scale, dy: 0.0)
			} else if dx < -mapSize {
				let mul = floor(-dx / mapSize)
				t = t.translatedBy(dx: mul * mapSize / scale, dy: 0.0)
			}

			// limit scrolling latitudinally
			if dy > mapSize {
				t = t.translatedBy(dx: 0.0, dy: mapSize - dy)
			} else if dy < -2 * mapSize {
				t = t.translatedBy(dx: 0.0, dy: -2 * mapSize - dy)
			}

			// update transform
			mapTransform.transform = t

			// Determine if we've zoomed out enough to disable editing
			// We can only compute a precise surface area size at high zoom since it's possible
			// for the earth to be larger than the screen
			let area = mapTransform.zoom() > 8 ? SurfaceAreaOfRect(screenLatLonRect()) : Double.greatestFiniteMagnitude
			var isZoomedOut = area > 2.0 * 1000 * 1000
			if !editorLayer.isHidden, !editorLayer.atVisibleObjectLimit, area < 1000.0 * 1000 * 1000 {
				isZoomedOut = false
			}
			viewStateZoomedOut = isZoomedOut

			updateUserLocationIndicator(nil)
			updateCurrentRegionForLocationUsingCountryCoder()
			promptForBetterBackgroundImagery()

			// update pushpin location
			if let pushpinView = pushPin,
			   let pp = pp
			{
				if pushpinView.isDragging {
					// moving the screen while dragging the pin moves the pin/object
					let pt = mapTransform.screenPoint(forLatLon: pp, birdsEye: true)
					let drag = pushpinView.arrowPoint.minus(pt)
					pushpinView.dragCallback(.changed, drag.x, drag.y)
				} else {
					// if not dragging then make sure pin placement is updated
					let wasInside = bounds.contains(pushpinView.arrowPoint)
					pushpinView.arrowPoint = mapTransform.screenPoint(forLatLon: pp,
					                                                  birdsEye: true)
					let isInside = bounds.contains(pushpinView.arrowPoint)
					if wasInside, !isInside {
						// generate feedback if the user scrolled the pushpin off the screen
						let feedback = UINotificationFeedbackGenerator()
						feedback.notificationOccurred(.warning)
					}
				}
			}

			// We moved to a new location so update markers
			updateMapMarkerButtonPositions()
		}
	}

	var mapFromScreenTransform: OSMTransform {
		return screenFromMapTransform.inverse()
	}

	var gpsState: GPS_STATE = .NONE {
		didSet {
			if gpsState != oldValue {
				// update collection of GPX points
				if oldValue == .NONE, gpsState != .NONE {
					// because recording GPX tracks is cheap we record them every time GPS is enabled
					gpxLayer.startNewTrack(continuing: false)
				} else if gpsState == .NONE {
					gpxLayer.endActiveTrack(continuing: false)
				}

				if gpsState == .NONE {
					centerOnGPSButton.isHidden = true
					voiceAnnouncement?.enabled = false
				} else {
					voiceAnnouncement?.enabled = true
				}

				if gpsState != .NONE {
					locating = true
				} else {
					locating = false
				}
			}
		}
	}

	var gpsInBackground: Bool {
		get {
			return GpxLayer.backgroundTracking
		}
		set(gpsInBackground) {
			GpxLayer.backgroundTracking = gpsInBackground

			locationManager.allowsBackgroundLocationUpdates = gpsInBackground && displayGpxLogs

			if gpsInBackground {
				// ios 8 and later:
				if locationManager.responds(to: #selector(CLLocationManager.requestAlwaysAuthorization)) {
					locationManager.requestAlwaysAuthorization()
				}
			}
		}
	}

	private(set) var pushPin: PushPinView?

	let tileServerList: TileServerList

	var enableBirdsEye = false {
		didSet {
			if !enableBirdsEye {
				// remove birdsEye
				rotateBirdsEye(by: -mapTransform.birdsEyeRotation)
			}
		}
	}

	var enableRotation = false {
		didSet {
			if !enableRotation {
				// remove rotation
				let centerPoint = centerPoint()
				let angle = CGFloat(screenFromMapTransform.rotation())
				rotate(by: -angle, aroundScreenPoint: centerPoint)
			}
		}
	}

	var displayGpxLogs = false {
		didSet {
			gpxLayer.isHidden = !displayGpxLogs
			locationManager.allowsBackgroundLocationUpdates = gpsInBackground && displayGpxLogs
		}
	}

	var displayDataOverlayLayer = false {
		didSet {
			dataOverlayLayer.isHidden = !displayDataOverlayLayer

			if displayDataOverlayLayer {
				dataOverlayLayer.setNeedsLayout()
			}
			updateTileOverlayLayers()
		}
	}

	var enableTurnRestriction = false {
		didSet {
			if oldValue != enableTurnRestriction {
				editorLayer.clearCachedProperties()
			}
		}
	}

	var enableAutomaticCacheManagement = false

	private let AUTOSCROLL_DISPLAYLINK_NAME = "autoScroll"
	var automatedFramerateTestActive: Bool {
		get {
			return DisplayLink.shared.hasName(AUTOSCROLL_DISPLAYLINK_NAME)
		}
		set(enable) {
			let displayLink = DisplayLink.shared

			if enable == displayLink.hasName(AUTOSCROLL_DISPLAYLINK_NAME) {
				// unchanged
				return
			}

			if enable {
				// automaatically scroll view for frame rate testing
				fpsLabel.showFPS = true

				// this set's the starting center point
				let startLatLon = LatLon(lon: -122.2060122462481, lat: 47.675389766549706)
				let startZoom = 18.0

				// sets the size of the circle
				let mpd = MetersPerDegreeAt(latitude: startLatLon.lat)
				let radius = 35.0
				let radius2 = CGPoint(x: radius / mpd.x, y: radius / mpd.y)
				let startTime = CACurrentMediaTime()
				let periodSeconds = 2.0
				weak var weakSelf = self

				displayLink.addName(AUTOSCROLL_DISPLAYLINK_NAME, block: {
					guard let myself = weakSelf else { return }
					let offset = 1.0 - fmod((CACurrentMediaTime() - startTime) / periodSeconds, 1.0)
					let origin = LatLon(lon: startLatLon.lon + cos(offset * 2.0 * .pi) * radius2.x,
					                    lat: startLatLon.lat + sin(offset * 2.0 * .pi) * radius2.y)
					let zoomFrac = (1.0 + cos(offset * 2.0 * .pi)) * 0.5
					let zoom = startZoom * (1 + zoomFrac * 0.01)
					myself.centerOn(latLon: origin, zoom: zoom)
				})
			} else {
				fpsLabel.showFPS = false
				displayLink.removeName(AUTOSCROLL_DISPLAYLINK_NAME)
			}
		}
	}

	private(set) var crossHairs: CAShapeLayer!

	struct CurrentRegion: Codable, Equatable {
		let latLon: LatLon
		let country: String
		let regions: [String]

		static let none = CurrentRegion(latLon: LatLon(x: 0, y: 0),
		                                country: "",
		                                regions: [])

		func saveToUserPrefs() {
			UserPrefs.shared.currentRegion.value = try? PropertyListEncoder().encode(self)
		}

		static func fromUserPrefs() -> Self? {
			if let data = UserPrefs.shared.currentRegion.value {
				return try? PropertyListDecoder().decode(CurrentRegion.self, from: data)
			}
			return nil
		}

		func callingCodes() -> [String] {
			let regionDict = CountryCoder.shared.regionDict
			let regionList = regions.compactMap({ regionDict[$0] })
			return regionList.first(where: { $0.callingCodes.count > 0 })?.callingCodes ?? []
		}
	}

	private(set) var currentRegion: CurrentRegion

	private var locating: Bool {
		didSet {
			if oldValue == locating {
				return
			}
			if locating {
				let status = CLLocationManager.authorizationStatus()
				switch status {
				case .notDetermined:
					// we haven't asked user before, so have iOS pop up the question
					locationManager.requestWhenInUseAuthorization()
					gpsState = .NONE
					return
				case .restricted, .denied:
					// user denied permission previously, so ask if they want to open Settings
					AppDelegate.askUser(toAllowLocationAccess: mainViewController)
					gpsState = .NONE
					return
				case .authorizedAlways, .authorizedWhenInUse:
					break
				default:
					break
				}

				userOverrodeLocationPosition = false
				userOverrodeLocationZoom = false
				locationManager.startUpdatingLocation()
				locationManager.startUpdatingHeading()
				locationBallLayer.isHidden = false
			} else {
				locationManager.stopUpdatingLocation()
				locationManager.stopUpdatingHeading()
				locationBallLayer.isHidden = true
			}
		}
	}

	@IBOutlet private var statusBarBackground: UIVisualEffectView!

	// MARK: initialization

	required init?(coder: NSCoder) {
		tileServerList = TileServerList()
		locationBallLayer = LocationBallLayer()
		locating = false
		currentRegion = CurrentRegion.none

		super.init(coder: coder)

		tileServerList.onChange = {
			self.promptForBetterBackgroundImagery()
		}

		layer.masksToBounds = true
		backgroundColor = UIColor(white: 0.1, alpha: 1.0)

		// this option needs to be set before the editor is initialized
		enableAutomaticCacheManagement = UserPrefs.shared.automaticCacheManagement.value ?? true

		locatorLayer = MercatorTileLayer(mapView: self)
		locatorLayer.zPosition = ZLAYER.LOCATOR.rawValue
		locatorLayer.tileServer = TileServer.mapboxLocator
		locatorLayer.isHidden = true
		backgroundLayers.append(.tileLayer(locatorLayer))

		aerialLayer = MercatorTileLayer(mapView: self)
		aerialLayer.zPosition = ZLAYER.AERIAL.rawValue
		aerialLayer.tileServer = tileServerList.currentServer
		aerialLayer.isHidden = true
		backgroundLayers.append(.tileLayer(aerialLayer))

		// self-assigning will do everything to set up the appropriate layer
		basemapServer = basemapServer
		basemapLayer.isHidden = true

		editorLayer = EditorMapLayer(owner: self)
		editorLayer.zPosition = ZLAYER.EDITOR.rawValue
		backgroundLayers.append(.otherLayer(editorLayer))

		gpxLayer.zPosition = ZLAYER.GPX.rawValue
		gpxLayer.isHidden = true
		backgroundLayers.append(.otherLayer(gpxLayer))

		dataOverlayLayer.zPosition = ZLAYER.DATA.rawValue
		dataOverlayLayer.isHidden = true
		backgroundLayers.append(.otherLayer(dataOverlayLayer))

#if DEBUG && false
		quadDownloadLayer = QuadDownloadLayer(mapView: self)
		if let quadDownloadLayer = quadDownloadLayer {
			quadDownloadLayer.zPosition = Z_QUADDOWNLOAD
			quadDownloadLayer.isHidden = false
			backgroundLayers.append(.otherlayer(quadDownloadLayer))
		}
#endif

		for bg in backgroundLayers {
			switch bg {
			case let .otherLayer(layer):
				self.layer.addSublayer(layer)
			case let .tileLayer(layer):
				self.layer.addSublayer(layer)
			case let .tileView(view):
				addSubview(view)
			}
		}

		// implement crosshairs
		crossHairs = CrossHairsLayer(radius: 12.0)
		crossHairs.position = bounds.center()
		crossHairs.zPosition = ZLAYER.CROSSHAIRS.rawValue
		layer.addSublayer(crossHairs)

		locationBallLayer.zPosition = ZLAYER.LOCATION_BALL.rawValue
		locationBallLayer.heading = 0.0
		locationBallLayer.showHeading = true
		locationBallLayer.isHidden = true
		layer.addSublayer(locationBallLayer)

#if false
		voiceAnnouncement = VoiceAnnouncement()
		voiceAnnouncement?.mapView = self
		voiceAnnouncement?.radius = 30 // meters
#endif
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(applicationWillTerminate(_:)),
			name: UIApplication.willResignActiveNotification,
			object: nil)

		userInstructionLabel.layer.cornerRadius = 5
		userInstructionLabel.layer.masksToBounds = true
		userInstructionLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.3)
		userInstructionLabel.textColor = UIColor.white
		userInstructionLabel.isHidden = true

		progressIndicator.color = UIColor.green

		locationManagerExtraneousNotification = true // flag that we're going to receive a bogus notification from CL
		locationManager.delegate = self
		locationManager.pausesLocationUpdatesAutomatically = false
		locationManager.allowsBackgroundLocationUpdates = gpsInBackground && displayGpxLogs
		if #available(iOS 11.0, *) {
			locationManager.showsBackgroundLocationIndicator = true
		}
		locationManager.activityType = .other

		rulerView.mapView = self
		//    _rulerView.layer.zPosition = Z_RULER;

		// set up action button
		editControl.isHidden = true
		editControl.isSelected = false
		editControl.selectedSegmentIndex = Int(UISegmentedControl.noSegment)
		editControl.setTitleTextAttributes(
			[
				NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .headline)
			],
			for: .normal)
		editControl.layer.zPosition = ZLAYER.TOOLBAR.rawValue
		editControl.layer.cornerRadius = 4.0
#if targetEnvironment(macCatalyst)
		// We add a constraint in the storyboard to make the edit control buttons taller
		// so they're easier to push, but on Mac the constraints doesn't work correctly
		// and the buttons look ugly, so remove it.
		if let height = editControl.constraints.first(where: {
			$0.firstAttribute == .height && $0.constant == 43.0
		}) {
			editControl.removeConstraint(height)
		}
#endif

		// long press for selecting from multiple objects (for multipolygon members)
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(screenLongPressGesture(_:)))
		longPress.delegate = self
		addGestureRecognizer(longPress)

		// two-finger rotation
		let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
		rotationGesture.delegate = self
		addGestureRecognizer(rotationGesture)

		// long-press on + for adding nodes via taps
		addNodeButtonLongPressGestureRecognizer = UILongPressGestureRecognizer(
			target: self,
			action: #selector(plusButtonLongPressHandler(_:)))
		addNodeButtonLongPressGestureRecognizer?.minimumPressDuration = 0.001
		addNodeButtonLongPressGestureRecognizer?.delegate = self
		if let addNodeButtonLongPressGestureRecognizer = addNodeButtonLongPressGestureRecognizer {
			addNodeButton.addGestureRecognizer(addNodeButtonLongPressGestureRecognizer)
		}

		if #available(iOS 13.4, macCatalyst 13.4, *) {
			// pan gesture to recognize mouse-wheel scrolling (zoom) on iPad and Mac Catalyst
			let scrollWheelGesture = UIPanGestureRecognizer(
				target: self,
				action: #selector(handleScrollWheelGesture(_:)))
			scrollWheelGesture.allowedScrollTypesMask = .discrete
			scrollWheelGesture.maximumNumberOfTouches = 0
			addGestureRecognizer(scrollWheelGesture)
		}

		mapMarkerDatabase.mapData = editorLayer.mapData

		// center button
		centerOnGPSButton.isHidden = true

		// dPadView
		dPadView.delegate = self
		dPadView.layer.zPosition = ZLAYER.D_PAD.rawValue
		dPadView.isHidden = true

		// error message label
		flashLabel.font = UIFont.preferredFont(forTextStyle: .title3)
		flashLabel.layer.cornerRadius = 5
		flashLabel.layer.masksToBounds = true
		flashLabel.layer.zPosition = ZLAYER.FLASH.rawValue
		flashLabel.isHidden = true

		// magnifying glass
		magnifyingGlass = MagnifyingGlass(sourceView: self, radius: 70.0, scale: 2.0)
		superview!.addSubview(magnifyingGlass)
		magnifyingGlass.setPosition(.topLeft, animated: false)
		magnifyingGlass.isHidden = true

		// Support zoom via tap and drag
		tapAndDragGesture = TapAndDragGesture(target: self, action: #selector(handleTapAndDragGesture(_:)))
		tapAndDragGesture.delegate = self
		tapAndDragGesture.delaysTouchesBegan = false
		tapAndDragGesture.delaysTouchesEnded = false
		addGestureRecognizer(tapAndDragGesture)

		// these need to be loaded late because assigning to them changes the view
		viewState = MapViewState(rawValue: UserPrefs.shared.mapViewState.value ?? -999)
			?? MapViewState.EDITORAERIAL
		viewOverlayMask = MapViewOverlays(rawValue: UserPrefs.shared.mapViewOverlays.value ?? 0)

		enableRotation = UserPrefs.shared.mapViewEnableRotation.value ?? true
		enableBirdsEye = UserPrefs.shared.mapViewEnableBirdsEye.value ?? false
		displayGpxLogs = UserPrefs.shared.mapViewEnableBreadCrumb.value ?? false
		displayDataOverlayLayer = UserPrefs.shared.mapViewEnableDataOverlay.value ?? false
		enableTurnRestriction = UserPrefs.shared.mapViewEnableTurnRestriction.value ?? false

		if let loc = CurrentRegion.fromUserPrefs() {
			currentRegion = loc
		} else {
			currentRegion = CurrentRegion(latLon: LatLon(x: 0, y: 0), country: "", regions: [])
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0,
		                              execute: {
		                              	self.updateCurrentRegionForLocationUsingCountryCoder()
		                              	self.promptForBetterBackgroundImagery()
		                              })

		updateAerialAttributionButton()

		editorLayer.whiteText = !aerialLayer.isHidden
	}

	func viewDidAppear() {
		// Only want to run this once. On older versions of iOS viewDidAppear is called multiple times
		if !windowPresented {
			windowPresented = true

			// get current location
			if let lat = UserPrefs.shared.view_latitude.value,
			   let lon = UserPrefs.shared.view_longitude.value,
			   let scale = UserPrefs.shared.view_scale.value
			{
				setTransformFor(latLon: LatLon(latitude: lat, longitude: lon),
				                scale: scale)
			} else {
				let rc = OSMRect(layer.bounds)
				screenFromMapTransform = OSMTransform.translation(rc.origin.x + rc.size.width / 2 - 128,
				                                                  rc.origin.y + rc.size.height / 2 - 128)
				// turn on GPS which will move us to current location
				mainViewController.setGpsState(GPS_STATE.LOCATION)
			}

			// get notes
			updateMapMarkersFromServer(withDelay: 0, including: [])
		}
	}

	func acceptsFirstResponder() -> Bool {
		return true
	}

	func tileOverlayLayers() -> [MercatorTileLayer] {
		return backgroundLayers.filter {
			if case let .tileLayer(layer) = $0 {
				return layer.tileServer.overlay
			}
			return false
		} as! [MercatorTileLayer]
	}

	func updateTileOverlayLayers() {
		let serverIdents = UserPrefs.shared.tileOverlaySelections.value ?? []

		// if they toggled display of the noname layer we need to refresh the editor layer
		if serverIdents.contains(TileServer.noName.identifier) != useUnnamedRoadHalo() {
			editorLayer.clearCachedProperties()
		}

		// remove any layers no longer displayed
		let removals = backgroundLayers.filter { layer in
			guard case let .tileLayer(layer) = layer,
			      layer.tileServer.overlay
			else {
				return false
			}
			if displayDataOverlayLayer, serverIdents.contains(layer.tileServer.identifier) {
				return false
			}
			return true
		}
		for layer in removals {
			backgroundLayers.removeAll(where: { $0 == layer })
			switch layer {
			case let .otherLayer(layer):
				layer.removeFromSuperlayer()
			case let .tileLayer(layer):
				layer.removeFromSuperlayer()
			case let .tileView(view):
				view.removeFromSuperview()
			}
		}

		if displayDataOverlayLayer {
			// create any overlay layers the user had enabled
			for ident in serverIdents {
				if backgroundLayers.contains(where: {
					guard case let .tileLayer(layer) = $0 else { return false }
					return layer.tileServer.identifier == ident
				}) {
					// already have it
					continue
				}
				guard let tileServer = tileServerList.serviceWithIdentifier(ident) else {
					// server doesn't exist anymore
					var list = serverIdents
					list.removeAll(where: { $0 == ident })
					UserPrefs.shared.tileOverlaySelections.value = list
					continue
				}

				let layer = MercatorTileLayer(mapView: self)
				layer.zPosition = ZLAYER.GPX.rawValue
				layer.tileServer = tileServer
				layer.isHidden = false
				backgroundLayers.append(.tileLayer(layer))
				self.layer.addSublayer(layer)
			}
		}
		layoutSubviews()
	}

	func save() {
		// save preferences first
		let latLon = screenCenterLatLon()
		let scale = screenFromMapTransform.scale()
#if false && DEBUG
		assert(scale > 1.0)
#endif
		UserPrefs.shared.view_scale.value = scale
		UserPrefs.shared.view_latitude.value = latLon.lat
		UserPrefs.shared.view_longitude.value = latLon.lon

		UserPrefs.shared.mapViewState.value = viewState.rawValue
		UserPrefs.shared.mapViewOverlays.value = viewOverlayMask.rawValue

		UserPrefs.shared.mapViewEnableRotation.value = enableRotation
		UserPrefs.shared.mapViewEnableBirdsEye.value = enableBirdsEye
		UserPrefs.shared.mapViewEnableBreadCrumb.value = displayGpxLogs
		UserPrefs.shared.mapViewEnableDataOverlay.value = displayDataOverlayLayer
		UserPrefs.shared.mapViewEnableTurnRestriction.value = enableTurnRestriction
		UserPrefs.shared.automaticCacheManagement.value = enableAutomaticCacheManagement

		currentRegion.saveToUserPrefs()

		UserPrefs.shared.synchronize()

		tileServerList.save()
		gpxLayer.saveActiveTrack()

		// then save data
		editorLayer.save()
	}

	@objc func applicationWillTerminate(_ notification: Notification) {
		voiceAnnouncement?.removeAll()
		save()
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		let bounds = self.bounds

		// update bounds of layers
		for bg in backgroundLayers {
			switch bg {
			case let .otherLayer(layer):
				layer.frame = bounds
				layer.bounds = bounds
			case let .tileLayer(layer):
				layer.frame = bounds
				layer.bounds = bounds
			case let .tileView(view):
				view.frame = bounds
				view.bounds = bounds.offsetBy(dx: bounds.width / 2, dy: bounds.height / 2)
			}
		}

		crossHairs.position = bounds.center()

		statusBarBackground.isHidden = UIApplication.shared.isStatusBarHidden
	}

	override var bounds: CGRect {
		get {
			return super.bounds
		}
		set(bounds) {
			var bounds = bounds
			// adjust bounds so we're always centered on 0,0
			bounds = CGRect(
				x: -bounds.size.width / 2,
				y: -bounds.size.height / 2,
				width: bounds.size.width,
				height: bounds.size.height)
			super.bounds = bounds
		}
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if #available(iOS 13.0, *),
		   traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
		   case let .tileLayer(view) = basemapLayer
		{
			view.updateDarkMode()
		}
	}

	// MARK: Utility

	func isFlipped() -> Bool {
		return true
	}

	func updateAerialAttributionButton() {
		let service = aerialLayer.tileServer
		let icon = service.attributionIcon(height: aerialServiceLogo.frame.size.height,
		                                   completion: {
		                                   	self.updateAerialAttributionButton()
		                                   })
		aerialServiceLogo.isHidden = aerialLayer.isHidden || (service.attributionString.isEmpty && icon == nil)
		if !aerialServiceLogo.isHidden {
			let gap = icon != nil && service.attributionString.count > 0 ? " " : ""
			aerialServiceLogo.setImage(icon, for: .normal)
			aerialServiceLogo.setTitle(gap + service.attributionString, for: .normal)
		}
	}

	func showAlert(_ title: String, message: String?) {
		let alertError = UIAlertController(title: title,
		                                   message: message,
		                                   preferredStyle: .alert)
		alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
		mainViewController.present(alertError, animated: true)
	}

	func flashMessage(title: String?, message: String, duration: TimeInterval) {
		let MAX_ALPHA: CGFloat = 0.8

		if let attrText = NSMutableAttributedString(withHtmlString: message,
		                                            textColor: UIColor.white,
		                                            backgroundColor: UIColor.black),
			attrText.length > 0
		{
			if let title = title {
				let attrTitle = NSMutableAttributedString(string: title + "\n\n", attributes: [
					.foregroundColor: UIColor.white,
					.backgroundColor: UIColor.black
				])
				attrTitle.append(attrText)
				flashLabel.attributedText = attrTitle
			} else {
				flashLabel.attributedText = attrText
			}
		} else {
			if let title = title {
				flashLabel.text = title + "\n\n" + message
			} else {
				flashLabel.text = message
			}
		}

		if flashLabel.isHidden {
			// animate in
			flashLabel.alpha = 0.0
			flashLabel.isHidden = false
			UIView.animate(withDuration: 0.25, animations: {
				self.flashLabel.alpha = MAX_ALPHA
			})
		} else {
			// already displayed
			flashLabel.layer.removeAllAnimations()
			flashLabel.alpha = MAX_ALPHA
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: {
			UIView.animate(withDuration: 0.35, animations: {
				self.flashLabel.alpha = 0.0
			}) { finished in
				if finished, self.flashLabel.layer.presentation()?.opacity == 0.0 {
					self.flashLabel.isHidden = true
				}
			}
		})
	}

	func flashMessage(title: String?, message: String) {
		flashMessage(title: title, message: message, duration: 0.7)
	}

	func presentError(title: String?, error: Error, flash: Bool) {
		if lastErrorDate == nil || Date().timeIntervalSince(lastErrorDate ?? Date()) > 3.0 {
			var title = title ?? NSLocalizedString("Error", comment: "")
			var text = error.localizedDescription

			var isNetworkError = false
			var ignoreButton: String?
			let userInfo = (error as NSError).userInfo
			if userInfo["NSErrorFailingURLKey"] != nil {
				isNetworkError = true
			}
			if let underError = userInfo["NSUnderlyingError"] as? NSError,
			   (underError.domain as CFString) == kCFErrorDomainCFNetwork
			{
				isNetworkError = true
			}
			if let error = error as? UrlSessionError,
			   case let .badStatusCode(_, html) = error,
			   html.count > 20
			{
				text = html
			}

			if isNetworkError {
				if let ignoreNetworkErrorsUntilDate = ignoreNetworkErrorsUntilDate {
					if Date().timeIntervalSince(ignoreNetworkErrorsUntilDate) >= 0 {
						self.ignoreNetworkErrorsUntilDate = nil
					}
				}
				if ignoreNetworkErrorsUntilDate != nil {
					return
				}
				title = NSLocalizedString("Network error", comment: "")
				ignoreButton = NSLocalizedString("Ignore", comment: "")
			}

			if flash {
				flashMessage(title: title, message: text, duration: 0.9)
			} else {
				let alertError = UIAlertController(title: title, message: text, preferredStyle: .alert)
				if let attrText = NSMutableAttributedString(withHtmlString: text,
				                                            textColor: UIColor.black,
				                                            backgroundColor: UIColor.white)
				{
					alertError.setValue(attrText, forKey: "attributedMessage")
				}
				alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                                   style: .cancel, handler: nil))
				if let ignoreButton = ignoreButton {
					alertError.addAction(UIAlertAction(title: ignoreButton, style: .default, handler: { [self] _ in
						// ignore network errors for a while
						ignoreNetworkErrorsUntilDate = Date().addingTimeInterval(5 * 60.0)
					}))
				}
				mainViewController.present(alertError, animated: true)
			}
		}
		if !flash {
			lastErrorDate = Date()
		}
	}

	func ask(toRate uploadCount: Int) {
		let countLog10 = log10(Double(uploadCount))
		if uploadCount > 1, countLog10 == floor(countLog10) {
			let title = String.localizedStringWithFormat(
				NSLocalizedString("You've uploaded %ld changesets with this version of Go Map!!\n\nRate this app?",
				                  comment: ""),
				uploadCount)
			let alertViewRateApp = UIAlertController(
				title: title,
				message: NSLocalizedString(
					"Rating this app makes it easier for other mappers to discover it and increases the visibility of OpenStreetMap.",
					comment: ""),
				preferredStyle: .alert)
			alertViewRateApp.addAction(UIAlertAction(
				title: NSLocalizedString("Maybe later...", comment: "rate the app later"),
				style: .cancel,
				handler: { _ in
				}))
			alertViewRateApp.addAction(UIAlertAction(
				title: NSLocalizedString("I'll do it!", comment: "rate the app now"),
				style: .default,
				handler: { [self] _ in
					showInAppStore()
				}))
			mainViewController.present(alertViewRateApp, animated: true)
		}
	}

	func showInAppStore() {
		let appStoreId = 592_990211
#if true
		let urlText = "itms-apps://itunes.apple.com/app/id\(appStoreId)"
		let url = URL(string: urlText)
		if let url = url {
			UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
#else
		let spvc = SKStoreProductViewController()
		spvc.delegate = self // self is the view controller to present spvc
		spvc.loadProduct(
			withParameters: [
				SKStoreProductParameterITunesItemIdentifier: NSNumber(value: appStoreId)
			],
			completionBlock: { [self] result, _ in
				if result {
					viewController.present(spvc, animated: true)
				}
			})
#endif
	}

	func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
		(viewController.delegate as? UIViewController)?.dismiss(animated: true)
	}

	@IBAction func requestAerialServiceAttribution(_ sender: Any) {
		let aerial = aerialLayer.tileServer
		if aerial.isBingAerial() {
			// present bing metadata
			mainViewController.performSegue(withIdentifier: "BingMetadataSegue", sender: self)
		} else if aerial.attributionUrl.count > 0 {
			// open the attribution url
			if let url = URL(string: aerial.attributionUrl) {
				let safariViewController = SFSafariViewController(url: url)
				mainViewController.present(safariViewController, animated: true)
			}
		}
	}

	private func promptForBetterBackgroundImagery() {
		if aerialLayer.isHidden {
			return
		}

		// Check if we've moved a long distance from the last check
		let latLon = screenCenterLatLon()
		if let prevLatLonData = UserPrefs.shared.latestAerialCheckLatLon.value,
		   let prevLatLon = try? PropertyListDecoder().decode(LatLon.self, from: prevLatLonData),
		   GreatCircleDistance(latLon, prevLatLon) < 10 * 1000
		{
			return
		}

		if !tileServerList.currentServer.coversLocation(latLon) {
			// current imagery layer doesn't exist at current location
			let best = tileServerList.bestService(at: latLon) ?? tileServerList.builtinServers()[0]
			tileServerList.currentServer = best
			setAerialTileServer(best)
		} else if mapTransform.zoom() < 15 {
			// return here instead of updating last check location
			return
		} else if !tileServerList.currentServer.best,
		          tileServerList.currentServer.isGlobalImagery(),
		          let best = tileServerList.bestService(at: latLon)
		{
			// There's better imagery available at this location
			var message = NSLocalizedString(
				"Better background imagery is available for your location. Would you like to change to it?",
				comment: "")
			message += "\n\n"
			message += best.name
			if best.description != "",
			   best.description != best.name
			{
				message += "\n\n"
				message += best.description
			}
			let alert = UIAlertController(title: NSLocalizedString("Better imagery available", comment: ""),
			                              message: message,
			                              preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .cancel,
			                              handler: nil))
			alert.addAction(UIAlertAction(title: NSLocalizedString("Change", comment: ""), style: .default,
			                              handler: { _ in
			                              	self.tileServerList.currentServer = best
			                              	self.setAerialTileServer(best)
			                              }))
			mainViewController.present(alert, animated: true)
		}

		UserPrefs.shared.latestAerialCheckLatLon.value = try? PropertyListEncoder().encode(latLon)
	}

	func updateCurrentRegionForLocationUsingCountryCoder() {
		if editorLayer.isHidden {
			return
		}

		// if we moved a significant distance then check our location
		let latLon = screenCenterLatLon()
		if GreatCircleDistance(latLon, currentRegion.latLon) < 10 * 1000 {
			return
		}

		let regions = CountryCoder.shared.regionsAt(latLon)
		currentRegion = CurrentRegion(latLon: latLon,
		                              country: CountryCoder.countryforRegions(regions),
		                              regions: CountryCoder.regionsStringsForRegions(regions))
	}

	func unnamedRoadLayer() -> MercatorTileLayer? {
		let noName = TileServer.noName.identifier
		for layer in backgroundLayers {
			if case let .tileLayer(layer) = layer,
			   layer.tileServer.identifier == noName
			{
				return layer
			}
		}
		return nil
	}

	// MARK: Rotate object

	func startObjectRotation() {
		// remove previous rotation in case user pressed Rotate button twice
		endObjectRotation()

		guard let rotateObjectCenter = editorLayer.selectedNode?.latLon
			?? editorLayer.selectedWay?.centerPoint()
			?? editorLayer.selectedRelation?.centerPoint()
		else {
			return
		}
		removePin()
		let rotateObjectOverlay = CAShapeLayer()
		let radiusInner: CGFloat = 70
		let radiusOuter: CGFloat = 90
		let arrowWidth: CGFloat = 60
		let center = mapTransform.screenPoint(forLatLon: rotateObjectCenter, birdsEye: true)
		let path = UIBezierPath(
			arcCenter: center,
			radius: radiusInner,
			startAngle: .pi / 2,
			endAngle: .pi,
			clockwise: false)
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2 + arrowWidth / 2, y: center.y))
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2, y: center.y + arrowWidth / sqrt(2.0)))
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2 - arrowWidth / 2, y: center.y))
		path.addArc(withCenter: center, radius: radiusOuter, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
		path.close()
		rotateObjectOverlay.path = path.cgPath
		rotateObjectOverlay.fillColor = UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.4).cgColor
		rotateObjectOverlay.zPosition = ZLAYER.ROTATEGRAPHIC.rawValue
		layer.addSublayer(rotateObjectOverlay)

		isRotateObjectMode = (rotateObjectOverlay, rotateObjectCenter)
	}

	func endObjectRotation() {
		isRotateObjectMode?.rotateObjectOverlay.removeFromSuperlayer()
		placePushpinForSelection()
		editorLayer.dragState.confirmDrag = false
		isRotateObjectMode = nil
	}

	func viewStateWillChangeTo(_ state: MapViewState, overlays: MapViewOverlays, zoomedOut: Bool) {
		if viewState == state, viewOverlayMask == overlays, viewStateZoomedOut == zoomedOut {
			// no change
			return
		}

		func StateFor(_ state: MapViewState, zoomedOut: Bool) -> MapViewState {
			if zoomedOut, state == .EDITOR { return .BASEMAP }
			if zoomedOut, state == .EDITORAERIAL { return .AERIAL }
			return state
		}
		func OverlaysFor(_ state: MapViewState, overlays: MapViewOverlays, zoomedOut: Bool) -> MapViewOverlays {
			if zoomedOut, state == .EDITORAERIAL { return overlays.union(.LOCATOR) }
			return overlays
		}

		// Things are complicated because the user has their own preference for the view
		// but when they zoom out we make automatic substitutions:
		// 	Editor only --> Basemap
		//	Editor+Aerial --> Aerial+Locator
		let oldState = StateFor(viewState, zoomedOut: viewStateZoomedOut)
		let newState = StateFor(state, zoomedOut: zoomedOut)
		let oldOverlays = OverlaysFor(viewState, overlays: viewOverlayMask, zoomedOut: viewStateZoomedOut)
		let newOverlays = OverlaysFor(state, overlays: overlays, zoomedOut: zoomedOut)
		if newState == oldState, newOverlays == oldOverlays {
			return
		}

		CATransaction.begin()
		CATransaction.setAnimationDuration(0.5)

		locatorLayer.isHidden = !newOverlays.contains(.LOCATOR) || locatorLayer.tileServer.apiKey == ""

		aerialAlignmentButton.isHidden = true
		dPadView.isHidden = true

		switch newState {
		case MapViewState.EDITOR:
			editorLayer.isHidden = false
			aerialLayer.isHidden = true
			basemapLayer.isHidden = true
			userInstructionLabel.isHidden = true
			editorLayer.whiteText = true
		case MapViewState.EDITORAERIAL:
			aerialLayer.tileServer = tileServerList.currentServer
			editorLayer.isHidden = false
			aerialLayer.isHidden = false
			basemapLayer.isHidden = true
			userInstructionLabel.isHidden = true
			editorLayer.whiteText = true
			aerialAlignmentButton.isHidden = false
		case MapViewState.AERIAL:
			aerialLayer.tileServer = tileServerList.currentServer
			editorLayer.isHidden = true
			aerialLayer.isHidden = false
			basemapLayer.isHidden = true
			userInstructionLabel.isHidden = true
		case MapViewState.BASEMAP:
			editorLayer.isHidden = true
			aerialLayer.isHidden = true
			basemapLayer.isHidden = false
			userInstructionLabel.isHidden = state != .EDITOR && state != .EDITORAERIAL
			if !userInstructionLabel.isHidden {
				userInstructionLabel.text = NSLocalizedString("Zoom to Edit", comment: "")
			}
		}
		quadDownloadLayer?.isHidden = editorLayer.isHidden

		if let noName = unnamedRoadLayer() {
			noName.isHidden = !editorLayer.isHidden
		}

		CATransaction.commit()

		DispatchQueue.main.async {
			// Async because the state change hasn't happened yet.
			// This entire function should be based on didChange instead of willChange.
			self.updateMapMarkersFromServer(withDelay: 0, including: [])
		}

		// enable/disable editing buttons based on visibility
		mainViewController.updateUndoRedoButtonState()
		updateAerialAttributionButton()
		addNodeButton.isHidden = editorLayer.isHidden

		editorLayer.whiteText = !aerialLayer.isHidden
	}

	func setAerialTileServer(_ service: TileServer) {
		aerialLayer.tileServer = service
		updateAerialAttributionButton()
		// update imagery offset
		aerialLayer.imageryOffsetMeters = CGPointZero
		updateAerialAlignmentButton()
	}

	func metersPerPixel() -> Double {
		return mapTransform.metersPerPixel(atScreenPoint: crossHairs.position)
	}

	func distance(from: CGPoint, to: CGPoint) -> Double {
		return mapTransform.distance(from: from, to: to)
	}

	func boundingMapRectForScreen() -> OSMRect {
		let rc = OSMRect(layer.bounds)
		return mapTransform.boundingMapRect(forScreenRect: rc)
	}

	func screenLatLonRect() -> OSMRect {
		let rc = boundingMapRectForScreen()
		let rect = MapTransform.latLon(forMapRect: rc)
		return rect
	}

	func screenCenterLatLon() -> LatLon {
		return mapTransform.latLon(forScreenPoint: centerPoint())
	}

	// MARK: Set location

	// Try not to call this directly, since scale isn't something exposed.
	// Use one of the centerOn() functions instead.
	private func setTransformFor(latLon: LatLon, scale: Double? = nil) {
		var lat = latLon.lat
		lat = min(lat, MapTransform.latitudeLimit)
		lat = max(lat, -MapTransform.latitudeLimit)
		let latLon2 = LatLon(latitude: lat, longitude: latLon.lon)
		let point = mapTransform.screenPoint(forLatLon: latLon2, birdsEye: false)
		let center = crossHairs.position
		let delta = CGPoint(x: center.x - point.x, y: center.y - point.y)
		adjustOrigin(by: delta)

		if let scale = scale {
			let ratio = scale / screenFromMapTransform.scale()
			adjustZoom(by: CGFloat(ratio), aroundScreenPoint: crossHairs.position)
		}
	}

	// center without changing zoom
	func centerOn(latLon: LatLon) {
		setTransformFor(latLon: latLon, scale: nil)
	}

	func centerOn(latLon: LatLon, zoom: Double) {
		let scale = pow(2.0, zoom)
		setTransformFor(latLon: latLon,
		                scale: scale)
	}

	func centerOn(latLon: LatLon, metersWide: Double) {
		let degrees = metersToDegrees(meters: metersWide, latitude: latLon.lat)
		let scale = 360 / (degrees / 2)
		setTransformFor(latLon: latLon,
		                scale: scale)
	}

	func centerOn(_ location: MapLocation) {
		let zoom = location.zoom > 0 ? location.zoom : 21.0
		let latLon = LatLon(latitude: location.latitude, longitude: location.longitude)
		centerOn(latLon: latLon,
		         zoom: zoom)
		let rotation = location.direction * .pi / 180.0 + screenFromMapTransform.rotation()
		rotate(by: CGFloat(-rotation), aroundScreenPoint: crossHairs.position)
		if let state = location.viewState {
			viewState = state
		}
	}

	// MARK: Discard stale data

	func discardStaleData() {
		if enableAutomaticCacheManagement {
			let changed = editorLayer.mapData.discardStaleData()
			if changed {
				flashMessage(title: nil, message: NSLocalizedString("Cache trimmed", comment: ""))
				editorLayer.updateMapLocation() // download data if necessary
			}
		}
	}

	// MARK: Progress indicator

	func progressIncrement(_ delta: Int = 1) {
		if progressActive.value() == 0, delta > 0 {
			progressIndicator.startAnimating()
		}
		progressActive.increment(delta)
	}

	func progressDecrement() {
		progressActive.decrement()
		if progressActive.value() == 0 {
			progressIndicator.stopAnimating()
		}
#if DEBUG
		if progressActive.value() < 0 {
			print("progressDecrement = \(progressActive.value())")
		}
#endif
	}

	// MARK: Aerial imagery alignment

	@IBAction func aerialAlignmentPressed(_ sender: Any) {
		dPadView.isHidden = !dPadView.isHidden
	}

	func updateAerialAlignmentButton() {
		let offset = aerialLayer.imageryOffsetMeters
		let buttonText: String
		if offset == CGPointZero {
			buttonText = "(0,0)"
		} else {
			buttonText = String(format: "(%.1f,%.1f)", arguments: [offset.x, offset.y])
		}
		UIView.performWithoutAnimation {
			aerialAlignmentButton.setTitle(buttonText, for: .normal)
			aerialAlignmentButton.layoutIfNeeded()
		}
	}

	func dPadPress(_ shift: CGPoint) {
		let scale = 0.5
		let newOffset = aerialLayer.imageryOffsetMeters.plus(CGPoint(x: shift.x * scale, y: shift.y * scale))
		aerialLayer.imageryOffsetMeters = newOffset
		updateAerialAlignmentButton()
	}

	// MARK: GPS and Location Manager

	func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
		if locationManagerExtraneousNotification {
			// filter out extraneous notification we get when initializing CL
			//
			locationManagerExtraneousNotification = false
			return
		}

		var ok = false
		switch status {
		case .authorizedAlways, .authorizedWhenInUse:
			ok = true
		case .notDetermined, .restricted, .denied:
			fallthrough
		default:
			ok = false
		}
		mainViewController.setGpsState(ok ? .LOCATION : .NONE)
	}

	@IBAction func center(onGPS sender: Any) {
		if gpsState == .NONE {
			return
		}

		userOverrodeLocationPosition = false
		if let location = locationManager.location {
			centerOn(latLon: LatLon(location.coordinate))
		}
	}

	@IBAction func compassPressed(_ sender: Any) {
		switch gpsState {
		case .HEADING:
			gpsState = .LOCATION
			rotateToNorth()
		case .LOCATION:
			gpsState = .HEADING
			rotateToHeading()
		case .NONE:
			rotateToNorth()
		}
	}

	func updateUserLocationIndicator(_ location: CLLocation?) {
		if !locationBallLayer.isHidden {
			// set new position
			guard let location = location ?? locationManager.location else { return }
			let coord = LatLon(location.coordinate)
			var point = mapTransform.screenPoint(forLatLon: coord, birdsEye: true)
			point = mapTransform.wrappedScreenPoint(point, screenBounds: bounds)
			locationBallLayer.position = point

			// set location accuracy
			let meters = location.horizontalAccuracy
			var pixels = CGFloat(meters / metersPerPixel())
			if pixels == 0.0 {
				pixels = 100.0
			}
			locationBallLayer.radiusInPixels = pixels
		}
	}

	func heading(for clHeading: CLHeading) -> Double {
		var heading = clHeading.trueHeading * .pi / 180
		switch UIApplication.shared.statusBarOrientation {
		case .portraitUpsideDown:
			heading += .pi
		case .landscapeLeft:
			heading += .pi / 2
		case .landscapeRight:
			heading -= .pi / 2
		case .portrait:
			fallthrough
		default:
			break
		}
		return heading
	}

	func updateHeadingSmoothed(_ heading: Double, accuracy: Double) {
		let screenAngle = screenFromMapTransform.rotation()

		if gpsState == .HEADING {
			// rotate to new heading
			let center = centerPoint()
			let delta = -(heading + screenAngle)
			rotate(by: CGFloat(delta), aroundScreenPoint: center)
		} else if !locationBallLayer.isHidden {
			// rotate location ball
			locationBallLayer.headingAccuracy = CGFloat(accuracy * (.pi / 180))
			locationBallLayer.showHeading = true
			locationBallLayer.heading = CGFloat(heading + screenAngle - .pi / 2)
		}
	}

	private var locationManagerSmoothHeading = 0.0
	func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
		let accuracy = newHeading.headingAccuracy
		let heading = self.heading(for: newHeading)

		DisplayLink.shared.addName("smoothHeading", block: { [self] in
			var delta = heading - self.locationManagerSmoothHeading
			if delta > .pi {
				delta -= 2 * .pi
			} else if delta < -.pi {
				delta += 2 * .pi
			}
			delta *= 0.15
			if abs(delta) < 0.001 {
				self.locationManagerSmoothHeading = heading
			} else {
				self.locationManagerSmoothHeading += delta
			}
			updateHeadingSmoothed(self.locationManagerSmoothHeading, accuracy: accuracy)
			if heading == self.locationManagerSmoothHeading {
				DisplayLink.shared.removeName("smoothHeading")
			}
		})
	}

	@objc func locationUpdated(to newLocation: CLLocation) {
		if gpsState == .NONE {
			// sometimes we get a notification after turning off notifications
			DLog("discard location notification")
			return
		}

		if newLocation.timestamp < Date(timeIntervalSinceNow: -10.0) {
			// its old data
			DLog("discard old GPS data: \(newLocation.timestamp), \(Date())\n")
			return
		}

		// check if we moved an appreciable distance
		let p1 = LatLon(newLocation.coordinate)
		let p2 = LatLon(currentLocation.coordinate)
		let delta = GreatCircleDistance(p1, p2)
		if !locationBallLayer.isHidden, delta < 0.1,
		   abs(newLocation.horizontalAccuracy - currentLocation.horizontalAccuracy) < 1.0
		{
			return
		}
		currentLocation = newLocation

		if let voiceAnnouncement = voiceAnnouncement,
		   !editorLayer.isHidden
		{
			voiceAnnouncement.announce(forLocation: LatLon(newLocation.coordinate))
		}

		if gpxLayer.activeTrack != nil {
			gpxLayer.addPoint(newLocation)
		}

		if gpsState == .NONE {
			locating = false
		}

		let pp = mapTransform.latLon(forScreenPoint: pushPin?.arrowPoint ?? CGPoint.zero)

		if !userOverrodeLocationPosition {
			// move view to center on new location
			if userOverrodeLocationZoom {
				centerOn(latLon: LatLon(newLocation.coordinate))
			} else {
				centerOn(latLon: LatLon(newLocation.coordinate),
				         metersWide: 20.0)
			}
		}

		pushPin?.arrowPoint = mapTransform.screenPoint(forLatLon: pp, birdsEye: true)
		updateUserLocationIndicator(newLocation)
	}

	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		for location in locations {
			locationUpdated(to: location)
		}
	}

	func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
		print("GPS paused by iOS\n")
	}

	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
		var error = error
		let controller = mainViewController
		if (error as? CLError)?.code == CLError.Code.denied {
			controller.setGpsState(GPS_STATE.NONE)
			if !isLocationSpecified() {
				// go home
				centerOn(latLon: LatLon(latitude: 47.6858, longitude: -122.1917),
				         metersWide: 50.0)
			}
			var text = String.localizedStringWithFormat(
				NSLocalizedString(
					"Ensure Location Services is enabled and you have granted this application access.\n\nError: %@",
					comment: ""),
				error.localizedDescription)
			text = NSLocalizedString("The current location cannot be determined: ", comment: "") + text
			error = NSError(domain: "Location", code: 100, userInfo: [
				NSLocalizedDescriptionKey: text
			])
			presentError(title: nil, error: error, flash: false)
		} else {
			// driving through a tunnel or something
			let text = NSLocalizedString("Location unavailable", comment: "")
			error = NSError(domain: "Location", code: 100, userInfo: [
				NSLocalizedDescriptionKey: text
			])
			presentError(title: nil, error: error, flash: true)
		}
	}

	// MARK: Undo/Redo

	func placePushpinForSelection(at point: CGPoint? = nil) {
		guard let selection = editorLayer.selectedPrimary
		else {
			removePin()
			return
		}

		// Make sure editor is visible
		switch viewState {
		case .AERIAL, .BASEMAP:
			viewState = .EDITORAERIAL
		case .EDITOR, .EDITORAERIAL:
			break
		}

		let loc: LatLon
		if let point = point {
			let latLon = mapTransform.latLon(forScreenPoint: point)
			loc = selection.latLonOnObject(forLatLon: latLon)
		} else {
			loc = selection.selectionPoint()
		}

		let point = mapTransform.screenPoint(forLatLon: loc, birdsEye: true)
		placePushpin(at: point, object: selection)

		if viewStateZoomedOut {
			// set location and zoom in
			centerOn(latLon: loc, metersWide: 30.0)
		} else if !bounds.contains(pushPin!.arrowPoint) {
			// set location without changing zoom
			centerOn(latLon: loc)
		}
	}

	@IBAction func undo(_ sender: Any?) {
		if editorLayer.isHidden {
			flashMessage(title: nil, message: NSLocalizedString("Editing layer not visible", comment: ""))
			return
		}
		// if just dropped a pin then undo removes the pin
		if pushPin != nil, editorLayer.selectedPrimary == nil {
			removePin()
			return
		}

		removePin()
		editorLayer.undo()
	}

	@IBAction func redo(_ sender: Any?) {
		if editorLayer.isHidden {
			flashMessage(title: nil, message: NSLocalizedString("Editing layer not visible", comment: ""))
			return
		}
		removePin()
		editorLayer.redo()
	}

	// MARK: Resize & movement

	func isLocationSpecified() -> Bool {
		return !(screenFromMapTransform == .identity)
	}

	func adjustOrigin(by delta: CGPoint) {
		if delta.x == 0.0, delta.y == 0.0 {
			return
		}

		let o = OSMTransform.translation(Double(delta.x), Double(delta.y))
		let t = screenFromMapTransform.concat(o)
		screenFromMapTransform = t
	}

	func adjustZoom(by ratio: CGFloat, aroundScreenPoint zoomCenter: CGPoint) {
		guard ratio != 1.0,
		      isRotateObjectMode == nil
		else {
			return
		}

		let maxZoomIn = Double(Int(1) << 30)

		let scale = screenFromMapTransform.scale()
		var ratio = Double(ratio)
		if ratio * scale < 1.0 {
			ratio = 1.0 / scale
		}
		if ratio * scale > maxZoomIn {
			ratio = maxZoomIn / scale
		}

		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(zoomCenter), birdsEye: false)
		var t = screenFromMapTransform
		t = t.translatedBy(dx: offset.x, dy: offset.y)
		t = t.scaledBy(ratio)
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		screenFromMapTransform = t
	}

	func rotate(by angle: CGFloat, aroundScreenPoint zoomCenter: CGPoint) {
		if angle == 0.0 {
			return
		}

		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(zoomCenter), birdsEye: false)
		var t = screenFromMapTransform
		t = t.translatedBy(dx: offset.x, dy: offset.y)
		t = t.rotatedBy(Double(angle))
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		screenFromMapTransform = t

		let screenAngle = screenFromMapTransform.rotation()
		compassButton.rotate(angle: CGFloat(screenAngle))
		if !locationBallLayer.isHidden {
			if gpsState == .HEADING, abs(locationBallLayer.heading - -.pi / 2) < 0.0001 {
				// don't pin location ball to North until we've animated our rotation to north
				locationBallLayer.heading = -.pi / 2
			} else {
				if let heading = locationManager.heading {
					let heading = self.heading(for: heading)
					locationBallLayer.heading = CGFloat(screenAngle + heading - .pi / 2)
				}
			}
		}
	}

	func animateRotation(by deltaHeading: Double, aroundPoint center: CGPoint) {
		var deltaHeading = deltaHeading
		// don't rotate the long way around
		while deltaHeading < -.pi {
			deltaHeading += 2 * .pi
		}
		while deltaHeading > .pi {
			deltaHeading -= 2 * .pi
		}

		if abs(deltaHeading) < 0.00001 {
			return
		}

		let startTime = CACurrentMediaTime()

		let duration = 0.4
		var prevHeading: Double = 0
		weak var weakSelf = self
		DisplayLink.shared.addName(DisplayLinkHeading, block: {
			if let myself = weakSelf {
				var elapsedTime = CACurrentMediaTime() - startTime
				if elapsedTime > duration {
					elapsedTime = CFTimeInterval(duration) // don't want to over-rotate
				}
				// Rotate using an ease-in/out curve. This ensures that small changes in direction don't cause jerkiness.
				// result = interpolated value, t = current time, b = initial value, c = delta value, d = duration
				func easeInOutQuad(_ t: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
					var t = t
					t /= d / 2
					if t < 1 {
						return c / 2 * t * t + b
					}
					t -= 1
					return -c / 2 * (t * (t - 2) - 1) + b
				}
				let miniHeading = easeInOutQuad(elapsedTime, 0, deltaHeading, duration)
				myself.rotate(by: CGFloat(miniHeading - prevHeading), aroundScreenPoint: center)
				prevHeading = miniHeading
				if elapsedTime >= duration {
					DisplayLink.shared.removeName(DisplayLinkHeading)
				}
			}
		})
	}

	func rotateBirdsEye(by angle: Double) {
		var angle = angle
		// limit maximum rotation
		var t = screenFromMapTransform
		let maxRotation = Double(65 * (Double.pi / 180))
#if TRANSFORM_3D
		let currentRotation = atan2(t.m23, t.m22)
#else
		let currentRotation = Double(mapTransform.birdsEyeRotation)
#endif
		if currentRotation + angle > maxRotation {
			angle = maxRotation - currentRotation
		}
		if currentRotation + Double(angle) < 0 {
			angle = -currentRotation
		}

		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(centerPoint()), birdsEye: false)

		t = t.translatedBy(dx: offset.x, dy: offset.y)
#if TRANSFORM_3D
		t = CATransform3DRotate(t, delta, 1.0, 0.0, 0.0)
#else
		mapTransform.birdsEyeRotation += angle
#endif
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		screenFromMapTransform = t

		if !locationBallLayer.isHidden {
			updateUserLocationIndicator(nil)
		}
	}

	func rotateToNorth() {
		// Rotate to face North
		let center = centerPoint()
		let rotation = screenFromMapTransform.rotation()
		animateRotation(by: -rotation, aroundPoint: center)
	}

	func rotateToHeading() {
		// Rotate to face current compass heading
		if let heading = locationManager.heading {
			let center = centerPoint()
			let screenAngle = screenFromMapTransform.rotation()
			let heading = self.heading(for: heading)
			animateRotation(by: -(screenAngle + heading), aroundPoint: center)
		}
	}

	// MARK: Key presses

	/// Offers the option to either merge tags or replace them with the copied tags.
	/// - Parameter sender: nil
	override func paste(_ sender: Any?) {
		editorLayer.pasteTags()
	}

	override func delete(_ sender: Any?) {
		editorLayer.deleteCurrentSelection()
	}

#if !os(iOS)
	func keyDown(_ event: NSEvent?) {
		let chars = event?.characters
		let character = unichar(chars?[chars?.index(chars?.startIndex, offsetBy: 0)] ?? 0)
		var angle = 0.0
		switch character {
		case unichar(NSLeftArrowFunctionKey):
			angle = .pi * -1 / 180
		case unichar(NSRightArrowFunctionKey):
			angle = .pi * 1 / 180
		default:
			break
		}
		if angle != 0.0 {
			mapTransform = OSMTransformRotate(mapTransform, angle)
		}
	}
#endif

	// show/hide edit control based on selection
	func updateEditControl() {
		let show = pushPin != nil || editorLayer.selectedPrimary != nil
		editControl.isHidden = !show
		if show {
			if editorLayer.selectedPrimary == nil {
				// brand new node
				if editorLayer.canPasteTags() {
					editControlActions = [.EDITTAGS, .ADDNOTE, .PASTETAGS]
				} else {
					editControlActions = [.EDITTAGS, .ADDNOTE]
				}
			} else {
				if let relation = editorLayer.selectedPrimary?.isRelation() {
					if relation.isRestriction() {
						editControlActions = [.EDITTAGS, .PASTETAGS, .RESTRICT]
					} else if relation.isMultipolygon() {
						editControlActions = [.EDITTAGS, .PASTETAGS, .MORE]
					} else {
						editControlActions = [.EDITTAGS, .PASTETAGS]
					}
				} else {
					editControlActions = [.EDITTAGS, .PASTETAGS, .DELETE, .MORE]
				}
			}
			editControl.removeAllSegments()
			for action in editControlActions {
				let title: String = action.actionTitle(abbreviated: true)
				editControl.insertSegment(withTitle: title,
				                          at: editControl.numberOfSegments,
				                          animated: false)
			}
			// mark segment labels as adjustsFontSizeToFitWidth
			for segment in editControl.subviews {
				for label in segment.subviews {
					guard let label = label as? UILabel else {
						continue
					}
					label.adjustsFontSizeToFitWidth = true
				}
			}
		}
	}

	func presentEditActionSheet(_ sender: Any?) {
		let actionList = editorLayer.editActionsAvailable()
		if actionList.isEmpty {
			// nothing selected
			return
		}

		let actionSheet = UIAlertController(
			title: NSLocalizedString("Perform Action", comment: ""),
			message: nil,
			preferredStyle: .actionSheet)
		for value in actionList {
			let title = value.actionTitle()
			actionSheet.addAction(UIAlertAction(title: title, style: .default, handler: { [self] _ in
				editorLayer.performEdit(value)
			}))
		}
		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
		                                    style: .cancel,
		                                    handler: nil))
		mainViewController.present(actionSheet, animated: true)

		// compute location for action sheet to originate
		var button = editControl.bounds
		let segmentWidth = button.size.width /
			CGFloat(editControl.numberOfSegments) // hack because we can't get the frame for an individual segment
		button.origin.x += button.size.width - segmentWidth
		button.size.width = segmentWidth
		actionSheet.popoverPresentationController?.sourceView = editControl
		actionSheet.popoverPresentationController?.sourceRect = button
	}

	@IBAction func editControlAction(_ sender: Any) {
		// get the selected button: has to be done before modifying the node/way selection
		guard let segmentedControl = sender as? UISegmentedControl else { return }
		let segment = segmentedControl.selectedSegmentIndex
		if segment >= 0, segment < editControlActions.count {
			let action = editControlActions[segment]
			editorLayer.performEdit(action)
		}
		segmentedControl.selectedSegmentIndex = UISegmentedControl.noSegment
	}

	@IBAction func presentTagEditor(_ sender: Any?) {
		mainViewController.performSegue(withIdentifier: "poiSegue", sender: nil)
	}

	// Turn restriction panel
	func presentTurnRestrictionEditor() {
		guard let selectedPrimary = editorLayer.selectedPrimary,
		      let pushPin = pushPin
		else { return }

		let showRestrictionEditor: (() -> Void) = { [self] in
			guard let myVc = mainViewController.storyboard?
				.instantiateViewController(withIdentifier: "TurnRestrictController") as? TurnRestrictController
			else { return }
			myVc.centralNode = editorLayer.selectedNode
			myVc.modalPresentationStyle = UIModalPresentationStyle.overCurrentContext
			mainViewController.present(myVc, animated: true)

			// if GPS is running don't keep moving around
			userOverrodeLocationPosition = true

			// scroll view so intersection stays visible
			let rc = myVc.viewWithTitle.frame
			let pt = pushPin.arrowPoint
			let delta = CGPoint(x: Double(bounds.midX - pt.x), y: Double(bounds.midY - rc.size.height / 2 - pt.y))
			adjustOrigin(by: delta)
		}

		// check if this is a fancy relation type we don't support well
		let restrictionEditWarning: ((OsmNode?) -> Void) = { [self] viaNode in
			var warn = false
			if let parentRelations = viaNode?.parentRelations {
				for relation in parentRelations {
					if relation.isRestriction() {
						let type = relation.tags["type"]
						if type?.hasPrefix("restriction:") ?? false || relation.tags["except"] != nil {
							warn = true
						}
					}
				}
			}
			if warn {
				let alert = UIAlertController(
					title: "Unsupported turn restriction type",
					message: """
					One or more turn restrictions connected to this node have extended properties that will not be displayed.\n\n\
					Modififying these restrictions may destroy important information.
					""",
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("Edit restrictions", comment: ""),
				                              style: .destructive,
				                              handler: { _ in
				                              	showRestrictionEditor()
				                              }))
				alert
					.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
					                         style: .cancel,
					                         handler: nil))
				mainViewController.present(alert, animated: true)
			} else {
				showRestrictionEditor()
			}
		}

		// if we currently have a relation selected then select the via node instead

		if let relation = selectedPrimary.isRelation() {
			let fromWay = relation.member(byRole: "from")?.obj?.isWay()
			let viaNode = relation.member(byRole: "via")?.obj?.isNode()

			if viaNode == nil {
				// not supported yet
				showAlert(
					NSLocalizedString("Unsupported turn restriction type", comment: ""),
					message: NSLocalizedString(
						"This app does not yet support editing turn restrictions without a node as the 'via' member",
						comment: ""))
				return
			}

			editorLayer.selectedWay = fromWay
			editorLayer.selectedNode = viaNode
			if editorLayer.selectedNode != nil {
				placePushpinForSelection()
				restrictionEditWarning(editorLayer.selectedNode)
			}
		} else if selectedPrimary.isNode() != nil {
			restrictionEditWarning(editorLayer.selectedNode)
		}
	}

	func removePin() {
		if let pushpinView = pushPin {
			pushpinView.removeFromSuperview()
		}
		pushPin = nil
		updateEditControl()
		magnifyingGlass.isHidden = true
	}

	private func pushpinDragCallbackFor(object: OsmBaseObject) -> PushPinViewDragCallback {
		weak var object = object
		return { [weak self] state, dx, dy in
			guard let self = self else { return }
			switch state {
			case .ended, .cancelled, .failed:
				DisplayLink.shared.removeName("dragScroll")
				let isRotate = self.isRotateObjectMode != nil
				if isRotate {
					self.endObjectRotation()
				}
				self.unblinkObject()
				if let object = object {
					self.editorLayer.dragFinish(object: object, isRotate: isRotate)
				}

			case .began:
				if let pos = self.pushPin?.arrowPoint {
					self.editorLayer.dragBegin(from: pos.minus(CGPoint(x: dx, y: dy)))
				}
				fallthrough // begin state can have movement
			case .changed:
				// define the drag function
				let dragObjectToPushpin: (() -> Void) = { [weak object] in
					if let object = object,
					   let pos = self.pushPin?.arrowPoint
					{
						self.editorLayer.dragContinue(object: object,
						                              toPoint: pos,
						                              isRotateObjectMode: self.isRotateObjectMode)
					}
				}

				// scroll screen if too close to edge
				let MinDistanceSide: CGFloat = 40.0
				let MinDistanceTop = MinDistanceSide + 10.0
				let MinDistanceBottom = MinDistanceSide + 120.0
				let arrow = self.pushPin?.arrowPoint ?? .zero
				let screen = self.bounds
				let SCROLL_SPEED: CGFloat = 10.0
				var scrollx: CGFloat = 0
				var scrolly: CGFloat = 0

				if arrow.x < (screen.origin.x + MinDistanceSide) {
					scrollx = -SCROLL_SPEED
				} else if arrow.x > screen.origin.x + screen.size.width - MinDistanceSide {
					scrollx = SCROLL_SPEED
				}
				if arrow.y < screen.origin.y + MinDistanceTop {
					scrolly = -SCROLL_SPEED
				} else if arrow.y > screen.origin.y + screen.size.height - MinDistanceBottom {
					scrolly = SCROLL_SPEED
				}

				if scrollx != 0.0 || scrolly != 0.0 {
					// if we're dragging at a diagonal then scroll diagonally as well, in the direction the user is dragging
					let center = self.centerPoint()
					let v = Sub(OSMPoint(arrow), OSMPoint(center)).unitVector()
					scrollx = SCROLL_SPEED * CGFloat(v.x)
					scrolly = SCROLL_SPEED * CGFloat(v.y)

					// scroll the screen to keep pushpin centered
					var prevTime = TimeInterval(CACurrentMediaTime())
					DisplayLink.shared.addName("dragScroll", block: { [self] in
						let now = TimeInterval(CACurrentMediaTime())
						let duration = now - prevTime
						prevTime = now
						// scale to 60 FPS assumption, need to move farther if framerate is slow
						let sx = scrollx * CGFloat(duration) * 60.0
						let sy = scrolly * CGFloat(duration) * 60.0
						self.adjustOrigin(by: CGPoint(x: -sx, y: -sy))
						// update position of blink layer
						if let pt = self.blinkLayer?.position.withOffset(-sx, -sy) {
							self.blinkLayer?.position = pt
						}
						dragObjectToPushpin()
					})
				} else {
					DisplayLink.shared.removeName("dragScroll")
				}

				// move the object
				dragObjectToPushpin()

				self.magnifyingGlass.setSourceCenter(arrow, in: self, visible: !self.aerialLayer.isHidden)
			default:
				break
			}
		}
	}

	func placePushpin(at point: CGPoint, object: OsmBaseObject?) {
		removePin()

		editorLayer.dragState.confirmDrag = false
		let pushpinView = PushPinView()
		pushPin = pushpinView
		refreshPushpinText()
		pushpinView.layer.zPosition = ZLAYER.PUSHPIN.rawValue
		pushpinView.arrowPoint = point

		if let object = object {
			pushpinView.dragCallback = pushpinDragCallbackFor(object: object)
		} else {
			pushpinView.dragCallback = { _, _, _ in
				self.magnifyingGlass.setSourceCenter(
					pushpinView.arrowPoint,
					in: self,
					visible: !self.aerialLayer.isHidden)
			}
		}

		if object == nil {
			// do animation if creating a new object
			pushpinView.animateMove(from: CGPoint(x: bounds.origin.x + bounds.size.width,
			                                      y: bounds.origin.y))
		}

		if object == nil {
			// Need (?) graphic at arrow point
			let layer = pushpinView.placeholderLayer
			if (layer.sublayers?.count ?? 0) == 0 {
				layer.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
				layer.cornerRadius = layer.bounds.size.width / 2
				layer.backgroundColor = UIColor(red: 0.0, green: 150 / 255.0, blue: 1.0, alpha: 1.0).cgColor
				layer.masksToBounds = true
				layer.borderColor = UIColor.white.cgColor
				layer.borderWidth = 1.0
				layer.contentsScale = UIScreen.main.scale
				// shadow
				layer.shadowColor = UIColor.black.cgColor
				layer.shadowOffset = CGSize(width: 3, height: 3)
				layer.shadowRadius = 3
				layer.shadowOpacity = 0.5
				layer.masksToBounds = false

				let text = CATextLayer()
				text.foregroundColor = UIColor.white.cgColor
				text.string = "?"
				text.fontSize = 18
				text.font = UIFont.boldSystemFont(ofSize: text.fontSize)
				text.alignmentMode = .center
				text.bounds = layer.bounds
				text.position = CGPoint(x: 0, y: 1)
				text.anchorPoint = CGPoint.zero
				text.contentsScale = UIScreen.main.scale
				layer.addSublayer(text)
			}

			magnifyingGlass.setSourceCenter(pushpinView.arrowPoint, in: self, visible: !aerialLayer.isHidden)
		}

		addSubview(pushpinView)

		updateEditControl()
	}

	func refreshPushpinText() {
		let text = editorLayer.selectedPrimary?.friendlyDescription() ?? NSLocalizedString("(new object)", comment: "")
		pushPin?.text = text
	}

	func unblinkObject() {
		blinkLayer?.removeFromSuperlayer()
		blinkLayer = nil
		blinkObject = nil
		blinkSegment = -1
	}

	func blink(_ object: OsmBaseObject?, segment: Int) {
		guard let object = object else {
			unblinkObject()
			return
		}
		if object == blinkObject, segment == blinkSegment {
			return
		}
		blinkLayer?.removeFromSuperlayer()
		blinkObject = object
		blinkSegment = segment

		// create a layer for the object
		let path = CGMutablePath()
		if let node = object as? OsmNode {
			let center = mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
			var rect = CGRect(x: center.x, y: center.y, width: 0, height: 0)
			rect = rect.insetBy(dx: -10, dy: -10)
			path.addEllipse(in: rect, transform: .identity)
		} else if let way = object as? OsmWay {
			if segment >= 0 {
				assert(way.nodes.count >= segment + 2)
				let n1 = way.nodes[segment]
				let n2 = way.nodes[segment + 1]
				let p1 = mapTransform.screenPoint(forLatLon: n1.latLon, birdsEye: true)
				let p2 = mapTransform.screenPoint(forLatLon: n2.latLon, birdsEye: true)
				path.move(to: CGPoint(x: p1.x, y: p1.y))
				path.addLine(to: CGPoint(x: p2.x, y: p2.y))
			} else {
				var isFirst = true
				for node in way.nodes {
					let pt = mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
					if isFirst {
						path.move(to: CGPoint(x: pt.x, y: pt.y))
					} else {
						path.addLine(to: CGPoint(x: pt.x, y: pt.y))
					}
					isFirst = false
				}
			}
		} else {
			assertionFailure()
		}
		self.blinkLayer = CAShapeLayer()
		guard let blinkLayer = blinkLayer else { fatalError() }
		blinkLayer.path = path
		blinkLayer.fillColor = nil
		blinkLayer.lineWidth = 3.0
		blinkLayer.frame = CGRect(x: 0, y: 0, width: bounds.size.width, height: bounds.size.height)
		blinkLayer.zPosition = ZLAYER.BLINK.rawValue
		blinkLayer.strokeColor = UIColor.black.cgColor

		let dots = CAShapeLayer()
		dots.path = blinkLayer.path
		dots.fillColor = nil
		dots.lineWidth = blinkLayer.lineWidth
		dots.bounds = blinkLayer.bounds
		dots.position = CGPoint.zero
		dots.anchorPoint = CGPoint.zero
		dots.strokeColor = UIColor.white.cgColor
		dots.lineDashPhase = 0.0
		dots.lineDashPattern = [NSNumber(value: 4), NSNumber(value: 4)]
		blinkLayer.addSublayer(dots)

		let dashAnimation = CABasicAnimation(keyPath: "lineDashPhase")
		dashAnimation.fromValue = NSNumber(value: 0.0)
		dashAnimation.toValue = NSNumber(value: -16.0)
		dashAnimation.duration = 0.6
		dashAnimation.repeatCount = Float(CGFloat.greatestFiniteMagnitude)
		dots.add(dashAnimation, forKey: "linePhase")

		layer.addSublayer(blinkLayer)
	}

	// MARK: Map Markers

	// This performs an expensive update with a time delay, coalescing multiple calls
	// into a single update.
	func updateMapMarkersFromServer(withDelay delay: CGFloat, including: MapMarkerDatabase.MapMarkerSet) {
		let delay = max(delay, 0.01)
		var including = including
		if including.isEmpty {
			// compute the list
			if viewOverlayMask.contains(.NOTES) {
				including.insert(.notes)
				including.insert(.fixme)
			}
			if viewOverlayMask.contains(.QUESTS) {
				including.insert(.quest)
			}
			if displayGpxLogs {
				including.insert(.gpx)
			}
		} else if !viewOverlayMask.contains(.QUESTS) {
			including.remove(.quest)
		}

		mapMarkerDatabase.updateRegion(screenLatLonRect(),
		                               withDelay: delay,
		                               mapData: editorLayer.mapData,
		                               including: including,
		                               completion: {
		                               	self.updateMapMarkerButtonPositions()
		                               })
	}

	// This performs an inexpensive update using only data we've already downloaded
	func updateMapMarkerButtonPositions() {
		// need this to disable implicit animation
		UIView.performWithoutAnimation({
			let MaxMarkers = 50
			var count = 0
			// update new and existing buttons
			for marker in self.mapMarkerDatabase.allMapMarkers {
				// Update the location of the button
				let onScreen = updateButtonPositionForMapMarker(marker: marker, hidden: count > MaxMarkers)
				if onScreen {
					count += 1
				}
			}
		})
	}

	// Update the location of the button. Return true if it is on-screen.
	private func updateButtonPositionForMapMarker(marker: MapMarker, hidden: Bool) -> Bool {
		// create buttons that haven't been created
		guard !hidden else {
			marker.button?.isHidden = true
			return false
		}
		if marker.button == nil {
			let button = marker.makeButton()
			button.addTarget(self,
			                 action: #selector(mapMarkerButtonPress(_:)),
			                 for: .touchUpInside)
			button.tag = marker.buttonId
			addSubview(button)
			if let object = marker.object {
				// If marker is associated with an object then the marker needs to be
				// updated when the object changes:
				object.observer = { obj in
					let markers = self.mapMarkerDatabase.refreshMarkersFor(object: obj)
					for marker in markers {
						_ = self.updateButtonPositionForMapMarker(marker: marker, hidden: false)
					}
				}
			}
		}

		// Set position of button
		let button = marker.button!
		button.isHidden = false
		let offsetX = (marker is KeepRightMarker) || (marker is FixmeMarker) ? 0.00001 : 0.0
		let pos = mapTransform.screenPoint(forLatLon: LatLon(latitude: marker.latLon.lat,
		                                                     longitude: marker.latLon.lon + offsetX),
		                                   birdsEye: true)
		if pos.x.isInfinite || pos.y.isInfinite {
			return false
		}
		if let button = button as? LocationButton {
			button.arrowPoint = pos
		} else {
			var rc = button.bounds
			rc = rc.offsetBy(dx: pos.x - rc.size.width / 2,
			                 dy: pos.y - rc.size.height / 2)
			button.frame = rc
		}
		return bounds.contains(pos)
	}

	@objc func mapMarkerButtonPress(_ sender: Any?) {
		guard let button = sender as? UIButton,
		      let marker = mapMarkerDatabase.mapMarker(forButtonId: button.tag)
		else { return }

		var object: OsmBaseObject?
		if let marker = marker as? KeepRightMarker {
			object = marker.object(from: editorLayer.mapData)
		} else {
			object = marker.object
		}

		if !editorLayer.isHidden,
		   let object = object
		{
			editorLayer.selectedNode = object.isNode()
			editorLayer.selectedWay = object.isWay()
			editorLayer.selectedRelation = object.isRelation()

			let pt = object.latLonOnObject(forLatLon: marker.latLon)
			let point = mapTransform.screenPoint(forLatLon: pt, birdsEye: true)
			placePushpin(at: point, object: object)
		}

		if (marker is WayPointMarker) || (marker is KeepRightMarker) {
			let comment = (marker as? WayPointMarker)?.description ?? (marker as? KeepRightMarker)?.description ?? ""
			let title = marker is WayPointMarker ? "Waypoint" : "Keep Right"

			// use regular alertview
			let alertKeepRight = UIAlertController(title: title, message: comment, preferredStyle: .alert)
			alertKeepRight.addAction(
				UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				              style: .cancel,
				              handler: { _ in
				              }))
			if let marker = marker as? KeepRightMarker {
				alertKeepRight.addAction(
					UIAlertAction(title: NSLocalizedString("Ignore", comment: ""),
					              style: .default,
					              handler: { [self] _ in
					              	// they want to hide this button from now on
					              	marker.ignore()
					              	editorLayer.selectedNode = nil
					              	editorLayer.selectedWay = nil
					              	editorLayer.selectedRelation = nil
					              	removePin()
					              }))
			}
			mainViewController.present(alertKeepRight, animated: true)
		} else if let object = object {
			// Fixme marker or Quest marker
			if !editorLayer.isHidden {
				if let marker = marker as? QuestMarker {
					let onClose = {
						// Need to update the QuestMarker icon
						self.updateMapMarkersFromServer(withDelay: 0.0, including: [.quest])
					}
					let vc = QuestSolverController.instantiate(marker: marker,
					                                           object: object,
					                                           onClose: onClose)
					if #available(iOS 15.0, *),
					   let sheet = vc.sheetPresentationController
					{
						sheet.selectedDetentIdentifier = .large
						sheet.prefersScrollingExpandsWhenScrolledToEdge = false
						sheet.detents = [.medium(), .large()]
						sheet.delegate = self
					}
					mainViewController.present(vc, animated: true)
				} else {
					presentTagEditor(nil)
				}
			} else {
				let text: String
				if let fixme = marker as? FixmeMarker,
				   let object = fixme.object
				{
					text = FixmeMarker.fixmeTag(object) ?? ""
				} else if let quest = marker as? QuestMarker {
					text = quest.quest.title
				} else {
					text = ""
				}
				let alert = UIAlertController(title: "\(object.friendlyDescription())",
				                              message: text,
				                              preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
				mainViewController.present(alert, animated: true)
			}
		} else if let note = marker as? OsmNoteMarker {
			mainViewController.performSegue(withIdentifier: "NotesSegue", sender: note)
		}
	}

	// This gets called when the user changes the size of a sheet
	@available(iOS 15.0, *)
	func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
		_ sheetPresentationController: UISheetPresentationController)
	{
		// if they are switching to a medium sheet size then adjust the map to be centered in the upper screen
		if sheetPresentationController.selectedDetentIdentifier == .medium,
		   let pin = pushPin?.arrowPoint
		{
			let newPin = CGPoint(x: bounds.midX,
			                     y: (bounds.minY + bounds.center().y) / 2)
			let translation = newPin.minus(pin)
			adjustOrigin(by: translation)
		}
	}

	// MARK: Gesture Recognizers

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		// http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer
		var view = touch.view
		while view != nil, !((view is UIControl) || (view is UIToolbar)) {
			view = view?.superview
		}
		if view != nil {
			// We touched a button, slider, or other UIControl.
			// When the user taps a button we don't want to
			// select the object underneath it, so we reject
			// Tap recognizers.
			if gestureRecognizer is UITapGestureRecognizer || view is PushPinView {
				return false // ignore the touch
			}
		}
		return true // handle the touch
	}

	func gestureRecognizer(
		_ gestureRecognizer: UIGestureRecognizer,
		shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
	{
		if gestureRecognizer == addNodeButtonLongPressGestureRecognizer ||
			otherGestureRecognizer == addNodeButtonLongPressGestureRecognizer
		{
			// if holding down the + button then always allow other gestures to proceeed
			return true
		}

		if gestureRecognizer is UILongPressGestureRecognizer ||
			otherGestureRecognizer is UILongPressGestureRecognizer
		{
			// don't register long-press when other gestures are occuring
			return false
		}

		if (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is TapAndDragGesture) ||
			(gestureRecognizer is TapAndDragGesture && otherGestureRecognizer is UIPanGestureRecognizer)
		{
			// Tap-and-drag is a shortcut for zooming, so it's not compatible with the Pan gesture
			return false
		} else if gestureRecognizer is TapAndDragGesture {
			return true
		}

		if gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer {
			// don't register taps during panning/zooming/rotating
			return false
		}

		// allow other things so we can pan/zoom/rotate simultaneously
		return true
	}

	@objc func handlePanGesture(_ pan: UIPanGestureRecognizer) {
		userOverrodeLocationPosition = true

		if pan.state == .began {
			// start pan
			DisplayLink.shared.removeName(DisplayLinkPanning)
			// disable frame rate test if active
			automatedFramerateTestActive = false
		} else if pan.state == .changed {
			// move pan
			if SHOW_3D {
				// multi-finger drag to initiate 3-D view
				if enableBirdsEye, pan.numberOfTouches == 3 {
					let translation = pan.translation(in: self)
					let delta = Double(-translation.y / 40 / 180 * .pi)
					rotateBirdsEye(by: delta)
					return
				}
			}
			let translation = pan.translation(in: self)
			adjustOrigin(by: translation)
			pan.setTranslation(CGPoint(x: 0, y: 0), in: self)
		} else if pan.state == .ended || pan.state == .cancelled {
			// cancelled occurs when we throw an error dialog
			let duration = 0.5

			// finish pan with inertia
			let initialVelecity = pan.velocity(in: self)
			if hypot(initialVelecity.x, initialVelecity.y) < 100.0 {
				// don't use inertia for small movements because it interferes with dropping the pin precisely
			} else {
				let startTime = CACurrentMediaTime()
				let displayLink = DisplayLink.shared
				displayLink.addName(DisplayLinkPanning, block: {
					let timeOffset = CACurrentMediaTime() - startTime
					if timeOffset >= duration {
						displayLink.removeName(DisplayLinkPanning)
					} else {
						var translation = CGPoint()
						let t = timeOffset / duration // time [0..1]
						translation.x = CGFloat(1 - t) * initialVelecity.x * CGFloat(displayLink.duration())
						translation.y = CGFloat(1 - t) * initialVelecity.y * CGFloat(displayLink.duration())
						self.adjustOrigin(by: translation)
					}
				})
			}
			updateMapMarkersFromServer(withDelay: CGFloat(duration), including: [])
		} else if pan.state == .failed {
			DLog("pan gesture failed")
		} else {
			DLog("pan gesture \(pan.state)")
		}
	}

	// unfortunately macCatalyst does't handle setting pinch.scale correctly, so
	// we need to track the previous scale
	var prevousPinchScale = 0.0

	@objc func handlePinchGesture(_ pinch: UIPinchGestureRecognizer) {
		switch pinch.state {
		case .began:
			prevousPinchScale = 1.0
			fallthrough
		case .changed:
			userOverrodeLocationZoom = true

			DisplayLink.shared.removeName(DisplayLinkPanning)

#if targetEnvironment(macCatalyst)
			// On Mac we want to zoom around the screen center, not the cursor.
			// This is better determined by testing for indirect touches, but
			// that information isn't exposed by the gesture recognizer.
			// If we're zooming via mouse then we'll follow the zoom path, not the pinch path.
			let zoomCenter = crossHairs.position
#else
			let zoomCenter = pinch.location(in: self)
#endif
			let scale = pinch.scale / prevousPinchScale
			adjustZoom(by: scale, aroundScreenPoint: zoomCenter)
			prevousPinchScale = pinch.scale
		case .ended:
			updateMapMarkersFromServer(withDelay: 0, including: [])
		default:
			break
		}
	}

	var tapAndDragSelections: EditorMapLayer.Selections?
	var tapAndDragPushpinLatLon: LatLon?

	@objc func handleTapAndDragGesture(_ tapAndDrag: TapAndDragGesture) {
		// do single-finger zooming
		switch tapAndDrag.state {
		case .began:
			// we don't want the initial tap to change object selection
			if let tapAndDragSelections = tapAndDragSelections {
				editorLayer.selections = tapAndDragSelections
				if let tapAndDragPushpinLatLon = tapAndDragPushpinLatLon {
					let pt = mapTransform.screenPoint(forLatLon: tapAndDragPushpinLatLon, birdsEye: true)
					placePushpinForSelection(at: pt)
				} else {
					removePin()
				}
				self.tapAndDragSelections = nil
			}

		case .changed:
			userOverrodeLocationZoom = true

			DisplayLink.shared.removeName(DisplayLinkPanning)

			let delta = tapAndDrag.translation(in: self)
			let scale = 1.0 - delta.y * 0.01
			let zoomCenter = centerPoint()
			adjustZoom(by: scale, aroundScreenPoint: zoomCenter)
		case .ended:
			updateMapMarkersFromServer(withDelay: 0, including: [])
		default:
			break
		}
	}

	/// Invoked to select an object on the screen
	@IBAction func screenTapGesture(_ tap: UITapGestureRecognizer) {
		switch tap.state {
		case .ended:
			// we don't want the initial tap of a tap-and-drag to change object selection
			tapAndDragSelections = editorLayer.selections
			if let pushPin = pushPin {
				tapAndDragPushpinLatLon = mapTransform.latLon(forScreenPoint: pushPin.arrowPoint)
			} else {
				tapAndDragPushpinLatLon = nil
			}

			// disable rotation if in action
			if isRotateObjectMode != nil {
				endObjectRotation()
			}

			let point = tap.location(in: self)
			if plusButtonTimestamp != 0.0 {
				// user is doing a long-press on + button
				editorLayer.addNode(at: point)
			} else {
				editorLayer.selectObjectAtPoint(point)
			}
		default:
			break
		}
	}

	@objc func plusButtonLongPressHandler(_ recognizer: UILongPressGestureRecognizer) {
		switch recognizer.state {
		case .began:
			plusButtonTimestamp = TimeInterval(CACurrentMediaTime())
		case .ended:
			if CACurrentMediaTime() - plusButtonTimestamp < 0.5 {
				// treat as tap, but make sure it occured inside the button
				let touch = recognizer.location(in: recognizer.view)
				if recognizer.view?.bounds.contains(touch) ?? false {
					editorLayer.addNode(at: crossHairs.position)
				}
			}
			plusButtonTimestamp = 0.0
		case .cancelled, .failed:
			plusButtonTimestamp = 0.0
		default:
			break
		}
	}

	// long press on map allows selection of various objects near the location
	@IBAction func screenLongPressGesture(_ longPress: UILongPressGestureRecognizer) {
		if longPress.state == .began, !editorLayer.isHidden {
			let point = longPress.location(in: self)
			editorLayer.longPressAtPoint(point)
		}
	}

	@IBAction func handleRotationGesture(_ rotationGesture: UIRotationGestureRecognizer) {
		if let rotate = isRotateObjectMode {
			// Rotate object on screen
			if rotationGesture.state == .began {
				editorLayer.rotateBegin()
			} else if rotationGesture.state == .changed {
				editorLayer.rotateContinue(delta: rotationGesture.rotation, rotate: rotate)
			} else {
				// ended
				endObjectRotation()
				editorLayer.rotateFinish()
			}
			return
		}

		// Rotate screen
		if enableRotation {
			switch rotationGesture.state {
			case .began:
				break // ignore
			case .changed:
#if targetEnvironment(macCatalyst)
				// On Mac we want to rotate around the screen center, not the cursor.
				// This is better determined by testing for indirect touches, but
				// that information isn't exposed by the gesture recognizer.
				let centerPoint = crossHairs.position
#else
				let centerPoint = rotationGesture.location(in: self)
#endif
				let angle = rotationGesture.rotation
				rotate(by: angle, aroundScreenPoint: centerPoint)
				rotationGesture.rotation = 0.0

				if gpsState == .HEADING {
					gpsState = .LOCATION
				}
			case .ended:
				updateMapMarkersFromServer(withDelay: 0, including: [])
			default:
				break // ignore
			}
		}
	}

	func updateSpeechBalloonPosition() {}

	// MARK: Mouse movment

	@objc func handleScrollWheelGesture(_ pan: UIPanGestureRecognizer) {
		if pan.state == .changed {
			let delta = pan.translation(in: self)
			var center = pan.location(in: self)
			center.y -= delta.y
			let zoom = delta.y >= 0 ? (1000.0 + delta.y) / 1000.0 : 1000.0 / (1000.0 - delta.y)
			adjustZoom(by: zoom, aroundScreenPoint: center)
		}
	}

	func rightClick(atLocation location: CGPoint) {
		// right-click is equivalent to holding + and clicking
		editorLayer.addNode(at: location)
	}
}

// MARK: EditorMapLayerOwner delegate methods

// EditorMap extensions
extension MapView: EditorMapLayerOwner {
	func setScreenFromMap(transform: OSMTransform) {
		screenFromMapTransform = transform
	}

	func didUpdateObject() {
		refreshPushpinText()
		updateMapMarkerButtonPositions()
	}

	func didDownloadData() {
		updateMapMarkersFromServer(withDelay: 0.5, including: [])
	}

	func selectionDidChange() {
		updateEditControl()
		mapMarkerDatabase.didSelectObject(editorLayer.selectedPrimary)
	}

	func centerPoint() -> CGPoint {
		return bounds.center()
	}

	func useTurnRestrictions() -> Bool {
		return enableTurnRestriction
	}

	func useUnnamedRoadHalo() -> Bool {
		return unnamedRoadLayer() != nil
	}

	func useAutomaticCacheManagement() -> Bool {
		return enableAutomaticCacheManagement
	}

	func pushpinView() -> PushPinView? {
		return pushPin
	}

	func presentAlert(alert: UIAlertController, location: MenuLocation) {
		switch location {
		case .none:
			break
		case .editBar:
			var button = editControl.bounds
			let segmentWidth = button.size.width
				/ CGFloat(editControl.numberOfSegments) // hack because we can't get the frame for an individual segment
			button.origin.x += button.size.width - 2 * segmentWidth
			button.size.width = segmentWidth
			alert.popoverPresentationController?.sourceView = editControl
			alert.popoverPresentationController?.sourceRect = button
		case let .rect(rc):
			alert.popoverPresentationController?.sourceView = self
			alert.popoverPresentationController?.sourceRect = rc
		}
		mainViewController.present(alert, animated: true)
	}

	func addNote() {
		if let pushpinView = pushPin {
			let pos = mapTransform.latLon(forScreenPoint: pushpinView.arrowPoint)
			let note = OsmNoteMarker(latLon: pos)
			mainViewController.performSegue(withIdentifier: "NotesSegue", sender: note)
			removePin()
		}
	}
}

extension MapView {
	// This is a button that knows that it can be dragged around on the MapView,
	// and if that happens then it shouldn't activate on touchUpInside.
	//
	// When it sees touchDown it records its position and then on touchUpInside
	// it checks if it has moved a significant distance, and only calls the
	// target selector if it is close by.
	class MapViewButton: UIButton {
		private var tapPos = CGPoint.zero
		private var target: NSObject?
		private var requestedAction: Selector?

		override init(frame: CGRect) {
			super.init(frame: frame)
			addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
		}

		required init?(coder: NSCoder) {
			super.init(coder: coder)
			addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
		}

		@objc func touchDown(_ sender: Any?) {
			tapPos = frame.origin
		}

		override func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
			if controlEvents == .touchUpInside {
				// we need to intercept the event and ignore it potentially
				self.target = (target as? NSObject)!
				requestedAction = action
				super.addTarget(self, action: #selector(touchUpInside), for: controlEvents)
			} else {
				super.addTarget(target, action: action, for: controlEvents)
			}
		}

		@objc func touchUpInside() {
			let pos1 = tapPos
			let pos2 = frame.origin
			if hypot(pos1.x - pos2.x, pos1.y - pos2.y) > frame.size.width / 2 {
				// we moved, so ignore event
			} else {
				// good to go: invoke the original action
				_ = target!.perform(requestedAction!, with: self).takeUnretainedValue()
			}
		}
	}
}
