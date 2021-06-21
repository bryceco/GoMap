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

/// The main map display: Editor, Aerial, Mapnik etc.
enum MapViewState: Int {
	case EDITOR
	case EDITORAERIAL
	case AERIAL
	case MAPNIK
}

/// Overlays on top of the map: Locator when zoomed, GPS traces, etc.
struct MapViewOverlays: OptionSet {
	let rawValue: Int
	static let LOCATOR = MapViewOverlays(rawValue: 1 << 0)
	static let GPSTRACE = MapViewOverlays(rawValue: 1 << 1)
	static let NOTES = MapViewOverlays(rawValue: 1 << 2)
	static let NONAME = MapViewOverlays(rawValue: 1 << 3)
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
	case CIRCULARIZE
	case COPYTAGS
	case PASTETAGS
	case RESTRICT
	case CREATE_RELATION
}

private let Z_AERIAL: CGFloat = -100
private let Z_NONAME: CGFloat = -99
private let Z_MAPNIK: CGFloat = -98
private let Z_LOCATOR: CGFloat = -50
private let Z_GPSTRACE: CGFloat = -40
private let Z_EDITOR: CGFloat = -20
private let Z_GPX: CGFloat = -15
private let Z_ROTATEGRAPHIC: CGFloat = -3
private let Z_BLINK: CGFloat = 4
private let Z_CROSSHAIRS: CGFloat = 5
private let Z_BALL: CGFloat = 6
private let Z_TOOLBAR: CGFloat = 90
private let Z_PUSHPIN: CGFloat = 105
private let Z_FLASH: CGFloat = 110

let DefaultHitTestRadius: CGFloat = 10.0 // how close to an object do we need to tap to select it
let DragConnectHitTestRadius = (DefaultHitTestRadius * 0.6) // how close to an object do we need to drag a node to connect to it

struct MapLocation {
	var longitude = 0.0
	var latitude = 0.0
	var zoom = 0.0
	var viewState: MapViewState? = nil
}

protocol MapViewProgress {
	func progressIncrement()
	func progressDecrement()
}

// MARK: Gestures

private let DisplayLinkHeading = "Heading"
private let DisplayLinkPanning = "Panning" // disable gestures inside toolbar buttons

/// Localized names of edit actions
private func ActionTitle(_ action: EDIT_ACTION, _ abbrev: Bool) -> String {
	switch action {
	case .SPLIT: return NSLocalizedString("Split", comment: "Edit action")
	case .RECTANGULARIZE: return NSLocalizedString("Make Rectangular", comment: "Edit action")
	case .STRAIGHTEN: return NSLocalizedString("Straighten", comment: "Edit action")
	case .REVERSE: return NSLocalizedString("Reverse", comment: "Edit action")
	case .DUPLICATE: return NSLocalizedString("Duplicate", comment: "Edit action")
	case .ROTATE: return NSLocalizedString("Rotate", comment: "Edit action")
	case .CIRCULARIZE: return NSLocalizedString("Make Circular", comment: "Edit action")
	case .JOIN: return NSLocalizedString("Join", comment: "Edit action")
	case .DISCONNECT: return NSLocalizedString("Disconnect", comment: "Edit action")
	case .COPYTAGS: return NSLocalizedString("Copy Tags", comment: "Edit action")
	case .PASTETAGS: return NSLocalizedString("Paste", comment: "Edit action")
	case .EDITTAGS: return NSLocalizedString("Tags", comment: "Edit action")
	case .ADDNOTE: return NSLocalizedString("Add Note", comment: "Edit action")
	case .DELETE: return NSLocalizedString("Delete", comment: "Edit action")
	case .MORE: return NSLocalizedString("More...", comment: "Edit action")
	case .RESTRICT: return abbrev ? NSLocalizedString("Restrict", comment: "Edit action")
		: NSLocalizedString("Turn Restrictions", comment: "Edit action")
	case .CREATE_RELATION: return NSLocalizedString("Create Relation", comment: "Edit action")
	}
}

final class MapView: UIView, MapViewProgress, CLLocationManagerDelegate, UIActionSheetDelegate, UIGestureRecognizerDelegate, SKStoreProductViewControllerDelegate {
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
	var tapAndDragGesture: TapAndDragGesture?

	var addNodeButtonLongPressGestureRecognizer: UILongPressGestureRecognizer?
	var plusButtonTimestamp: TimeInterval = 0.0

	var windowPresented = false
	var locationManagerExtraneousNotification = false

	var mainViewController = MainViewController()
	@IBOutlet var fpsLabel: FpsLabel!
	@IBOutlet var userInstructionLabel: UILabel!
	@IBOutlet var compassButton: UIButton!
	@IBOutlet var flashLabel: UILabel!
	@IBOutlet var aerialServiceLogo: UIButton!
	@IBOutlet var helpButton: UIButton!
	@IBOutlet var centerOnGPSButton: UIButton!
	@IBOutlet var addNodeButton: UIButton!
	@IBOutlet var rulerView: RulerView!
	@IBOutlet var progressIndicator: UIActivityIndicatorView!
	@IBOutlet var editControl: UISegmentedControl!

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

	private var viewStateZoomedOut: Bool = false { // override layer because we're zoomed out
		willSet(newValue) {
			viewStateWillChangeTo(viewState, overlays: viewOverlayMask, zoomedOut: newValue)
		}
	}

	public var userOverrodeLocationPosition: Bool = false {
		didSet {
			centerOnGPSButton.isHidden = !userOverrodeLocationPosition || gpsState == .NONE
		}
	}

	public var userOverrodeLocationZoom: Bool = false {
		didSet {
			centerOnGPSButton.isHidden = !userOverrodeLocationZoom || gpsState == .NONE
		}
	}

	private(set) lazy var notesDatabase = OsmNotesDatabase()
	private(set) var notesViewDict: [Int: UIButton] = [:] // convert a note ID to a button on the map

	private(set) lazy var aerialLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
	private(set) lazy var mapnikLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
	private(set) lazy var noNameLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
	private(set) lazy var editorLayer: EditorMapLayer = { EditorMapLayer(owner: self) }()
	private(set) lazy var gpxLayer: GpxLayer = { GpxLayer(mapView: self) }()

	// overlays
	private(set) lazy var locatorLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
	private(set) lazy var gpsTraceLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()

	private(set) var backgroundLayers: [CALayer] = [] // list of all layers that need to be resized, etc.

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

			// Wrap around if we translate too far
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
			if dy > 0 {
				let mul = ceil(dy / mapSize)
				t = t.translatedBy(dx: 0.0, dy: -mul * mapSize / scale)
			} else if dy < -mapSize {
				let mul = floor(-dy / mapSize)
				t = t.translatedBy(dx: 0.0, dy: mul * mapSize / scale)
			}

			// update transform
			mapTransform.transform = t

			// Determine if we've zoomed out enough to disable editing
			// We can only compute a precise surface area size at high zoom since it's possible
			// for the earth to be larger than the screen
			let area = mapTransform.zoom() > 12 ? SurfaceAreaOfRect(screenLatLonRect()) : Double.greatestFiniteMagnitude
			var isZoomedOut = area > 2.0 * 1000 * 1000
			if !editorLayer.isHidden, !editorLayer.atVisibleObjectLimit, area < 200.0 * 1000 * 1000 {
				isZoomedOut = false
			}
			viewStateZoomedOut = isZoomedOut

			updateMouseCoordinates()
			updateUserLocationIndicator(nil)

			updateCountryCodeForLocationUsingNominatim()

			// update pushpin location
			if let pushpinView = pushPin,
			   let pp = pp
			{
				pushpinView.arrowPoint = mapTransform.screenPoint(forLatLon: pp,
				                                                  birdsEye: true)
			}

			refreshNoteButtonsFromDatabase()
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
					gpxLayer.startNewTrack()
				} else if gpsState == .NONE {
					gpxLayer.endActiveTrack()
				}

				if gpsState == .HEADING {
					// rotate to heading
					if let heading = locationManager.heading {
						let center = bounds.center()
						let screenAngle = screenFromMapTransform.rotation()
						let heading = self.heading(for: heading)
						animateRotation(by: -(screenAngle + heading), aroundPoint: center)
					}
				} else if gpsState == .LOCATION {
					// orient toward north
					let center = bounds.center()
					let rotation = screenFromMapTransform.rotation()
					animateRotation(by: -rotation, aroundPoint: center)
				} else {
					// keep whatever rotation we had
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

			locationManager.allowsBackgroundLocationUpdates = gpsInBackground && enableGpxLogging

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

	var enableBirdsEye: Bool = false {
		didSet {
			if !enableBirdsEye {
				// remove birdsEye
				rotateBirdsEye(by: -mapTransform.birdsEyeRotation)
			}
		}
	}

	var enableRotation: Bool = false {
		didSet {
			if !enableRotation {
				// remove rotation
				let centerPoint = bounds.center()
				let angle = CGFloat(screenFromMapTransform.rotation())
				rotate(by: -angle, aroundScreenPoint: centerPoint)
			}
		}
	}

	var enableUnnamedRoadHalo: Bool = false {
		didSet {
			editorLayer.clearCachedProperties()
		}
	}

	var enableGpxLogging: Bool = false {
		didSet {
			gpxLayer.isHidden = !enableGpxLogging
			locationManager.allowsBackgroundLocationUpdates = gpsInBackground && enableGpxLogging
		}
	}

	var enableTurnRestriction: Bool = false {
		didSet {
			editorLayer.clearCachedProperties()
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
				let startLatLon = OSMPoint(x: -122.205831, y: 47.675024)
				let startZoom = 18.0 // 17.302591
				setTransformFor(latLon: LatLon(startLatLon), zoom: startZoom)

				// sets the size of the circle
				let radius: Double = 100
				let startAngle: CGFloat = 1.5 * .pi
				let rpm: CGFloat = 2.0
				let zoomTotal: CGFloat = 1.1 // 10% larger
				let zoomDelta = pow(zoomTotal, 1 / 60.0)

				var angle = startAngle
				var prevTime = CACurrentMediaTime()
				weak var weakSelf = self

				displayLink.addName(AUTOSCROLL_DISPLAYLINK_NAME, block: {
					guard let myself = weakSelf else { return }
					let time = CACurrentMediaTime()
					let delta = time - prevTime
					let newAngle = angle + (2 * .pi) / rpm * CGFloat(delta) // angle change depends on framerate to maintain 2/RPM

					if angle < startAngle, newAngle >= startAngle {
						// reset to start position
						myself.setTransformFor(latLon: LatLon(startLatLon), zoom: startZoom)
						angle = startAngle
					} else {
						// move along circle
						let x1 = cos(angle)
						let y1 = sin(angle)
						let x2 = cos(newAngle)
						let y2 = sin(newAngle)
						let dx = CGFloat(Double(x2 - x1) * radius)
						let dy = CGFloat(Double(y2 - y1) * radius)

						myself.adjustOrigin(by: CGPoint(x: dx, y: dy))
						let zoomRatio = Double(dy >= 0 ? zoomDelta : 1 / zoomDelta)
						myself.adjustZoom(by: CGFloat(zoomRatio), aroundScreenPoint: myself.crossHairs.position)
						angle = fmod(newAngle, 2 * .pi)
					}
					prevTime = time
				})
			} else {
				fpsLabel.showFPS = false
				displayLink.removeName(AUTOSCROLL_DISPLAYLINK_NAME)
			}
		}
	}

	private(set) var crossHairs: CAShapeLayer
	private(set) var countryCodeForLocation: String?
	private(set) var countryCodeLocation: LatLon

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
		crossHairs = CAShapeLayer()
		tileServerList = TileServerList()
		locationBallLayer = LocationBallLayer()
		locating = false
		countryCodeLocation = .zero

		super.init(coder: coder)

		layer.masksToBounds = true
		if #available(iOS 13.0, *) {
			backgroundColor = UIColor.systemGray6
		} else {
			backgroundColor = UIColor(white: 0.85, alpha: 1.0)
		}

		UserDefaults.standard.register(
			defaults: [
				"view.scale": NSNumber(value: Double.nan),
				"view.latitude": NSNumber(value: Double.nan),
				"view.longitude": NSNumber(value: Double.nan),
				"mapViewState": NSNumber(value: MapViewState.EDITORAERIAL.rawValue),
				"mapViewEnableBirdsEye": NSNumber(value: false),
				"mapViewEnableRotation": NSNumber(value: true),
				"automaticCacheManagement": NSNumber(value: true)
			])

		// this option needs to be set before the editor is initialized
		enableAutomaticCacheManagement = UserDefaults.standard.bool(forKey: "automaticCacheManagement")

		var bg: [CALayer] = []

		locatorLayer = MercatorTileLayer(mapView: self)
		locatorLayer.zPosition = Z_LOCATOR
		locatorLayer.tileServer = TileServer.mapboxLocator
		locatorLayer.isHidden = true
		bg.append(locatorLayer)

		gpsTraceLayer = MercatorTileLayer(mapView: self)
		gpsTraceLayer.zPosition = Z_GPSTRACE
		gpsTraceLayer.tileServer = TileServer.gpsTrace
		gpsTraceLayer.isHidden = true
		bg.append(gpsTraceLayer)

		noNameLayer = MercatorTileLayer(mapView: self)
		noNameLayer.zPosition = Z_NONAME
		noNameLayer.tileServer = TileServer.noName
		noNameLayer.isHidden = true
		bg.append(noNameLayer)

		aerialLayer = MercatorTileLayer(mapView: self)
		aerialLayer.zPosition = Z_AERIAL
		aerialLayer.opacity = 0.75
		aerialLayer.tileServer = tileServerList.currentServer
		aerialLayer.isHidden = true
		bg.append(aerialLayer)

		mapnikLayer = MercatorTileLayer(mapView: self)
		mapnikLayer.tileServer = TileServer.mapnik
		mapnikLayer.zPosition = Z_MAPNIK
		mapnikLayer.isHidden = true
		bg.append(mapnikLayer)

		editorLayer = EditorMapLayer(owner: self)
		editorLayer.zPosition = Z_EDITOR
		bg.append(editorLayer)

		gpxLayer = GpxLayer(mapView: self)
		gpxLayer.zPosition = Z_GPX
		gpxLayer.isHidden = true
		bg.append(gpxLayer)

		backgroundLayers = bg
		for layer in backgroundLayers {
			self.layer.addSublayer(layer)
		}

		// implement crosshairs
		do {
			var path = UIBezierPath()
			let radius: CGFloat = 12
			path.move(to: CGPoint(x: -radius, y: 0))
			path.addLine(to: CGPoint(x: radius, y: 0))
			path.move(to: CGPoint(x: 0, y: -radius))
			path.addLine(to: CGPoint(x: 0, y: radius))
			crossHairs.anchorPoint = CGPoint(x: 0.5, y: 0.5)
			crossHairs.path = path.cgPath
			crossHairs.strokeColor = UIColor(red: 1.0, green: 1.0, blue: 0.5, alpha: 1.0).cgColor
			crossHairs.bounds = CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)
			crossHairs.lineWidth = 2.0
			crossHairs.zPosition = Z_CROSSHAIRS

			path = UIBezierPath()
			let shadowWidth: CGFloat = 2.0
			let p1 = UIBezierPath(rect: CGRect(x: -(radius + shadowWidth - 1), y: -shadowWidth, width: 2 * (radius + shadowWidth - 1), height: 2 * shadowWidth))
			let p2 = UIBezierPath(rect: CGRect(x: -shadowWidth, y: -(radius + shadowWidth - 1), width: 2 * shadowWidth, height: 2 * (radius + shadowWidth - 1)))
			path.append(p1)
			path.append(p2)
			crossHairs.shadowColor = UIColor.black.cgColor
			crossHairs.shadowOpacity = 1.0
			crossHairs.shadowPath = path.cgPath
			crossHairs.shadowRadius = 0
			crossHairs.shadowOffset = CGSize(width: 0, height: 0)

			crossHairs.position = bounds.center()
			layer.addSublayer(crossHairs)
		}

		locationBallLayer.zPosition = Z_BALL
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

		NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: UIApplication.willResignActiveNotification, object: nil)

		userInstructionLabel.layer.cornerRadius = 5
		userInstructionLabel.layer.masksToBounds = true
		userInstructionLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.3)
		userInstructionLabel.textColor = UIColor.white
		userInstructionLabel.isHidden = true

		progressIndicator.color = UIColor.green

		locationManagerExtraneousNotification = true // flag that we're going to receive a bogus notification from CL
		locationManager.delegate = self
		locationManager.pausesLocationUpdatesAutomatically = false
		locationManager.allowsBackgroundLocationUpdates = gpsInBackground && enableGpxLogging
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
		editControl.layer.zPosition = Z_TOOLBAR
		editControl.layer.cornerRadius = 4.0

		// long press for selecting from multiple objects (for multipolygon members)
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(screenLongPressGesture(_:)))
		longPress.delegate = self
		addGestureRecognizer(longPress)

		// two-finger rotation
		let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
		rotationGesture.delegate = self
		addGestureRecognizer(rotationGesture)

		// long-press on + for adding nodes via taps
		addNodeButtonLongPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(plusButtonLongPressHandler(_:)))
		addNodeButtonLongPressGestureRecognizer?.minimumPressDuration = 0.001
		addNodeButtonLongPressGestureRecognizer?.delegate = self
		if let addNodeButtonLongPressGestureRecognizer = addNodeButtonLongPressGestureRecognizer {
			addNodeButton.addGestureRecognizer(addNodeButtonLongPressGestureRecognizer)
		}

#if targetEnvironment(macCatalyst)
		do {
			// pan gesture to recognize mouse-wheel scrolling (zoom) on Mac Catalyst
			let scrollWheelGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScrollWheelGesture(_:)))
			scrollWheelGesture.allowedScrollTypesMask = .discrete
			scrollWheelGesture.maximumNumberOfTouches = 0
			addGestureRecognizer(scrollWheelGesture)
		}
#endif

		notesDatabase.mapData = editorLayer.mapData
		notesViewDict = [:]

		// center button
		centerOnGPSButton.isHidden = true

		// compass button
		compassButton.contentMode = .center
		compassButton.setImage(nil, for: .normal)
		compassButton.backgroundColor = UIColor.white
		compass(on: compassButton.layer, withRadius: compassButton.bounds.size.width / 2)

		// error message label
		flashLabel.font = UIFont.preferredFont(forTextStyle: .title3)
		flashLabel.layer.cornerRadius = 5
		flashLabel.layer.masksToBounds = true
		flashLabel.layer.zPosition = Z_FLASH
		flashLabel.isHidden = true

#if false
		// Support zoom via tap and drag
		handleTapAndDragGesture = TapAndDragGesture(target: self, action: #selector(handleTapAndDragGesture(_:)))
		handleTapAndDragGesture?.delegate = self
		if let handleTapAndDragGesture = handleTapAndDragGesture {
			addGestureRecognizer(handleTapAndDragGesture)
		}
#endif

		// these need to be loaded late because assigning to them changes the view
		viewState = MapViewState(rawValue: UserDefaults.standard.integer(forKey: "mapViewState")) ?? MapViewState.EDITORAERIAL
		viewOverlayMask = MapViewOverlays(rawValue: UserDefaults.standard.integer(forKey: "mapViewOverlays"))

		enableRotation = UserDefaults.standard.bool(forKey: "mapViewEnableRotation")
		enableBirdsEye = UserDefaults.standard.bool(forKey: "mapViewEnableBirdsEye")
		enableUnnamedRoadHalo = UserDefaults.standard.bool(forKey: "mapViewEnableUnnamedRoadHalo")
		enableGpxLogging = UserDefaults.standard.bool(forKey: "mapViewEnableBreadCrumb")
		enableTurnRestriction = UserDefaults.standard.bool(forKey: "mapViewEnableTurnRestriction")

		countryCodeForLocation = UserDefaults.standard.object(forKey: "countryCodeForLocation") as? String

		updateAerialAttributionButton()

		editorLayer.whiteText = !aerialLayer.isHidden
	}

	func viewDidAppear() {
		// Only want to run this once. On older versions of iOS viewDidAppear is called multiple times
		if !windowPresented {
			windowPresented = true

			// get current location
			let scale = UserDefaults.standard.double(forKey: "view.scale")
			let latitude = UserDefaults.standard.double(forKey: "view.latitude")
			let longitude = UserDefaults.standard.double(forKey: "view.longitude")

			if !latitude.isNaN, !longitude.isNaN, !scale.isNaN {
				setTransformFor(latLon: LatLon(latitude: latitude, longitude: longitude),
				                scale: scale)
			} else {
				let rc = OSMRect(layer.bounds)
				screenFromMapTransform = OSMTransform.translation(rc.origin.x + rc.size.width / 2 - 128,
				                                                  rc.origin.y + rc.size.height / 2 - 128)
				// turn on GPS which will move us to current location
				mainViewController.setGpsState(GPS_STATE.LOCATION)
			}

			// get notes
			updateNotesFromServer(withDelay: 0)
		}
	}

	func compass(on layer: CALayer, withRadius radius: CGFloat) {
		let needleWidth = CGFloat(round(Double(radius / 5)))
		layer.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
		layer.cornerRadius = radius
		do {
			let north = CAShapeLayer()
			let path = UIBezierPath()
			path.move(to: CGPoint(x: -needleWidth, y: 0))
			path.addLine(to: CGPoint(x: needleWidth, y: 0))
			path.addLine(to: CGPoint(x: 0, y: CGFloat(-round(Double(radius * 0.9)))))
			path.close()
			north.path = path.cgPath
			north.fillColor = UIColor.systemRed.cgColor
			north.position = CGPoint(x: radius, y: radius)
			layer.addSublayer(north)
		}
		do {
			let south = CAShapeLayer()
			let path = UIBezierPath()
			path.move(to: CGPoint(x: -needleWidth, y: 0))
			path.addLine(to: CGPoint(x: needleWidth, y: 0))
			path.addLine(to: CGPoint(x: 0, y: CGFloat(round(Double(radius * 0.9)))))
			path.close()
			south.path = path.cgPath
			south.fillColor = UIColor.lightGray.cgColor
			south.position = CGPoint(x: radius, y: radius)
			layer.addSublayer(south)
		}
		do {
			let pivot = CALayer()
			pivot.bounds = CGRect(x: radius - needleWidth / 2, y: radius - needleWidth / 2, width: needleWidth, height: needleWidth)
			pivot.backgroundColor = UIColor.white.cgColor
			pivot.borderColor = UIColor.black.cgColor
			pivot.cornerRadius = needleWidth / 2
			pivot.position = CGPoint(x: radius, y: radius)
			layer.addSublayer(pivot)
		}
	}

	func acceptsFirstResponder() -> Bool {
		return true
	}

	func save() {
		// save defaults firs
		var center = OSMPoint(crossHairs.position)
		center = mapTransform.mapPoint(forScreenPoint: center, birdsEye: false)
		let latLon = MapTransform.latLon(forMapPoint: center)
		let scale = screenFromMapTransform.scale()
#if false && DEBUG
		assert(scale > 1.0)
#endif
		UserDefaults.standard.set(scale, forKey: "view.scale")
		UserDefaults.standard.set(latLon.lat, forKey: "view.latitude")
		UserDefaults.standard.set(latLon.lon, forKey: "view.longitude")

		UserDefaults.standard.set(viewState.rawValue, forKey: "mapViewState")
		UserDefaults.standard.set(viewOverlayMask.rawValue, forKey: "mapViewOverlays")

		UserDefaults.standard.set(enableRotation, forKey: "mapViewEnableRotation")
		UserDefaults.standard.set(enableBirdsEye, forKey: "mapViewEnableBirdsEye")
		UserDefaults.standard.set(enableUnnamedRoadHalo, forKey: "mapViewEnableUnnamedRoadHalo")
		UserDefaults.standard.set(enableGpxLogging, forKey: "mapViewEnableBreadCrumb")
		UserDefaults.standard.set(enableTurnRestriction, forKey: "mapViewEnableTurnRestriction")
		UserDefaults.standard.set(enableAutomaticCacheManagement, forKey: "automaticCacheManagement")

		UserDefaults.standard.set(countryCodeForLocation, forKey: "countryCodeForLocation")

		UserDefaults.standard.synchronize()

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
		for layer in backgroundLayers {
			layer.frame = bounds
			layer.bounds = bounds
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
			bounds = CGRect(x: -bounds.size.width / 2, y: -bounds.size.height / 2, width: bounds.size.width, height: bounds.size.height)
			super.bounds = bounds
		}
	}

	// MARK: Utility

	func isFlipped() -> Bool {
		return true
	}

	func updateAerialAttributionButton() {
		let service = aerialLayer.tileServer
		aerialServiceLogo.isHidden = aerialLayer.isHidden || (service.attributionString.count == 0 && service.attributionIcon == nil)
		if !aerialServiceLogo.isHidden {
			// For Bing maps, the attribution icon is part of the app's assets and already has the desired size,
			// so there's no need to scale it.
			if !service.isBingAerial() {
				service.scaleAttributionIcon(toHeight: aerialServiceLogo.frame.size.height)
			}

			aerialServiceLogo.setImage(service.attributionIcon, for: .normal)
			aerialServiceLogo.setTitle(service.attributionString, for: .normal)
		}
	}

	func showAlert(_ title: String, message: String?) {
		let alertError = UIAlertController(title: title, message: message, preferredStyle: .alert)
		alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
		mainViewController.present(alertError, animated: true)
	}

	func html(asAttributedString html: String, textColor: UIColor, backgroundColor backColor: UIColor) -> NSAttributedString? {
		if html.hasPrefix("<") {
			var attrText: NSAttributedString?
			if let data = html.data(using: .utf8) {
				attrText = try? NSAttributedString(
					data: data,
					options: [.documentType: NSAttributedString.DocumentType.html,
					          .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)],
					documentAttributes: nil)
			}
			if let attrText = attrText {
				let s = NSMutableAttributedString(attributedString: attrText)
				// change text color
				s.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: s.length))
				s.addAttribute(.backgroundColor, value: backColor, range: NSRange(location: 0, length: s.length))
				// center align
				let paragraphStyle = NSMutableParagraphStyle()
				paragraphStyle.alignment = .center
				s.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: s.length))

				return s
			}
		}
		return nil
	}

	func flashMessage(_ message: String, duration: TimeInterval) {
		//        #if os(iOS)
		let MAX_ALPHA: CGFloat = 0.8

		let attrText = html(asAttributedString: message, textColor: UIColor.white, backgroundColor: UIColor.black)
		if (attrText?.length ?? 0) > 0 {
			flashLabel.attributedText = attrText
		} else {
			flashLabel.text = message
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

		let popTime = DispatchTime.now() + Double(duration)

		DispatchQueue.main.asyncAfter(deadline: popTime) {
			UIView.animate(withDuration: 0.35, animations: {
				self.flashLabel.alpha = 0.0
			}) { finished in
				if finished, self.flashLabel.layer.presentation()?.opacity == 0.0 {
					self.flashLabel.isHidden = true
				}
			}
		}
		//        #endif
	}

	func flashMessage(_ message: String) {
		flashMessage(message, duration: 0.7)
	}

	func presentError(_ error: Error, flash: Bool) {
		if lastErrorDate == nil || Date().timeIntervalSince(lastErrorDate ?? Date()) > 3.0 {
			let text = error.localizedDescription

#if false
			let ignorable = (error as NSError?)?.userInfo["Ignorable"]
			if ignorable != nil {
				return
			}
#endif

			var isNetworkError = false
			var title = NSLocalizedString("Error", comment: "")
			var ignoreButton: String?
			if (error as NSError?)?.userInfo["NSErrorFailingURLKey"] != nil {
				isNetworkError = true
			}
			if let underError = (error as NSError?)?.userInfo["NSUnderlyingError"] as? NSError {
				if (underError.domain as CFString) == kCFErrorDomainCFNetwork {
					isNetworkError = true
				}
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
				flashMessage(text, duration: 0.9)
			} else {
				let attrText = html(asAttributedString: text, textColor: UIColor.black, backgroundColor: UIColor.white)
				let alertError = UIAlertController(title: title, message: text, preferredStyle: .alert)
				if let attrText = attrText {
					alertError.setValue(attrText, forKey: "attributedMessage")
				}
				alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
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
			let title = String.localizedStringWithFormat(NSLocalizedString("You've uploaded %ld changesets with this version of Go Map!!\n\nRate this app?", comment: ""), uploadCount)
			let alertViewRateApp = UIAlertController(title: title, message: NSLocalizedString("Rating this app makes it easier for other mappers to discover it and increases the visibility of OpenStreetMap.", comment: ""), preferredStyle: .alert)
			alertViewRateApp.addAction(UIAlertAction(title: NSLocalizedString("Maybe later...", comment: "rate the app later"), style: .cancel, handler: { _ in
			}))
			alertViewRateApp.addAction(UIAlertAction(title: NSLocalizedString("I'll do it!", comment: "rate the app now"), style: .default, handler: { [self] _ in
				showInAppStore()
			}))
			mainViewController.present(alertViewRateApp, animated: true)
		}
	}

	func showInAppStore() {
		let appStoreId = 592990211
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

	func updateCountryCodeForLocationUsingNominatim() {
		if viewStateZoomedOut {
			return
		}

		// if we moved a significant distance then check our country location
		let loc = mapTransform.latLon(forScreenPoint: center)
		let distance = GreatCircleDistance(loc, countryCodeLocation)
		if distance < 10 * 1000 {
			return
		}
		countryCodeLocation = loc

		let url = "https://nominatim.openstreetmap.org/reverse?zoom=13&addressdetails=1&format=json&lat=\(loc.lat)&lon=\(loc.lon)"
		var task: URLSessionDataTask?
		if let url1 = URL(string: url) {
			task = URLSession.shared.dataTask(with: url1, completionHandler: { data, _, _ in
				if (data?.count ?? 0) != 0 {
					var json: Any?
					do {
						if let data = data {
							json = try JSONSerialization.jsonObject(with: data, options: [])
						}
					} catch {}
					if let json = json as? [String: Any] {
						if let address = json["address"] as? [String: Any] {
							let code = address["country_code"] as? String
							if let code = code {
								DispatchQueue.main.async {
									self.countryCodeForLocation = code
								}
							}
						}
					}
				}
			})
		}
		task?.resume()
	}

	// MARK: Rotate object

	func startObjectRotation() {
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
		let path = UIBezierPath(arcCenter: center, radius: radiusInner, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2 + arrowWidth / 2, y: center.y))
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2, y: center.y + arrowWidth / sqrt(2.0)))
		path.addLine(to: CGPoint(x: center.x - (radiusOuter + radiusInner) / 2 - arrowWidth / 2, y: center.y))
		path.addArc(withCenter: center, radius: radiusOuter, startAngle: .pi, endAngle: .pi / 2, clockwise: true)
		path.close()
		rotateObjectOverlay.path = path.cgPath
		rotateObjectOverlay.fillColor = UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.4).cgColor
		rotateObjectOverlay.zPosition = Z_ROTATEGRAPHIC
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
			return
		}

		func StateFor(_ state: MapViewState, zoomedOut: Bool) -> MapViewState {
			if zoomedOut, state == .EDITOR { return .MAPNIK }
			if zoomedOut, state == .EDITORAERIAL { return .AERIAL }
			return state
		}
		func OverlaysFor(_ state: MapViewState, overlays: MapViewOverlays, zoomedOut: Bool) -> MapViewOverlays {
			if zoomedOut, state == .EDITORAERIAL { return overlays.union(.LOCATOR) }
			if !zoomedOut { return overlays.subtracting(.NONAME) }
			return overlays
		}

		// Things are complicated because the user has their own preference for the view
		// but when they zoom out we make automatic substitutions:
		// 	Editor only --> Mapnik
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

		locatorLayer.isHidden = !newOverlays.contains(.LOCATOR)
		gpsTraceLayer.isHidden = !newOverlays.contains(.GPSTRACE)
		noNameLayer.isHidden = !newOverlays.contains(.NONAME)

		switch newState {
		case MapViewState.EDITOR:
			editorLayer.isHidden = false
			aerialLayer.isHidden = true
			mapnikLayer.isHidden = true
			userInstructionLabel.isHidden = true
			editorLayer.whiteText = true
		case MapViewState.EDITORAERIAL:
			aerialLayer.tileServer = tileServerList.currentServer
			editorLayer.isHidden = false
			aerialLayer.isHidden = false
			mapnikLayer.isHidden = true
			userInstructionLabel.isHidden = true
			aerialLayer.opacity = 0.75
			editorLayer.whiteText = true
		case MapViewState.AERIAL:
			aerialLayer.tileServer = tileServerList.currentServer
			editorLayer.isHidden = true
			aerialLayer.isHidden = false
			mapnikLayer.isHidden = true
			userInstructionLabel.isHidden = true
			aerialLayer.opacity = 1.0
		case MapViewState.MAPNIK:
			editorLayer.isHidden = true
			aerialLayer.isHidden = true
			mapnikLayer.isHidden = false
			userInstructionLabel.isHidden = state != .EDITOR && state != .EDITORAERIAL
			if !userInstructionLabel.isHidden {
				userInstructionLabel.text = NSLocalizedString("Zoom to Edit", comment: "")
			}
		}
		updateNotesFromServer(withDelay: 0)

		CATransaction.commit()

		// enable/disable editing buttons based on visibility
		mainViewController.updateUndoRedoButtonState()
		updateAerialAttributionButton()
		addNodeButton.isHidden = editorLayer.isHidden

		editorLayer.whiteText = !aerialLayer.isHidden
	}

	func setAerialTileServer(_ service: TileServer) {
		aerialLayer.tileServer = service
		updateAerialAttributionButton()
	}

	func metersPerPixel() -> Double {
		return mapTransform.metersPerPixel(atScreenPoint: crossHairs.position)
	}

	func boundingMapRectForScreen() -> OSMRect {
		let rc = OSMRect(layer.bounds)
		return mapTransform.boundingMapRect(forScreenRect: rc)
	}

	func screenLatLonRect() -> OSMRect {
		let rc = boundingMapRectForScreen()
		return MapTransform.latLon(forMapRect: rc)
	}

	func setTransformFor(latLon: LatLon) {
		let point = mapTransform.screenPoint(forLatLon: latLon, birdsEye: false)
		let center = crossHairs.position
		let delta = CGPoint(x: center.x - point.x, y: center.y - point.y)
		adjustOrigin(by: delta)
	}

	func setTransformFor(latLon: LatLon, scale: Double) {
		// translate
		setTransformFor(latLon: latLon)

		let ratio = scale / screenFromMapTransform.scale()
		adjustZoom(by: CGFloat(ratio), aroundScreenPoint: crossHairs.position)
	}

	func setTransformFor(latLon: LatLon, width widthDegrees: Double) {
		let scale = 360 / (widthDegrees / 2)
		setTransformFor(latLon: latLon,
		                scale: scale)
	}

	func setMapLocation(_ location: MapLocation) {
		let zoom = location.zoom > 0 ? location.zoom : 18.0
		let scale = pow(2, zoom)
		setTransformFor(latLon: LatLon(latitude: location.latitude, longitude: location.longitude),
		                scale: scale)
		if let state = location.viewState {
			viewState = state
		}
	}

	func setTransformFor(latLon: LatLon, zoom: Double) {
		let scale = pow(2, zoom)
		setTransformFor(latLon: latLon,
		                scale: scale)
	}

	// MARK: Discard stale data

	func discardStaleData() {
		if enableAutomaticCacheManagement {
			let changed = editorLayer.mapData.discardStaleData()
			if changed {
				flashMessage(NSLocalizedString("Cache trimmed", comment: ""))
				editorLayer.updateMapLocation() // download data if necessary
			}
		}
	}

	// MARK: Progress indicator

	func progressIncrement() {
		if progressActive.value() == 0 {
			progressIndicator.startAnimating()
		}
		progressActive.increment()
	}

	func progressDecrement() {
		DbgAssert(progressActive.value() > 0)
		progressActive.decrement()
		if progressActive.value() == 0 {
			progressIndicator.stopAnimating()
		}
	}

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
			setTransformFor(latLon: LatLon(location.coordinate))
		}
	}

	@IBAction func compassPressed(_ sender: Any) {
		switch gpsState {
		case .HEADING:
			gpsState = .LOCATION
		case .LOCATION:
			gpsState = .HEADING
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
			let center = bounds.center()
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
		if !locationBallLayer.isHidden, delta < 0.1, abs(newLocation.horizontalAccuracy - currentLocation.horizontalAccuracy) < 1.0 {
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
				setTransformFor(latLon: LatLon(newLocation.coordinate))
			} else {
				let widthDegrees = Double(20.0 /* meters */ / EarthRadius * 360.0)
				setTransformFor(latLon: LatLon(newLocation.coordinate),
				                width: widthDegrees)
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
				setTransformFor(latLon: LatLon(latitude: 47.6858, longitude: -122.1917),
				                width: 0.01)
			}
			var text = String.localizedStringWithFormat(NSLocalizedString("Ensure Location Services is enabled and you have granted this application access.\n\nError: %@", comment: ""),
			                                            error.localizedDescription)
			text = NSLocalizedString("The current location cannot be determined: ", comment: "") + text
			error = NSError(domain: "Location", code: 100, userInfo: [
				NSLocalizedDescriptionKey: text
			])
			presentError(error, flash: false)
		} else {
			// driving through a tunnel or something
			let text = NSLocalizedString("Location unavailable", comment: "")
			error = NSError(domain: "Location", code: 100, userInfo: [
				NSLocalizedDescriptionKey: text
			])
			presentError(error, flash: true)
		}
	}

	// MARK: Undo/Redo

	func placePushpinForSelection(at point: CGPoint? = nil) {
		guard let selection = editorLayer.selectedPrimary
		else {
			removePin()
			return
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

		if !bounds.contains(pushPin!.arrowPoint) {
			// need to zoom to location
			setTransformFor(latLon: loc)
		}
	}

	@IBAction func undo(_ sender: Any?) {
		if editorLayer.isHidden {
			flashMessage(NSLocalizedString("Editing layer not visible", comment: ""))
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
			flashMessage(NSLocalizedString("Editing layer not visible", comment: ""))
			return
		}
		removePin()
		editorLayer.redo()
	}

	// MARK: Resize & movement

	func isLocationSpecified() -> Bool {
		return !(screenFromMapTransform == .identity)
	}

	func updateMouseCoordinates() {}

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
		compassButton.transform = CGAffineTransform(rotationAngle: CGFloat(screenAngle))
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
				let easeInOutQuad: ((_ t: inout Double, _ b: Double, _ c: Double, _ d: Double) -> Double) = { t, b, c, d in
					t /= d / 2
					if t < 1 {
						return c / 2 * t * t + b
					}
					t -= 1
					return -c / 2 * (t * (t - 2) - 1) + b
				}
				let miniHeading = easeInOutQuad(&elapsedTime, 0, deltaHeading, duration)
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

		let center = bounds.center()
		let offset = mapTransform.mapPoint(forScreenPoint: OSMPoint(center), birdsEye: false)

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
		let center = bounds.center()
		let rotation = screenFromMapTransform.rotation()
		animateRotation(by: -rotation, aroundPoint: center)
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
				let title: String = ActionTitle(action, true)
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

		let actionSheet = UIAlertController(title: NSLocalizedString("Perform Action", comment: ""), message: nil, preferredStyle: .actionSheet)
		for value in actionList {
			let title = ActionTitle(value, false)
			actionSheet.addAction(UIAlertAction(title: title, style: .default, handler: { [self] _ in
				editorLayer.performEdit(value)
			}))
		}
		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { _ in
		}))
		mainViewController.present(actionSheet, animated: true)

		// compute location for action sheet to originate
		var button = editControl.bounds
		let segmentWidth = button.size.width / CGFloat(editControl.numberOfSegments) // hack because we can't get the frame for an individual segment
		button.origin.x += button.size.width - segmentWidth
		button.size.width = segmentWidth
		actionSheet.popoverPresentationController?.sourceView = editControl
		actionSheet.popoverPresentationController?.sourceRect = button
	}

	@IBAction func editControlAction(_ sender: Any) {
		// get the selected button: has to be done before modifying the node/way selection
		guard let segmentedControl = sender as? UISegmentedControl else { return }
		let segment = segmentedControl.selectedSegmentIndex
		if segment < editControlActions.count {
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
		      let pushPin = self.pushPin
		else { return }

		let showRestrictionEditor: (() -> Void) = { [self] in
			guard let myVc = mainViewController.storyboard?.instantiateViewController(withIdentifier: "TurnRestrictController") as? TurnRestrictController
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
				alert.addAction(UIAlertAction(title: NSLocalizedString("Edit restrictions", comment: ""), style: .destructive, handler: { _ in
					showRestrictionEditor()
				}))
				alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
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
					message: NSLocalizedString("This app does not yet support editing turn restrictions without a node as the 'via' member", comment: ""))
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
	}

	private func pushpinDragCallbackFor(object: OsmBaseObject) -> PushPinViewDragCallback {
		return { [self] state, dx, dy, _ in
			switch state {
			case .began:
				editorLayer.dragBegin()
			case .ended, .cancelled, .failed:
				DisplayLink.shared.removeName("dragScroll")
				let isRotate = self.isRotateObjectMode != nil
				if isRotate {
					self.endObjectRotation()
				}
				self.unblinkObject()
				editorLayer.dragFinish(object: object, isRotate: isRotate)

			case .changed:
				// define the drag function
				let dragObject: ((_ dragx: CGFloat, _ dragy: CGFloat) -> Void) = { dragx, dragy in
					// don't accumulate undo moves
					editorLayer.dragContinue(object: object,
					                         dragx: dragx,
					                         dragy: dragy,
					                         isRotateObjectMode: isRotateObjectMode)
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
					let center = self.bounds.center()
					let v = Sub(OSMPoint(arrow), OSMPoint(center)).unitVector()
					scrollx = SCROLL_SPEED * CGFloat(v.x)
					scrolly = SCROLL_SPEED * CGFloat(v.y)

					// scroll the screen to keep pushpin centered
					var prevTime = TimeInterval(CACurrentMediaTime())
					DisplayLink.shared.addName("dragScroll", block: { [self] in
						let now = TimeInterval(CACurrentMediaTime())
						let duration = now - prevTime
						prevTime = now
						let sx = scrollx * CGFloat(duration) * 60.0 // scale to 60 FPS assumption, need to move farther if framerate is slow
						let sy = scrolly * CGFloat(duration) * 60.0
						self.adjustOrigin(by: CGPoint(x: -sx, y: -sy))
						dragObject(sx, sy)
						// update position of pushpin
						if let pt = self.pushPin?.arrowPoint.withOffset(sx, sy) {
							self.pushPin?.arrowPoint = pt
						}
						// update position of blink layer
						if let pt = blinkLayer?.position.withOffset(-sx, -sy) {
							self.blinkLayer?.position = pt
						}
					})
				} else {
					DisplayLink.shared.removeName("dragScroll")
				}

				// move the object
				dragObject(dx, dy)
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
		pushpinView.layer.zPosition = Z_PUSHPIN
		pushpinView.arrowPoint = point

		if let object = object {
			pushpinView.dragCallback = pushpinDragCallbackFor(object: object)
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
				text.foregroundColor = UIColor(red: 0, green: 0, blue: 0.5, alpha: 1.0).cgColor
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
			assert(false)
		}
		self.blinkLayer = CAShapeLayer()
		guard let blinkLayer = self.blinkLayer else { fatalError() }
		blinkLayer.path = path
		blinkLayer.fillColor = nil
		blinkLayer.lineWidth = 3.0
		blinkLayer.frame = CGRect(x: 0, y: 0, width: bounds.size.width, height: bounds.size.height)
		blinkLayer.zPosition = Z_BLINK
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

	// MARK: Notes

	func updateNotesFromServer(withDelay delay: CGFloat) {
		if viewOverlayMask.contains(.NOTES) {
			let rc = screenLatLonRect()
			notesDatabase.updateRegion(rc, withDelay: delay, fixmeData: editorLayer.mapData) { [self] in
				refreshNoteButtonsFromDatabase()
			}
		} else {
			refreshNoteButtonsFromDatabase()
		}
	}

	func refreshNoteButtonsFromDatabase() {
		DispatchQueue.main.async { [self] in
			// need this to disable implicit animation

			UIView.performWithoutAnimation { [self] in
				// if a button is no longer in the notes database then it got resolved and can go away
				var remove: [Int] = []
				for tag in notesViewDict.keys {
					if notesDatabase.note(forTag: tag) == nil {
						remove.append(tag)
					}
				}
				for tag in remove {
					if let button = notesViewDict[tag] {
						notesViewDict.removeValue(forKey: tag)
						button.removeFromSuperview()
					}
				}

				// update new and existing buttons
				notesDatabase.enumerateNotes { [self] note in
					if viewOverlayMask.contains(MapViewOverlays.NOTES) {
						// hide unwanted keep right buttons
						if note.isKeepRight, notesDatabase.isIgnored(note) {
							if let button = notesViewDict[note.tagId] {
								button.removeFromSuperview()
							}
							return
						}

						if notesViewDict[note.tagId] == nil {
							let button = UIButton(type: .custom)
							button.addTarget(self, action: #selector(noteButtonPress(_:)), for: .touchUpInside)
							button.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
							button.layer.cornerRadius = 5
							button.layer.backgroundColor = UIColor.blue.cgColor
							button.layer.borderColor = UIColor.white.cgColor
							button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
							button.titleLabel?.textColor = UIColor.white
							button.titleLabel?.textAlignment = .center
							let title = note.isFixme ? "F" : note.isWaypoint ? "W" : note.isKeepRight ? "R" : "N"
							button.setTitle(title, for: .normal)
							button.tag = note.tagId
							addSubview(button)
							notesViewDict[note.tagId] = button
						}
						let button = notesViewDict[note.tagId]!

						if note.status == "closed" {
							button.removeFromSuperview()
						} else if note.isFixme, editorLayer.mapData.object(withExtendedIdentifier: note.noteId)?.tags["fixme"] == nil {
							button.removeFromSuperview()
						} else {
							let offsetX = note.isKeepRight || note.isFixme ? 0.00001 : 0.0
							let pos = mapTransform.screenPoint(forLatLon: LatLon(latitude: note.lat, longitude: note.lon + offsetX),
							                                   birdsEye: true)
							if pos.x.isInfinite || pos.y.isInfinite {
								return
							}

							var rc = button.bounds
							rc = rc.offsetBy(dx: pos.x - rc.size.width / 2,
							                 dy: pos.y - rc.size.height / 2)
							button.frame = rc
						}
					} else {
						// not displaying any notes at this time
						if let button = notesViewDict[note.tagId] {
							button.removeFromSuperview()
							notesViewDict.removeValue(forKey: note.tagId)
						}
					}
				}
			}

			if !viewOverlayMask.contains(.NOTES) {
				notesDatabase.reset()
			}
		}
	}

	@objc func noteButtonPress(_ sender: Any?) {
		guard let button = sender as? UIButton,
		      let note = notesDatabase.note(forTag: button.tag)
		else { return }

		if note.isWaypoint || note.isKeepRight {
			if !editorLayer.isHidden {
				let object = editorLayer.mapData.object(withExtendedIdentifier: note.noteId)
				if let object = object {
					editorLayer.selectedNode = object.isNode()
					editorLayer.selectedWay = object.isWay()
					editorLayer.selectedRelation = object.isRelation()

					let pt = object.latLonOnObject(forLatLon: LatLon(x: note.lon, y: note.lat))
					let point = mapTransform.screenPoint(forLatLon: pt, birdsEye: true)
					placePushpin(at: point, object: object)
				}
			}
			let comment = note.comments.last!
			let title = note.isWaypoint ? "Waypoint" : "Keep Right"

			// use regular alertview
			var text = comment.text
			if let r1 = text.range(of: "<a "),
			   let r2 = text.range(of: "\">")
			{
				text.removeSubrange(r1.lowerBound..<r2.upperBound)
			}
			text = text.replacingOccurrences(of: "&quot;", with: "\"")

			let alertKeepRight = UIAlertController(title: title, message: text, preferredStyle: .alert)
			alertKeepRight.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: { _ in
			}))
			alertKeepRight.addAction(UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .default, handler: { [self] _ in
				// they want to hide this button from now on
				notesDatabase.ignore(note)
				refreshNoteButtonsFromDatabase()
				editorLayer.selectedNode = nil
				editorLayer.selectedWay = nil
				editorLayer.selectedRelation = nil
				removePin()
			}))
			mainViewController.present(alertKeepRight, animated: true)
		} else if note.isFixme {
			guard let object = editorLayer.mapData.object(withExtendedIdentifier: note.noteId)
			else { return }
			editorLayer.selectedNode = object.isNode()
			editorLayer.selectedWay = object.isWay()
			editorLayer.selectedRelation = object.isRelation()
			presentTagEditor(nil)
		} else {
			mainViewController.performSegue(withIdentifier: "NotesSegue", sender: note)
		}
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		// http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer
		var view = touch.view
		while view != nil, !((view is UIControl) || (view is UIToolbar)) {
			view = view?.superview
		}
		if view != nil {
			// we touched a button, slider, or other UIControl
			if gestureRecognizer == addNodeButtonLongPressGestureRecognizer {
				return true
			}
			return false // ignore the touch
		}
		return true // handle the touch
	}

	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		if gestureRecognizer == addNodeButtonLongPressGestureRecognizer || otherGestureRecognizer == addNodeButtonLongPressGestureRecognizer {
			return true // if holding down the + button then always allow other gestures to proceeed
		}
		if (gestureRecognizer is UILongPressGestureRecognizer) || (otherGestureRecognizer is UILongPressGestureRecognizer) {
			return false // don't register long-press when other gestures are occuring
		}
		if (gestureRecognizer is UITapGestureRecognizer) || (otherGestureRecognizer is UITapGestureRecognizer) {
			return false // don't register taps during panning/zooming/rotating
		}
		return true // allow other things so we can pan/zoom/rotate simultaneously
	}

	@objc func handlePanGesture(_ pan: UIPanGestureRecognizer) {
		userOverrodeLocationPosition = true

		if pan.state == .began {
			// start pan
			DisplayLink.shared.removeName(DisplayLinkPanning)
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
			updateNotesFromServer(withDelay: CGFloat(duration))
		} else if pan.state == .failed {
			DLog("pan gesture failed")
		} else {
			DLog("pan gesture \(pan.state)")
		}
	}

	@objc func handlePinchGesture(_ pinch: UIPinchGestureRecognizer) {
		if pinch.state == .changed {
			if pinch.scale.isNaN {
				return
			}

			userOverrodeLocationZoom = true

			DisplayLink.shared.removeName(DisplayLinkPanning)

			let zoomCenter = pinch.location(in: self)
			adjustZoom(by: pinch.scale, aroundScreenPoint: zoomCenter)

			pinch.scale = 1.0
		} else if pinch.state == .ended {
			updateNotesFromServer(withDelay: 0)
		}
	}

	@objc func handleTapAndDragGesture(_ tapAndDrag: TapAndDragGesture) {
		// do single-finger zooming
		if tapAndDrag.state == .changed {
			userOverrodeLocationZoom = true

			DisplayLink.shared.removeName(DisplayLinkPanning)

			let delta = tapAndDrag.translation(in: self)
			let scale = 1.0 + delta.y * 0.01
			let zoomCenter = bounds.center()
			adjustZoom(by: scale, aroundScreenPoint: zoomCenter)
		} else if tapAndDrag.state == .ended {
			updateNotesFromServer(withDelay: 0)
		}
	}

	/// Invoked to select an object on the screen
	@IBAction func screenTapGesture(_ tap: UITapGestureRecognizer) {
		if tap.state == .ended {
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
		if longPress.state == .began, !isHidden {
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
			if rotationGesture.state == .began {
				// ignore
			} else if rotationGesture.state == .changed {
				let centerPoint = rotationGesture.location(in: self)
				let angle = rotationGesture.rotation
				rotate(by: angle, aroundScreenPoint: centerPoint)
				rotationGesture.rotation = 0.0

				if gpsState == .HEADING {
					gpsState = .LOCATION
				}
			} else if rotationGesture.state == .ended {
				updateNotesFromServer(withDelay: 0)
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

// EditorMap extensions
extension MapView: EditorMapLayerOwner {
	func setScreenFromMap(transform: OSMTransform) {
		screenFromMapTransform = transform
	}

	func didUpdateObject() {
		refreshPushpinText()
		refreshNoteButtonsFromDatabase()
	}

	func selectionDidChange() {
		updateEditControl()
	}

	func crosshairs() -> CGPoint {
		return crossHairs.position
	}

	func useTurnRestrictions() -> Bool {
		return enableTurnRestriction
	}

	func useUnnamedRoadHalo() -> Bool {
		return enableUnnamedRoadHalo
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
			let segmentWidth = button.size.width / CGFloat(editControl.numberOfSegments) // hack because we can't get the frame for an individual segment
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
			let note = OsmNote(lat: pos.lat, lon: pos.lon)
			mainViewController.performSegue(withIdentifier: "NotesSegue", sender: note)
			removePin()
		}
	}
}
