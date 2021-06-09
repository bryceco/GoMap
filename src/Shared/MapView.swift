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

/// The main map display: Editor, Aerial, Mapnik etc.
enum MapViewState : Int {
	case EDITOR
	case EDITORAERIAL
	case AERIAL
	case MAPNIK
}

/// Overlays on top of the map: Locator when zoomed, GPS traces, etc.
struct MapViewOverlays : OptionSet {
	let rawValue: Int
	static let LOCATOR	= MapViewOverlays(rawValue: 1 << 0)
	static let GPSTRACE	= MapViewOverlays(rawValue: 1 << 1)
	static let NOTES  	= MapViewOverlays(rawValue: 1 << 2)
	static let NONAME	= MapViewOverlays(rawValue: 1 << 3)
}

enum GPS_STATE : Int {
    case NONE
    case LOCATION
    case HEADING
}

enum EDIT_ACTION : Int {
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

class MapLocation {
    var longitude = 0.0
    var latitude = 0.0
    var zoom = 0.0
    var viewState: MapViewState? = nil
}

protocol MapViewProgress {
    func progressIncrement()
    func progressDecrement()
    func progressAnimate()
}

// MARK: Gestures

private let DisplayLinkHeading = "Heading"
private let DisplayLinkPanning = "Panning" // disable gestures inside toolbar buttons

private func StateFor(_ state: MapViewState, zoomedOut: Bool) -> MapViewState {
	if zoomedOut && state == .EDITOR {
        return .MAPNIK
    }
    if zoomedOut && state == .EDITORAERIAL {
        return .AERIAL
    }
    return state
}
private func OverlaysFor(_ state: MapViewState, overlays: MapViewOverlays, zoomedOut: Bool) -> MapViewOverlays {
	if zoomedOut && state == .EDITORAERIAL {
		return overlays.union(.LOCATOR)
	}
	if !zoomedOut {
		return overlays.subtracting(.NONAME)
	}
	return overlays
}

/// Localized names of edit actions
private func ActionTitle(_ action: EDIT_ACTION, _ abbrev: Bool) -> String {
    switch action {
        case .SPLIT:
            return NSLocalizedString("Split", comment: "Edit action")
        case .RECTANGULARIZE:
            return NSLocalizedString("Make Rectangular", comment: "Edit action")
        case .STRAIGHTEN:
            return NSLocalizedString("Straighten", comment: "Edit action")
        case .REVERSE:
            return NSLocalizedString("Reverse", comment: "Edit action")
        case .DUPLICATE:
            return NSLocalizedString("Duplicate", comment: "Edit action")
        case .ROTATE:
            return NSLocalizedString("Rotate", comment: "Edit action")
        case .CIRCULARIZE:
            return NSLocalizedString("Make Circular", comment: "Edit action")
        case .JOIN:
            return NSLocalizedString("Join", comment: "Edit action")
        case .DISCONNECT:
            return NSLocalizedString("Disconnect", comment: "Edit action")
        case .COPYTAGS:
            return NSLocalizedString("Copy Tags", comment: "Edit action")
        case .PASTETAGS:
            return NSLocalizedString("Paste", comment: "Edit action")
        case .EDITTAGS:
            return NSLocalizedString("Tags", comment: "Edit action")
        case .ADDNOTE:
            return NSLocalizedString("Add Note", comment: "Edit action")
        case .DELETE:
            return NSLocalizedString("Delete", comment: "Edit action")
        case .MORE:
            return NSLocalizedString("More...", comment: "Edit action")
        case .RESTRICT:
            return abbrev ? NSLocalizedString("Restrict", comment: "Edit action") : NSLocalizedString("Turn Restrictions", comment: "Edit action")
        case .CREATE_RELATION:
            return NSLocalizedString("Create Relation", comment: "Edit action")
    }
}

class MapView: UIView, MapViewProgress, CLLocationManagerDelegate, UIActionSheetDelegate, UIGestureRecognizerDelegate, SKStoreProductViewControllerDelegate {

    var lastMouseDragPos = CGPoint.zero
    var progressActive = 0
    var locationBallLayer: LocationBallLayer?
    var addWayProgressLayer: CAShapeLayer?
	var blinkObject: OsmBaseObject? // used for creating a moving dots animation during selection
	var blinkSegment = 0
	var blinkLayer: CAShapeLayer?
	var isZoomScroll = false // Command-scroll zooms instead of scrolling (desktop only)

	var isRotateObjectMode: (rotateObjectOverlay: CAShapeLayer, rotateObjectCenter: OSMPoint)? = nil

    var confirmDrag = false // should we confirm that the user wanted to drag the selected object? Only if they haven't modified it since selecting it

    var lastErrorDate: Date? // to prevent spamming of error dialogs
    var ignoreNetworkErrorsUntilDate: Date?
    var voiceAnnouncement: VoiceAnnouncement?
    var tapAndDragGesture: TapAndDragGesture?
    var pushpinDragTotalMove = CGPoint.zero // to maintain undo stack
    var gestureDidMove = false // to maintain undo stack

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
	private(set) var currentLocation: CLLocation = CLLocation()

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
	private var viewStateZoomedOut: Bool = false {	// override layer because we're zoomed out
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

	private(set) lazy var notesDatabase: OsmNotesDatabase = OsmNotesDatabase()
	private(set) var notesViewDict: [Int : UIButton] = [:]	// convert a note ID to a button on the map

	private(set) lazy var aerialLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
    private(set) lazy var mapnikLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
	private(set) lazy var noNameLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
    private (set) lazy var editorLayer: EditorMapLayer = { EditorMapLayer(mapView: self) }()
    private(set) lazy var gpxLayer: GpxLayer = { GpxLayer(mapView: self) }()

    // overlays
	private(set) lazy var locatorLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()
	private(set) lazy var gpsTraceLayer: MercatorTileLayer = { MercatorTileLayer(mapView: self) }()

	private(set) var backgroundLayers: [CALayer] = [] // list of all layers that need to be resized, etc.

	private var _screenFromMapTransform: OSMTransform = OSMTransform.identity
    @objc dynamic var screenFromMapTransform: OSMTransform {	// must be "@objc dynamic" because it's observed
        get {
            return _screenFromMapTransform
        }
        set(t) {
			if t == _screenFromMapTransform {
                return
            }

            // save pushpinView coordinates
			var pp: CLLocationCoordinate2D? = nil
			if let pushpinView = pushpinView {
				pp = longitudeLatitude(forScreenPoint: pushpinView.arrowPoint, birdsEye: true)
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
				_screenFromMapTransform = t.translatedBy(dx: -mul * mapSize / scale, dy: 0.0)
			} else if dx < -mapSize {
                let mul = floor(-dx / mapSize)
				_screenFromMapTransform = t.translatedBy(dx: mul * mapSize / scale, dy: 0.0)
			}
            if dy > 0 {
                let mul = ceil(dy / mapSize)
				_screenFromMapTransform = t.translatedBy(dx: 0.0, dy: -mul * mapSize / scale)
			} else if dy < -mapSize {
                let mul = floor(-dy / mapSize)
				_screenFromMapTransform = t.translatedBy(dx: 0.0, dy: mul * mapSize / scale)
			}

            // update transform
			_screenFromMapTransform = t

            // determine if we've zoomed out enough to disable editing
            let bbox = screenLongitudeLatitude()
            let area = SurfaceArea(bbox)
            var isZoomedOut = area > 2.0 * 1000 * 1000
			if !editorLayer.isHidden && !editorLayer.atVisibleObjectLimit && area < 200.0 * 1000 * 1000 {
				isZoomedOut = false
            }
            viewStateZoomedOut = isZoomedOut

            updateMouseCoordinates()
            updateUserLocationIndicator(nil)

            updateCountryCodeForLocationUsingNominatim()

            // update pushpin location
			if let pushpinView = pushpinView,
			   let pp = pp
			{
				pushpinView.arrowPoint = screenPoint(forLatitude: pp.latitude,
													 longitude: pp.longitude,
													 birdsEye: true)
			}
        }
    }

    var mapFromScreenTransform: OSMTransform {
		return screenFromMapTransform.inverse()
	}

    private var _gpsState: GPS_STATE = .NONE
    var gpsState: GPS_STATE {
        get {
            return _gpsState
        }
        set(gpsState) {
            if gpsState != _gpsState {
                // update collection of GPX points
                if _gpsState == .NONE && gpsState != .NONE {
                    // because recording GPX tracks is cheap we record them every time GPS is enabled
                    gpxLayer.startNewTrack()
                } else if gpsState == .NONE {
                    gpxLayer.endActiveTrack()
                }

                if gpsState == .HEADING {
                    // rotate to heading
                    let center = CGRectCenter(bounds)
					let screenAngle = screenFromMapTransform.rotation()
                    let heading = self.heading(for: locationManager.heading)
                    animateRotation(by: -(screenAngle + heading), aroundPoint: center)
                } else if gpsState == .LOCATION {
                    // orient toward north
                    let center = CGRectCenter(bounds)
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

                _gpsState = gpsState
                if _gpsState != .NONE {
                    locating = true
                } else {
                    locating = false
                }
            }
        }
    }

    var gpsInBackground: Bool {
        get {
            return UserDefaults.standard.bool(forKey: GpxLayer.USER_DEFAULTS_GPX_EXPIRATIION_KEY)
        }
        set(gpsInBackground) {
            UserDefaults.standard.set(gpsInBackground, forKey: GpxLayer.USER_DEFAULTS_GPX_BACKGROUND_TRACKING)

            locationManager.allowsBackgroundLocationUpdates = gpsInBackground && enableGpxLogging

            if gpsInBackground {
                // ios 8 and later:
                if locationManager.responds(to: #selector(CLLocationManager.requestAlwaysAuthorization)) {
                    locationManager.requestAlwaysAuthorization()
                }
            }
        }
    }
    private(set) var pushpinView: PushPinView?
    var silentUndo = false // don't flash message about undo
	let customAerials: AerialList
    private(set) var birdsEyeRotation: CGFloat = 0.0
    private(set) var birdsEyeDistance: CGFloat = 0.0

    private var _enableBirdsEye = false
    var enableBirdsEye: Bool {
        get {
            _enableBirdsEye
        }
        set(enableBirdsEye) {
            if _enableBirdsEye != enableBirdsEye {
                _enableBirdsEye = enableBirdsEye
                if !enableBirdsEye {
                    // remove birdsEye
                    rotateBirdsEye(by: -birdsEyeRotation)
                }
            }
        }
    }

    var enableRotation: Bool = false {
		didSet {
			if !enableRotation {
				// remove rotation
				let centerPoint = CGRectCenter(bounds)
				let angle = CGFloat(screenFromMapTransform.rotation())
				rotate(by: -angle, aroundScreenPoint: centerPoint)
            }
        }
    }

    var enableUnnamedRoadHalo: Bool = false {
		didSet {
			editorLayer.mapData.clearCachedProperties() // reset layers associated with objects
			editorLayer.setNeedsLayout()
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
			editorLayer.mapData.clearCachedProperties() // reset layers associated with objects
			editorLayer.setNeedsLayout()
        }
    }
    var enableAutomaticCacheManagement = false

	private let NAME = "autoScroll"
    var automatedFramerateTestActive: Bool {
        get {
            let displayLink = DisplayLink.shared()
            return displayLink.hasName(NAME)
        }
        set(enable) {
            let displayLink = DisplayLink.shared()

            if enable == displayLink.hasName(NAME) {
                // nothing to do
            } else if enable {
                // automaatically scroll view for frame rate testing
                fpsLabel.showFPS = true

                // this set's the starting center point
                let startLatLon = OSMPoint(x: -122.205831, y: 47.675024)
                let startZoom = 17.302591
                setTransformForLatitude(startLatLon.y, longitude: startLatLon.x, zoom: startZoom)

                // sets the size of the circle
                let radius: Double = 100
                let startAngle: CGFloat = 1.5 * .pi
                let rpm: CGFloat = 2.0
                let zoomTotal: CGFloat = 1.1 // 10% larger
                let zoomDelta = pow(zoomTotal, 1 / 60.0)

                var angle = startAngle
                var prevTime = CACurrentMediaTime()
                weak var weakSelf = self

                displayLink.addName(NAME, block: {
					guard let myself = weakSelf else { return }
					let time = CACurrentMediaTime()
                    let delta = time - prevTime
                    let newAngle = angle + (2 * .pi) / rpm * CGFloat(delta) // angle change depends on framerate to maintain 2/RPM

                    if angle < startAngle && newAngle >= startAngle {
                        // reset to start position
						myself.setTransformForLatitude(startLatLon.y, longitude: startLatLon.x, zoom: startZoom)
                        angle = startAngle
                    } else {
                        // move along circle
                        let x1 = cos(angle)
                        let y1 = sin(angle)
                        let x2 = cos(newAngle)
                        let y2 = sin(newAngle)
                        let dx = CGFloat(Double((x2 - x1)) * radius)
                        let dy = CGFloat(Double((y2 - y1)) * radius)

						myself.adjustOrigin(by: CGPoint(x: dx, y: dy))
                        let zoomRatio = Double(dy >= 0 ? zoomDelta : 1 / zoomDelta)
						myself.adjustZoom(by: CGFloat(zoomRatio), aroundScreenPoint: myself.crossHairs.position)
                        angle = fmod(newAngle, 2 * .pi)
					}
                    prevTime = time
                })
            } else {
                fpsLabel.showFPS = false
                displayLink.removeName(NAME)
            }
        }
    }
    private(set) var crossHairs: CAShapeLayer
    private(set) var countryCodeForLocation: String?
    private(set) var countryCodeLocation: CLLocationCoordinate2D?

    var pushpinPosition: CGPoint? {
        return pushpinView?.arrowPoint
	}

    private var _locating = false
    var locating: Bool {
        get {
            _locating
        }
        set(locating) {
            if _locating == locating {
                return
            }
            _locating = locating

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
            } else {
                locationManager.stopUpdatingLocation()
                locationManager.stopUpdatingHeading()
                locationBallLayer?.removeFromSuperlayer()
                locationBallLayer = nil
            }
        }
    }
    @IBOutlet private var statusBarBackground: UIVisualEffectView!

    // MARK: initialization

    required init?(coder: NSCoder) {

		self.crossHairs = CAShapeLayer()
		self.customAerials = AerialList()

		super.init(coder: coder)

		layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            backgroundColor = UIColor.systemGray6
        } else {
            backgroundColor = UIColor(white: 0.85, alpha: 1.0)
        }

        birdsEyeDistance = 1000.0

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
        locatorLayer.aerialService = AerialService.mapboxLocator
        locatorLayer.isHidden = true
        bg.append(locatorLayer)

        gpsTraceLayer = MercatorTileLayer(mapView: self)
        gpsTraceLayer.zPosition = Z_GPSTRACE
        gpsTraceLayer.aerialService = AerialService.gpsTrace
        gpsTraceLayer.isHidden = true
        bg.append(gpsTraceLayer)

        noNameLayer = MercatorTileLayer(mapView: self)
        noNameLayer.zPosition = Z_NONAME
        noNameLayer.aerialService = AerialService.noName
        noNameLayer.isHidden = true
        bg.append(noNameLayer)

        aerialLayer = MercatorTileLayer(mapView: self)
        aerialLayer.zPosition = Z_AERIAL
        aerialLayer.opacity = 0.75
        aerialLayer.aerialService = customAerials.currentAerial
        aerialLayer.isHidden = true
        bg.append(aerialLayer)

        mapnikLayer = MercatorTileLayer(mapView: self)
        mapnikLayer.aerialService = AerialService.mapnikAerialService
        mapnikLayer.zPosition = Z_MAPNIK
        mapnikLayer.isHidden = true
        bg.append(mapnikLayer)

        editorLayer = EditorMapLayer(mapView: self)
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

        if true {
            // implement crosshairs
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

            crossHairs.position = CGRectCenter(bounds)
			layer.addSublayer(crossHairs)
        }

        #if false
        voiceAnnouncement = VoiceAnnouncement()
        voiceAnnouncement?.mapView = self
        voiceAnnouncement?.radius = 30 // meters
        #endif

        weak var weakSelf = self
        editorLayer.mapData.undoCommentCallback = { undo, context in

			guard let myself = weakSelf,
				  !myself.silentUndo
			else {
				return
            }

			guard let action = context["comment"] as? String,
				  let location = context["location"] as? Data
			else { return }
			if location.count == MemoryLayout<OSMTransform>.size {
				location.withUnsafeBytes({ bytes in
                    let transform = bytes as AnyObject
					if let transform = transform as? OSMTransform {
                        weakSelf?.screenFromMapTransform = transform
                    }
                })
            }
			let title = undo ? NSLocalizedString("Undo", comment: "") : NSLocalizedString("Redo", comment: "")

            myself.editorLayer.selectedRelation = context["selectedRelation"] as? OsmRelation
            myself.editorLayer.selectedWay = context["selectedWay"] as? OsmWay
            myself.editorLayer.selectedNode = context["selectedNode"] as? OsmNode
            if myself.editorLayer.selectedNode?.deleted ?? false {
                myself.editorLayer.selectedNode = nil
			}

			if let pushpin = context["pushpin"] as? String,
			   let primary = myself.editorLayer.selectedPrimary
			{
                // since we don't record the pushpin location until after a drag has begun we need to re-center on the object:
                var pt = NSCoder.cgPoint(for: pushpin)
                let loc = myself.longitudeLatitude(forScreenPoint: pt, birdsEye: true)
                let pos = primary.pointOnObjectForPoint(OSMPoint(x: loc.longitude, y: loc.latitude))
				pt = myself.screenPoint(forLatitude: pos.y, longitude: pos.x, birdsEye: true)
                // place pushpin
				myself.placePushpin(at: pt, object: primary)
            } else {
                myself.removePin()
            }
            let message = "\(title) \(action)"
            myself.flashMessage(message)
        }
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

        // observe changes to aerial visibility so we can show/hide bing logo
        aerialLayer.addObserver(self, forKeyPath: "hidden", options: .new, context: nil)
        editorLayer.addObserver(self, forKeyPath: "hidden", options: .new, context: nil)

        editorLayer.whiteText = !aerialLayer.isHidden

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
    }

    func viewDidAppear() {
        // Only want to run this once. On older versions of iOS viewDidAppear is called multiple times
        if !windowPresented {
            windowPresented = true

            // get current location
            let scale = UserDefaults.standard.double(forKey: "view.scale")
            let latitude = UserDefaults.standard.double(forKey: "view.latitude")
            let longitude = UserDefaults.standard.double(forKey: "view.longitude")

            if !latitude.isNaN && !longitude.isNaN && !scale.isNaN {
				setTransformFor(latitude: latitude,
								longitude: longitude,
								scale: scale)
            } else {
                let rc = OSMRect(layer.bounds)
				screenFromMapTransform = OSMTransform.Translation(rc.origin.x + rc.size.width / 2 - 128,
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

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if (object as? MercatorTileLayer) == aerialLayer && keyPath == "hidden" {
			let hidden = (change?[.newKey] as? NSNumber)?.boolValue ?? false
            aerialServiceLogo.isHidden = hidden
        } else if (object as? EditorMapLayer) == editorLayer && (keyPath == "hidden") {
            let hidden = (change?[.newKey] as? NSNumber)?.boolValue ?? false
            if hidden {
                editorLayer.selectedNode = nil
                editorLayer.selectedWay = nil
                editorLayer.selectedRelation = nil
                removePin()
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func save() {
        // save defaults firs
        var center = OSMPoint(crossHairs.position)
        center = mapPoint(fromScreenPoint: center, birdsEye: false)
        center = LongitudeLatitudeFromMapPoint(center)
		let scale = screenFromMapTransform.scale()
        #if false && DEBUG
        assert(scale > 1.0)
        #endif
        UserDefaults.standard.set(scale, forKey: "view.scale")
        UserDefaults.standard.set(center.y, forKey: "view.latitude")
        UserDefaults.standard.set(center.x, forKey: "view.longitude")

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

        customAerials.save()
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

        crossHairs.position = CGRectCenter(bounds)

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
        let service = aerialLayer.aerialService
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

    func showAlert(_ title: String?, message: String?) {
        let alertError = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        mainViewController.present(alertError, animated: true)
    }

    func html(asAttributedString html: String, textColor: UIColor, backgroundColor backColor: UIColor) -> NSAttributedString? {
        if html.hasPrefix("<") {
            var attrText: NSAttributedString? = nil
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

        DispatchQueue.main.asyncAfter(deadline: popTime, execute: {
            UIView.animate(withDuration: 0.35, animations: {
                self.flashLabel.alpha = 0.0
            }) { finished in
                if finished && self.flashLabel.layer.presentation()?.opacity == 0.0 {
                    self.flashLabel.isHidden = true
                }
            }
        })
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
            var ignoreButton: String? = nil
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
                if self.ignoreNetworkErrorsUntilDate != nil {
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
                    alertError.addAction(UIAlertAction(title: ignoreButton, style: .default, handler: { [self] action in
                        // ignore network errors for a while
                        ignoreNetworkErrorsUntilDate = Date().addingTimeInterval(5 * 60.0)
                    }))
                }
                mainViewController.present(alertError, animated: true)
            }
        }
        if !flash {
            self.lastErrorDate = Date()
        }
    }

    func ask(toRate uploadCount: Int) {
        let countLog10 = log10(Double(uploadCount))
        if uploadCount > 1 && countLog10 == floor(countLog10) {
            let title = String.localizedStringWithFormat(NSLocalizedString("You've uploaded %ld changesets with this version of Go Map!!\n\nRate this app?", comment: ""), uploadCount)
            let alertViewRateApp = UIAlertController(title: title, message: NSLocalizedString("Rating this app makes it easier for other mappers to discover it and increases the visibility of OpenStreetMap.", comment: ""), preferredStyle: .alert)
            alertViewRateApp.addAction(UIAlertAction(title: NSLocalizedString("Maybe later...", comment: "rate the app later"), style: .cancel, handler: { action in
            }))
            alertViewRateApp.addAction(UIAlertAction(title: NSLocalizedString("I'll do it!", comment: "rate the app now"), style: .default, handler: { [self] action in
                showInAppStore()
            }))
            mainViewController.present(alertViewRateApp, animated: true)
        }
    }

    func showInAppStore() {
        #if true
        let urlText = "itms-apps://itunes.apple.com/app/id\(NSNumber(value: 592990211))"
        let url = URL(string: urlText)
        if let url = url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
		#else
        let spvc = SKStoreProductViewController()
        spvc.delegate = self //self is the view controller to present spvc
        spvc.loadProduct(
            withParameters: [
                SKStoreProductParameterITunesItemIdentifier: NSNumber(value: 592990211)
            ],
            completionBlock: { [self] result, error in
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
        let aerial = aerialLayer.aerialService
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
        let loc = longitudeLatitude(forScreenPoint: center, birdsEye: true)
        let distance = GreatCircleDistance(OSMPoint(x: loc.longitude, y: loc.latitude), OSMPoint(x: countryCodeLocation?.longitude ?? 0.0, y: countryCodeLocation?.latitude ?? 0.0))
        if distance < 10 * 1000 {
            return
        }
        countryCodeLocation = loc

        let url = "https://nominatim.openstreetmap.org/reverse?zoom=13&addressdetails=1&format=json&lat=\(loc.latitude)&lon=\(loc.longitude)"
        var task: URLSessionDataTask? = nil
        if let url1 = URL(string: url) {
            task = URLSession.shared.dataTask(with: url1, completionHandler: { data, response, error in
                if (data?.count ?? 0) != 0 {
                    var json: Any? = nil
                    do {
                        if let data = data {
                            json = try JSONSerialization.jsonObject(with: data, options: [])
                        }
                    } catch {
                    }
                    if let json = json as? [String: Any] {
                        if let address = json["address"] as? [String: Any] {
                            let code = address["country_code"] as? String
                            if let code = code {
                                DispatchQueue.main.async(execute: {
                                    self.countryCodeForLocation = code
                                })
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
		guard let rotateObjectCenter = editorLayer.selectedNode?.location()
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
        let center = screenPoint(forLatitude: rotateObjectCenter.y, longitude: rotateObjectCenter.x, birdsEye: true)
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

		self.isRotateObjectMode = (rotateObjectOverlay,rotateObjectCenter)
    }

    func endObjectRotation() {
		isRotateObjectMode?.rotateObjectOverlay.removeFromSuperlayer()
        placePushpinForSelection()
        confirmDrag = false
		isRotateObjectMode = nil
	}

    func viewStateWillChangeTo(_ state: MapViewState, overlays: MapViewOverlays, zoomedOut: Bool) {
        if viewState == state && viewOverlayMask == overlays && viewStateZoomedOut == zoomedOut {
            return
		}

		let oldState = StateFor(viewState, zoomedOut: viewStateZoomedOut)
		let newState = StateFor(state, zoomedOut: zoomedOut)
		let oldOverlays = OverlaysFor(viewState, overlays: viewOverlayMask, zoomedOut: viewStateZoomedOut)
		let newOverlays = OverlaysFor(state, overlays: overlays, zoomedOut: zoomedOut)
        if newState == oldState && newOverlays == oldOverlays {
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)

		locatorLayer.isHidden 	= !newOverlays.contains(.LOCATOR)
		gpsTraceLayer.isHidden 	= !newOverlays.contains(.GPSTRACE)
		noNameLayer.isHidden	= !newOverlays.contains(.NONAME)

		switch newState {
            case MapViewState.EDITOR:
                editorLayer.isHidden = false
                aerialLayer.isHidden = true
                mapnikLayer.isHidden = true
                userInstructionLabel.isHidden = true
                editorLayer.whiteText = true
            case MapViewState.EDITORAERIAL:
                aerialLayer.aerialService = customAerials.currentAerial
                editorLayer.isHidden = false
                aerialLayer.isHidden = false
                mapnikLayer.isHidden = true
                userInstructionLabel.isHidden = true
                aerialLayer.opacity = 0.75
                editorLayer.whiteText = true
            case MapViewState.AERIAL:
                aerialLayer.aerialService = customAerials.currentAerial
                editorLayer.isHidden = true
                aerialLayer.isHidden = false
                mapnikLayer.isHidden = true
                userInstructionLabel?.isHidden = true
                aerialLayer.opacity = 1.0
            case MapViewState.MAPNIK:
                editorLayer.isHidden = true
                aerialLayer.isHidden = true
                mapnikLayer.isHidden = false
                userInstructionLabel.isHidden = viewState != .EDITOR && viewState != .EDITORAERIAL
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
    }

    func setAerialTileService(_ service: AerialService) {
        aerialLayer.aerialService = service
        updateAerialAttributionButton()
    }

	static func mapRect(forLatLonRect latLon: OSMRect) -> OSMRect {
        var rc = latLon
        let p1 = MapPointForLatitudeLongitude(rc.origin.y + rc.size.height, rc.origin.x) // latitude increases opposite of map
        let p2 = MapPointForLatitudeLongitude(rc.origin.y, rc.origin.x + rc.size.width)
		rc = OSMRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y) // map size
        return rc
    }

    func mapPoint(fromScreenPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
        var point = point
        if birdsEyeRotation != 0.0 && birdsEye {
            let center = CGRectCenter(layer.bounds)
            point = FromBirdsEye(point, center, Double(birdsEyeDistance), Double(birdsEyeRotation))
        }
        point = OSMPointApplyTransform(point, mapFromScreenTransform)
        return point
    }

    func screenPoint(fromMapPoint point: OSMPoint, birdsEye: Bool) -> OSMPoint {
        var point = point
        point = OSMPointApplyTransform(point, screenFromMapTransform)
        if birdsEyeRotation != 0.0 && birdsEye {
            let center = CGRectCenter(layer.bounds)
            point = ToBirdsEye(point, center, Double(birdsEyeDistance), Double(birdsEyeRotation))
        }
        return point
    }

    func wrapScreenPoint(_ pt: CGPoint) -> CGPoint {
        var pt = pt
        if true /*fabs(_screenFromMapTransform.a) < 16 && fabs(_screenFromMapTransform.c) < 16*/ {
            // only need to do this if we're zoomed out all the way: pick the best world map on which to display location

            let rc = layer.bounds
			let unitX = screenFromMapTransform.unitX()
            let unitY = OSMPoint(x: -unitX.y, y: unitX.x)
			let mapSize: Double = 256 * screenFromMapTransform.scale()
			if pt.x >= rc.origin.x + rc.size.width {
                pt.x -= CGFloat(mapSize * unitX.x)
                pt.y -= CGFloat(mapSize * unitX.y)
            } else if pt.x < rc.origin.x {
                pt.x += CGFloat(mapSize * unitX.x)
                pt.y += CGFloat(mapSize * unitX.y)
            }
            if pt.y >= rc.origin.y + rc.size.height {
                pt.x -= CGFloat(mapSize * unitY.x)
                pt.y -= CGFloat(mapSize * unitY.y)
            } else if pt.y < rc.origin.y {
                pt.x += CGFloat(mapSize * unitY.x)
                pt.y += CGFloat(mapSize * unitY.y)
            }
        }
        return pt
    }

    func mapRect(fromScreenRect rect: OSMRect) -> OSMRect {
        return OSMRectApplyTransform(rect, mapFromScreenTransform)
    }

    func screenRect(fromMapRect rect: OSMRect) -> OSMRect {
        return OSMRectApplyTransform(rect, screenFromMapTransform)
    }

    func longitudeLatitude(forScreenPoint point: CGPoint, birdsEye: Bool) -> CLLocationCoordinate2D {
        let mapPoint = self.mapPoint(fromScreenPoint: OSMPoint(x: Double(point.x), y: Double(point.y)), birdsEye: birdsEye)
        let coord = LongitudeLatitudeFromMapPoint(mapPoint)
        let loc = CLLocationCoordinate2D(latitude: coord.y, longitude: coord.x)
        return loc
    }

    func metersPerPixel() -> Double {
		let p1 = crossHairs.position
        let p2 = CGPoint(x: p1.x + 1.0, y: p1.y)	// one pixel apart
		let c1 = longitudeLatitude(forScreenPoint: p1, birdsEye: false)
        let c2 = longitudeLatitude(forScreenPoint: p2, birdsEye: false)
        let o1 = OSMPoint(x: c1.longitude, y: c1.latitude)
        let o2 = OSMPoint(x: c2.longitude, y: c2.latitude)
        let meters = GreatCircleDistance(o1, o2)
        return meters
	}

    func boundingScreenRect(forMapRect mapRect: OSMRect) -> OSMRect {
        var rc = mapRect
        var corners = [OSMPoint(x: rc.origin.x, y: rc.origin.y),
                       OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y),
                       OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y + rc.size.height),
                       OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)
        ]
        for i in 0..<4 {
            corners[i] = screenPoint(fromMapPoint: corners[i], birdsEye: false)
        }

        var minX = corners[0].x
        var minY = corners[0].y
        var maxX = minX
        var maxY = minY
        for i in 1..<4 {
            minX = Double(min(minX, corners[i].x))
            maxX = Double(max(maxX, corners[i].x))
            minY = Double(min(minY, corners[i].y))
            maxY = Double(max(maxY, corners[i].y))
        }
		rc = OSMRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return rc
    }

    func boundingMapRect(forScreenRect screenRect: OSMRect) -> OSMRect {
        var rc = screenRect
        var corners = [OSMPoint(x: rc.origin.x, y: rc.origin.y),
                       OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y),
                       OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y + rc.size.height),
                       OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)
        ]
        for i in 0..<4 {
            corners[i] = mapPoint(fromScreenPoint: corners[i], birdsEye: true)
        }
        var minX = corners[0].x
        var minY = corners[0].y
        var maxX = minX
        var maxY = minY
        for i in 1..<4 {
            minX = Double(min(minX, corners[i].x))
            maxX = Double(max(maxX, corners[i].x))
            minY = Double(min(minY, corners[i].y))
            maxY = Double(max(maxY, corners[i].y))
        }

		rc = OSMRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return rc
    }

    func boundingMapRectForScreen() -> OSMRect {
        let rc = OSMRect(layer.bounds)
        return boundingMapRect(forScreenRect: rc)
    }

    func screenLongitudeLatitude() -> OSMRect {
        //        #if true
        var rc = boundingMapRectForScreen()
        //        #else
        //        var rc = mapRectFromScreenRect()
        //        #endif
        var southwest = OSMPoint(x: rc.origin.x, y: rc.origin.y + rc.size.height)
        var northeast = OSMPoint(x: rc.origin.x + rc.size.width, y: rc.origin.y)
        southwest = LongitudeLatitudeFromMapPoint(southwest)
        northeast = LongitudeLatitudeFromMapPoint(northeast)
        rc.origin.x = southwest.x
        rc.origin.y = southwest.y
        rc.size.width = northeast.x - southwest.x
        rc.size.height = northeast.y - southwest.y
        if rc.size.width < 0 {
            rc.size.width += 360
        }
        if rc.size.height < 0 {
            rc.size.height += 180
        }
        return rc
    }

    func screenPoint(forLatitude latitude: Double, longitude: Double, birdsEye: Bool) -> CGPoint {
        var pt = MapPointForLatitudeLongitude(latitude, longitude)
        pt = screenPoint(fromMapPoint: pt, birdsEye: birdsEye)
        return CGPointFromOSMPoint(pt)
    }

    func setTransformFor( latitude: Double, longitude: Double) {
        let point = screenPoint(forLatitude: latitude, longitude: longitude, birdsEye: false)
        let center = crossHairs.position
        let delta = CGPoint(x: center.x - point.x, y: center.y - point.y)
		adjustOrigin(by: delta)
    }

    func setTransformFor(latitude: Double, longitude: Double, scale: Double) {
        // translate
		setTransformFor(latitude: latitude, longitude: longitude)

		let ratio = scale / screenFromMapTransform.scale()
		adjustZoom(by: CGFloat(ratio), aroundScreenPoint: crossHairs.position)
    }

    func setTransformFor(latitude: Double, longitude: Double, width widthDegrees: Double) {
        let scale = 360 / (widthDegrees / 2)
		setTransformFor(latitude: latitude,
						longitude: longitude,
						scale: scale)
    }

    func setMapLocation(_ location: MapLocation) {
		let zoom = location.zoom > 0 ? location.zoom : 18.0
		let scale = pow(2, zoom)
		self.setTransformFor(latitude: location.latitude,
							 longitude: location.longitude,
							 scale: scale)
		if let state = location.viewState {
			self.viewState = state
		}
    }

    func setTransformForLatitude(_ latitude: Double, longitude: Double, zoom: Double) {
        let scale = pow(2, zoom)
		setTransformFor(latitude: latitude,
						longitude: longitude,
						scale: scale)
    }

    func zoom() -> Double {
		let scaleX = screenFromMapTransform.scale()
		return log2(scaleX)
    }

    func point(on object: OsmBaseObject?, for point: CGPoint) -> CGPoint {
        let latLon = longitudeLatitude(forScreenPoint: point, birdsEye: true)
		let latLon2 = object?.pointOnObjectForPoint(OSMPoint(x: latLon.longitude, y: latLon.latitude))
        let pos = screenPoint(forLatitude: latLon2?.y ?? 0.0, longitude: latLon2?.x ?? 0.0, birdsEye: true)
        return pos
    }

    // MARK: Discard stale data

    func discardStaleData() {
        if enableAutomaticCacheManagement {
            let mapData = editorLayer.mapData
            let changed = mapData.discardStaleData()
            if changed {
                flashMessage(NSLocalizedString("Cache trimmed", comment: ""))
                editorLayer.updateMapLocation() // download data if necessary
            }
        }
    }

    // MARK: Progress indicator

    func progressIncrement() {
        assert(progressActive >= 0)
        progressActive += 1
    }

    func progressDecrement() {
        assert(progressActive > 0)
        progressActive -= 1
        if progressActive == 0 {
            //            #if os(iOS)
            progressIndicator.stopAnimating()
            //            #else
            //            progressIndicator.stopAnimation()
            //            #endif
        }
    }

    func progressAnimate() {
        assert(progressActive >= 0)
        if progressActive > 0 {
            //            #if os(iOS)
            progressIndicator.startAnimating()
            //            #else
            //            progressIndicator.startAnimating()
            //            #endif
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
			setTransformFor(latitude: location.coordinate.latitude,
							longitude: location.coordinate.longitude)
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
        if locationBallLayer != nil {
            // set new position
            let coord = location != nil ? location?.coordinate ?? CLLocationCoordinate2D() : locationManager.location?.coordinate ?? CLLocationCoordinate2D()
            var point = screenPoint(forLatitude: coord.latitude, longitude: coord.longitude, birdsEye: true)

            point = wrapScreenPoint(point)
            locationBallLayer?.position = point

            // set location accuracy
            let meters = locationManager.location?.horizontalAccuracy ?? 0
            var pixels = CGFloat(meters / metersPerPixel())
            if pixels == 0.0 {
                pixels = 100.0
            }
            locationBallLayer?.radiusInPixels = pixels
        }
    }

    func heading(for clHeading: CLHeading?) -> Double {
        var heading = (clHeading?.trueHeading ?? 0.0) * .pi / 180
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

    func updateHeadingSmoothed(_ heading: CGFloat, accuracy: CGFloat) {
		let screenAngle = screenFromMapTransform.rotation()

        if gpsState == .HEADING {
            // rotate to new heading
            let center = CGRectCenter(bounds)
            let delta = -(heading + CGFloat(screenAngle))
            rotate(by: CGFloat(delta), aroundScreenPoint: center)
        } else if locationBallLayer != nil {
            // rotate location ball
            locationBallLayer?.headingAccuracy = accuracy * (.pi / 180)
            locationBallLayer?.showHeading = true
            locationBallLayer?.heading = heading + CGFloat(screenAngle) - .pi / 2
        }
    }

    static var locationManagerSmoothHeading = 0.0

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let accuracy = newHeading.headingAccuracy
        let heading = self.heading(for: newHeading)

        DisplayLink.shared().addName("smoothHeading", block: { [self] in
            var delta = heading - MapView.locationManagerSmoothHeading
            if delta > .pi {
                delta -= 2 * .pi
            } else if delta < -.pi {
                delta += 2 * .pi
            }
            delta *= 0.15
            if abs(Float(delta)) < 0.001 {
                MapView.locationManagerSmoothHeading = heading
            } else {
                MapView.locationManagerSmoothHeading += delta
            }
            updateHeadingSmoothed(CGFloat(MapView.locationManagerSmoothHeading), accuracy: CGFloat(accuracy))
            if heading == MapView.locationManagerSmoothHeading {
                DisplayLink.shared().removeName("smoothHeading")
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
		let p1 = OSMPoint( newLocation.coordinate )
		let p2 = OSMPoint( currentLocation.coordinate )
		let delta = GreatCircleDistance(p1, p2)
		if locationBallLayer != nil && delta < 0.1 && abs(newLocation.horizontalAccuracy - currentLocation.horizontalAccuracy) < 1.0 {
			return
        }
        currentLocation = newLocation

        if let voiceAnnouncement = voiceAnnouncement,
			!editorLayer.isHidden
		{
			voiceAnnouncement.announce(forLocation: newLocation.coordinate)
        }

		if (self.gpxLayer.activeTrack != nil) {
            gpxLayer.addPoint(newLocation)
        }

        if gpsState == .NONE {
            locating = false
        }

        let pp = longitudeLatitude(forScreenPoint: pushpinView?.arrowPoint ?? CGPoint.zero, birdsEye: false)

        if !userOverrodeLocationPosition {
            // move view to center on new location
            if userOverrodeLocationZoom {
				setTransformFor(latitude: newLocation.coordinate.latitude,
								longitude: newLocation.coordinate.longitude)
			} else {
				let widthDegrees: Double = Double(20.0 /*meters*/ / EarthRadius * 360.0)
				setTransformFor(latitude: newLocation.coordinate.latitude,
								longitude: newLocation.coordinate.longitude,
								width: widthDegrees)
			}
        }

		pushpinView?.arrowPoint = screenPoint(forLatitude: pp.latitude, longitude: pp.longitude, birdsEye: false)

		if locationBallLayer == nil {
            locationBallLayer = LocationBallLayer()
            locationBallLayer?.zPosition = Z_BALL
            locationBallLayer?.heading = 0.0
            locationBallLayer?.showHeading = true
			layer.addSublayer(locationBallLayer!)
		}
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
				setTransformFor(latitude: 47.6858,
								longitude: -122.1917,
								width: 0.01)
            }
			var text = String.localizedStringWithFormat(NSLocalizedString("Ensure Location Services is enabled and you have granted this application access.\n\nError: %@",	comment: ""),
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
		let loc: OSMPoint
		if let point = point {
			let latLon = longitudeLatitude(forScreenPoint:point, birdsEye: true)
			loc = selection.pointOnObjectForPoint(OSMPoint(latLon))
		} else {
			loc = selection.selectionPoint()
		}
        let point = screenPoint(forLatitude: loc.y, longitude: loc.x, birdsEye: true)
        placePushpin(at: point, object: selection)

        if !bounds.contains(pushpinView!.arrowPoint) {
            // need to zoom to location
			setTransformFor(latitude: loc.y,
							longitude: loc.x)
        }
    }

    @IBAction func undo(_ sender: Any?) {
        if editorLayer.isHidden {
			flashMessage(NSLocalizedString("Editing layer not visible", comment: ""))
			return
		}
		// if just dropped a pin then undo removes the pin
		if pushpinView != nil && editorLayer.selectedPrimary == nil {
			removePin()
			return
		}

        removePin()

        editorLayer.mapData.undo()
        editorLayer.setNeedsLayout()
    }

    @IBAction func redo(_ sender: Any?) {
        if editorLayer.isHidden {
            flashMessage(NSLocalizedString("Editing layer not visible", comment: ""))
            return
        }
        removePin()

        editorLayer.mapData.redo()
        editorLayer.setNeedsLayout()
    }

    // MARK: Resize & movement

    func isLocationSpecified() -> Bool {
		return !(screenFromMapTransform == .identity)
	}

    func updateMouseCoordinates() {
    }

    func adjustOrigin(by delta: CGPoint) {
        if delta.x == 0.0 && delta.y == 0.0 {
            return
        }

        refreshNoteButtonsFromDatabase()

		let o = OSMTransform.Translation(Double(delta.x), Double(delta.y))
		let t = screenFromMapTransform.concat( o )
		self.screenFromMapTransform = t
    }

    func adjustZoom(by ratio: CGFloat, aroundScreenPoint zoomCenter: CGPoint) {
		guard ratio != 1.0,
			  isRotateObjectMode == nil
		else {
			return
        }

        let maxZoomIn: Double = Double(Int(1) << 30)

		let scale = screenFromMapTransform.scale()
		var ratio = Double(ratio)
        if ratio * scale < 1.0 {
            ratio = 1.0 / scale
        }
        if ratio * scale > maxZoomIn {
            ratio = maxZoomIn / scale
		}

        refreshNoteButtonsFromDatabase()
        let offset = mapPoint(fromScreenPoint: OSMPoint(zoomCenter), birdsEye: false)
        var t = screenFromMapTransform
		t = t.translatedBy(dx: offset.x, dy: offset.y)
		t = t.scaledBy( ratio )
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		screenFromMapTransform = t
    }

    func rotate(by angle: CGFloat, aroundScreenPoint zoomCenter: CGPoint) {
        if angle == 0.0 {
            return
        }

        refreshNoteButtonsFromDatabase()

        let offset = mapPoint(fromScreenPoint: OSMPoint(zoomCenter), birdsEye: false)
        var t = screenFromMapTransform
		t = t.translatedBy(dx: offset.x, dy: offset.y)
		t = t.rotatedBy( Double(angle) )
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		screenFromMapTransform = t

		let screenAngle = screenFromMapTransform.rotation()
        compassButton.transform = CGAffineTransform(rotationAngle: CGFloat(screenAngle))
        if let locationBallLayer = locationBallLayer {
            if gpsState == .HEADING && abs(locationBallLayer.heading - -.pi / 2) < 0.0001 {
				// don't pin location ball to North until we've animated our rotation to north
				self.locationBallLayer!.heading = -.pi / 2
            } else {
                let heading = self.heading(for: locationManager.heading)
				self.locationBallLayer!.heading = CGFloat(screenAngle + heading - .pi / 2)
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
        let displayLink = DisplayLink.shared()
		weak var weakSelf = self
		displayLink.addName(DisplayLinkHeading, block: {
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
                    displayLink.removeName(DisplayLinkHeading)
                }
            }
        })
    }

    func rotateBirdsEye(by angle: CGFloat) {
        var angle = angle
        // limit maximum rotation
        var t = screenFromMapTransform
        let maxRotation = Double(65 * (Double.pi / 180))
        #if TRANSFORM_3D
        let currentRotation = atan2(t.m23, t.m22)
        #else
        let currentRotation = Double(birdsEyeRotation)
        #endif
        if currentRotation + Double(angle) > maxRotation {
            angle = CGFloat(maxRotation - currentRotation)
        }
        if currentRotation + Double(angle) < 0 {
            angle = CGFloat(-currentRotation)
        }

        let center = CGRectCenter(bounds)
        let offset = mapPoint(fromScreenPoint: OSMPoint(center), birdsEye: false)

		t = t.translatedBy(dx: offset.x, dy: offset.y)
		#if TRANSFORM_3D
        t = CATransform3DRotate(t, delta, 1.0, 0.0, 0.0)
        #else
        birdsEyeRotation += angle
        #endif
		t = t.translatedBy(dx: -offset.x, dy: -offset.y)
		screenFromMapTransform = t

        if locationBallLayer != nil {
            updateUserLocationIndicator(nil)
        }
    }

    func rotateToNorth() {
        // Rotate to face North
        let center = CGRectCenter(bounds)
		let rotation = screenFromMapTransform.rotation()
		animateRotation(by: -rotation, aroundPoint: center)
    }

    // MARK: Key presses

    /// Offers the option to either merge tags or replace them with the copied tags.
    /// - Parameter sender: nil
    override func paste(_ sender: Any?) {
		guard let copyPasteTags = UserDefaults.standard.object(forKey: "copyPasteTags") as? [String : String],
			copyPasteTags.count > 0
		else {
            showAlert(NSLocalizedString("No tags to paste", comment: ""), message: nil)
            return
        }

        if (editorLayer.selectedPrimary?.tags.count ?? 0) > 0 {
            let question = String.localizedStringWithFormat(NSLocalizedString("Pasting %ld tag(s)", comment: ""), copyPasteTags.count)
			let alertPaste = UIAlertController(title: NSLocalizedString("Paste", comment: ""), message: question, preferredStyle: .alert)
            alertPaste.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            alertPaste.addAction(UIAlertAction(title: NSLocalizedString("Merge Tags", comment: ""), style: .default, handler: { [self] alertAction in
                if let selectedPrimary = editorLayer.selectedPrimary {
                    editorLayer.pasteTagsMerge(selectedPrimary)
                }
                refreshPushpinText()
            }))
            alertPaste.addAction(UIAlertAction(title: NSLocalizedString("Replace Tags", comment: ""), style: .default, handler: { [self] alertAction in
                if let selectedPrimary = editorLayer.selectedPrimary {
                    editorLayer.pasteTagsReplace(selectedPrimary)
                }
                refreshPushpinText()
            }))
            mainViewController.present(alertPaste, animated: true)
        } else {
            if let selectedPrimary = editorLayer.selectedPrimary {
                editorLayer.pasteTagsReplace(selectedPrimary)
            }
            refreshPushpinText()
        }
    }

    override func delete(_ sender: Any?) {
		guard let selectedPrimary = editorLayer.selectedPrimary,
			  let pushpinView = pushpinView
		else { return }

        let deleteHandler: ((_ action: UIAlertAction?) -> Void) = { [self] action in
            var error: String? = nil
			let canDelete: EditAction? = editorLayer.canDeleteSelectedObject(&error)
            if let canDelete = canDelete {
                canDelete()
				var pos = pushpinView.arrowPoint
                removePin()
                if editorLayer.selectedPrimary != nil {
					pos = point(on: editorLayer.selectedPrimary, for: pos)
					if let primary = editorLayer.selectedPrimary {
						placePushpin(at: pos, object: primary)
                    }
                }
            } else {
                showAlert(NSLocalizedString("Delete failed", comment: ""), message: error)
            }
        }

        let alertDelete: UIAlertController
		if (editorLayer.selectedRelation?.isMultipolygon() ?? false) && (selectedPrimary.isWay() != nil) {
            // delete way from relation
			alertDelete = UIAlertController(title: NSLocalizedString("Delete", comment: ""), message: NSLocalizedString("Member of multipolygon relation", comment: ""), preferredStyle: .actionSheet)
            alertDelete.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { action in
            }))
            alertDelete.addAction(UIAlertAction(title: NSLocalizedString("Delete completely", comment: ""), style: .default, handler: deleteHandler))
            alertDelete.addAction(UIAlertAction(title: NSLocalizedString("Detach from relation", comment: ""), style: .default, handler: { [self] action in
                var error: String? = nil
				if let canRemove: EditAction = editorLayer.mapData.canRemove(selectedPrimary, from:editorLayer.selectedRelation!, error:&error) {
					canRemove()
					editorLayer.selectedRelation = nil
					refreshPushpinText()
                } else {
					showAlert(NSLocalizedString("Delete failed", comment: ""), message: error)
                }
            }))

			// compute location for action sheet to originate
            var button = editControl.bounds
            let segmentWidth = button.size.width / CGFloat(editControl.numberOfSegments) // hack because we can't get the frame for an individual segment
            button.origin.x += button.size.width - 2 * segmentWidth
            button.size.width = segmentWidth
            alertDelete.popoverPresentationController?.sourceView = editControl
            alertDelete.popoverPresentationController?.sourceRect = button
        } else {
            // regular delete
            let name = editorLayer.selectedPrimary?.friendlyDescription()
            let question = "Delete \(name ?? "")?"
            alertDelete = UIAlertController(title: NSLocalizedString("Delete", comment: ""), message: question, preferredStyle: .alert)
            alertDelete.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            alertDelete.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive, handler: deleteHandler))
        }
		mainViewController.present(alertDelete, animated: true)
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
        let show = pushpinView != nil || editorLayer.selectedPrimary != nil
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
                    editControlActions = [ .EDITTAGS, .PASTETAGS, .DELETE, .MORE ]
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
		var actionList: [EDIT_ACTION] = []
		if let selectedWay = editorLayer.selectedWay {
            if let selectedNode = editorLayer.selectedNode {
                // node in way
                let parentWays: [OsmWay] = [] // [_editorLayer.mapData waysContainingNode:_editorLayer.selectedNode];
                let disconnect = parentWays.count > 1 || selectedNode.hasInterestingTags() || selectedWay.isSelfIntersection(selectedNode)
				let split = selectedWay.isClosed() || (selectedNode != selectedWay.nodes[0] && selectedNode != selectedWay.nodes.last)
				let join = parentWays.count > 1
				let restriction = enableTurnRestriction && editorLayer.selectedWay?.tags["highway"] != nil && parentWays.count > 1

				actionList = [.COPYTAGS]

                if disconnect {
					actionList.append(.DISCONNECT)
                }
                if split {
					actionList.append(.SPLIT)
                }
                if join {
					actionList.append(.JOIN)
                }
				actionList.append(.ROTATE)
                if restriction {
					actionList.append(.RESTRICT)
                }
			} else {
                if selectedWay.isClosed() {
                    // polygon
					actionList = [.COPYTAGS, .RECTANGULARIZE, .CIRCULARIZE, .ROTATE, .DUPLICATE, .REVERSE, .CREATE_RELATION ]
				} else {
                    // line
					actionList = [ .COPYTAGS, .STRAIGHTEN, .REVERSE, .DUPLICATE, .CREATE_RELATION ]
				}
            }
        } else if editorLayer.selectedNode != nil {
			// node
            actionList = [ .COPYTAGS, .DUPLICATE ]
        } else if let selectedRelation = editorLayer.selectedRelation {
			// relation
            if selectedRelation.isMultipolygon() {
				actionList = [ .COPYTAGS, .ROTATE, .DUPLICATE ]
			} else {
				actionList = [ .COPYTAGS, .PASTETAGS ]
            }
		} else {
			// nothing selected
			return
        }
        let actionSheet = UIAlertController(title: NSLocalizedString("Perform Action", comment: ""), message: nil, preferredStyle: .actionSheet)
        for value in actionList {
			let title = ActionTitle(value, false)
            actionSheet.addAction(UIAlertAction(title: title, style: .default, handler: { [self] action in
				performEdit(value)
            }))
        }
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: { action in
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
			performEdit(action)
        }
		segmentedControl.selectedSegmentIndex = UISegmentedControl.noSegment
    }

	/// Performs the selected action on the currently selected editor objects
	func performEdit(_ action: EDIT_ACTION) {
        // if trying to edit a node in a way that has no tags assume user wants to edit the way instead
        switch action {
            case .RECTANGULARIZE, .STRAIGHTEN, .REVERSE, .DUPLICATE, .ROTATE, .CIRCULARIZE, .COPYTAGS, .PASTETAGS, .EDITTAGS, .CREATE_RELATION:
                if (editorLayer.selectedWay != nil) && (editorLayer.selectedNode != nil) && (editorLayer.selectedNode?.tags.count ?? 0) == 0 && (editorLayer.selectedWay?.tags.count ?? 0) == 0 && !(editorLayer.selectedWay?.isMultipolygonMember() ?? false) {
                    // promote the selection to the way
                    editorLayer.selectedNode = nil
                    refreshPushpinText()
                }
            case .SPLIT, .JOIN, .DISCONNECT, .RESTRICT, .ADDNOTE, .DELETE, .MORE:
                break
        }

        var error: String? = nil
        switch action {
            case .COPYTAGS:
                if let selectedPrimary = editorLayer.selectedPrimary {
                    if !editorLayer.copyTags(selectedPrimary) {
                        error = NSLocalizedString("The object does not contain any tags", comment: "")
                    }
                }
            case .PASTETAGS:
                if editorLayer.selectedPrimary == nil {
                    // pasting to brand new object, so we need to create it first
                    setTagsForCurrentObject([:])
                }

                if editorLayer.selectedWay != nil && editorLayer.selectedNode != nil && editorLayer.selectedWay?.tags.count ?? 0 == 0 {
                    // if trying to edit a node in a way that has no tags assume user wants to edit the way instead
                    editorLayer.selectedNode = nil
                    refreshPushpinText()
                }
                paste(nil)
            case .DUPLICATE:
				guard let primary = editorLayer.selectedPrimary,
					  let pushpinView = pushpinView
				else { return }
				let delta = CGPoint(x: crossHairs.position.x - pushpinView.arrowPoint.x,
									y: crossHairs.position.y - pushpinView.arrowPoint.y)
                var offset: OSMPoint
                if hypot(delta.x, delta.y) > 20 {
                    // move to position of crosshairs
                    let p1 = longitudeLatitude(forScreenPoint: pushpinView.arrowPoint, birdsEye: true)
                    let p2 = longitudeLatitude(forScreenPoint: crossHairs.position, birdsEye: true)
					offset = OSMPoint(x: p2.longitude - p1.longitude, y: p2.latitude - p1.latitude)
                } else {
					offset = OSMPoint(x: 0.00005, y: -0.00005)
                }
				guard let newObject = editorLayer.duplicateObject(primary, withOffset: offset)
				else {
					error = NSLocalizedString("Could not duplicate object", comment: "")
					break
				}
				editorLayer.selectedNode = newObject.isNode()
				editorLayer.selectedWay = newObject.isWay()
				editorLayer.selectedRelation = newObject.isRelation()
				placePushpinForSelection()
            case .ROTATE:
                if editorLayer.selectedWay == nil && !(editorLayer.selectedRelation?.isMultipolygon() ?? false) {
                    error = NSLocalizedString("Only ways/multipolygons can be rotated", comment: "")
                } else {
                    startObjectRotation()
                }
            case .RECTANGULARIZE:
                if (editorLayer.selectedWay?.ident ?? 0) >= 0 && !OSMRectContainsRect(screenLongitudeLatitude(), editorLayer.selectedWay?.boundingBox ?? OSMRect()) {
                    error = NSLocalizedString("The selected way must be completely visible", comment: "") // avoid bugs where nodes are deleted from other objects
                } else {
					let rect: EditAction? = editorLayer.mapData.canOrthogonalizeWay(editorLayer.selectedWay!, error:&error)
                    if let rect = rect {
                        rect()
                    }
                }
            case .REVERSE:
				let reverse: EditAction? = editorLayer.mapData.canReverse( editorLayer.selectedWay!, error:&error)
				if let reverse = reverse {
                    reverse()
                }
            case .JOIN:
				let join: EditAction? = editorLayer.mapData.canJoin(editorLayer.selectedWay!, at:editorLayer.selectedNode!, error:&error)
				if let join = join {
					join()
                }
            case .DISCONNECT:
				let disconnect: EditActionReturnNode? = editorLayer.mapData.canDisconnectWay( editorLayer.selectedWay!, at:editorLayer.selectedNode!, error:&error)
				if let disconnect = disconnect {
					editorLayer.selectedNode = disconnect()
					placePushpinForSelection()
				}
            case .SPLIT:
				let split: EditActionReturnWay? = editorLayer.mapData.canSplitWay(editorLayer.selectedWay!, at:editorLayer.selectedNode!, error:&error)
				if let split = split {
					_ = split()
                }
            case .STRAIGHTEN:
				if let selectedWay = editorLayer.selectedWay {
					let boundingBox = selectedWay.boundingBox
					if selectedWay.ident >= 0 && !OSMRectContainsRect(screenLongitudeLatitude(), boundingBox) {
						error = NSLocalizedString("The selected way must be completely visible", comment: "") // avoid bugs where nodes are deleted from other objects
                    } else {
						let straighten: EditAction? = editorLayer.mapData.canStraightenWay(selectedWay, error:&error)
						if let straighten = straighten {
							straighten()
                        }
                    }
                }
            case .CIRCULARIZE:
				let circle: EditAction? = editorLayer.mapData.canCircularizeWay( editorLayer.selectedWay!, error:&error)
				if let circle = circle {
					circle()
                }
            case .EDITTAGS:
                presentTagEditor(nil)
            case .ADDNOTE:
				if let pushpinView = pushpinView {
					let pos = longitudeLatitude(forScreenPoint: pushpinView.arrowPoint, birdsEye: true)
					let note = OsmNote(lat: pos.latitude, lon: pos.longitude)
					mainViewController.performSegue(withIdentifier: "NotesSegue", sender: note)
					removePin()
				}
            case .DELETE:
                delete(nil)
            case .MORE:
                presentEditActionSheet(nil)
            case .RESTRICT:
                restrictOptionSelected()
            case .CREATE_RELATION:
                let create: ((_ type: String?) -> Void) = { [self] type in
                    let relation = editorLayer.mapData.createRelation()
                    var tags = editorLayer.selectedPrimary?.tags
                    if tags == nil {
                        tags = [:]
                    }
                    tags?["type"] = type
                    editorLayer.mapData.setTags(tags ?? [:], for: relation)
                    editorLayer.mapData.setTags([:], for: editorLayer.selectedPrimary!)

					var error: String? = nil
					let add: EditAction? = editorLayer.mapData.canAdd( editorLayer.selectedPrimary!, to:relation, withRole:"outer", error:&error)
					add?()
                    editorLayer.selectedNode = nil
                    editorLayer.selectedWay = nil
                    editorLayer.selectedRelation = relation
                    editorLayer.setNeedsLayout()
                    refreshPushpinText()
                    showAlert(
                        NSLocalizedString("Adding members:", comment: ""),
                        message: NSLocalizedString("To add another member to the relation 'long press' on the way to be added", comment: ""))
                }
                let actionSheet = UIAlertController(title: NSLocalizedString("Create Relation Type", comment: ""), message: nil, preferredStyle: .actionSheet)
                actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Multipolygon", comment: ""), style: .default, handler: { action2 in
                    create("multipolygon")
                }))
                actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))

                // compute location for action sheet to originate. This will be the uppermost node in the polygon
				guard var box = editorLayer.selectedPrimary?.boundingBox else { return }
				box = MapView.mapRect(forLatLonRect: box)
                let rc = boundingScreenRect(forMapRect: box)
				actionSheet.popoverPresentationController?.sourceView = self
				actionSheet.popoverPresentationController?.sourceRect = CGRectFromOSMRect(rc)
                mainViewController.present(actionSheet, animated: true)
                return
        }
        if let error = error {
            showAlert(error, message: nil)
        }

        editorLayer.setNeedsLayout()
        refreshPushpinText()
    }

    @IBAction func presentTagEditor(_ sender: Any?) {
        mainViewController.performSegue(withIdentifier: "poiSegue", sender: nil)
    }

    // Turn restriction panel
    func restrictOptionSelected() {
        let showRestrictionEditor: (() -> Void) = { [self] in
            let myVc = mainViewController.storyboard?.instantiateViewController(withIdentifier: "TurnRestrictController") as? TurnRestrictController
            myVc?.centralNode = editorLayer.selectedNode
            myVc?.screenFromMapTransform = screenFromMapTransform
            myVc?.modalPresentationStyle = UIModalPresentationStyle.overCurrentContext
            if let myVc = myVc {
                mainViewController.present(myVc, animated: true)
            }

            // if GPS is running don't keep moving around
            userOverrodeLocationPosition = true

            // scroll view so intersection stays visible
            let rc = myVc?.viewWithTitle.frame ?? .zero
            let pt = pushpinView?.arrowPoint ?? .zero
            let delta = CGPoint(x: Double(bounds.midX - pt.x), y: Double(bounds.midY - (rc.size.height) / 2 - pt.y))
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
                alert.addAction(UIAlertAction(title: NSLocalizedString("Edit restrictions", comment: ""), style: .destructive, handler: { action in
                    showRestrictionEditor()
                }))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
                mainViewController.present(alert, animated: true)
            } else {
                showRestrictionEditor()
            }
        }


        // if we currently have a relation selected then select the via node instead

        if editorLayer.selectedPrimary?.isRelation() != nil {
            let relation = editorLayer.selectedPrimary?.isRelation()
            let fromWay = relation?.member(byRole: "from")?.obj?.isWay()
            let viaNode = relation?.member(byRole: "via")?.obj?.isNode()

			if viaNode == nil {
                // not supported yet
                showAlert(
                    NSLocalizedString("Unsupported turn restriction type", comment: ""),
                    message: NSLocalizedString("This app does not yet support editing turn restrictions without a node as the 'via' member", comment: ""))
                return
            }

            editorLayer.selectedWay = fromWay
            editorLayer.selectedNode = viaNode
            if (editorLayer.selectedNode != nil) {
				placePushpinForSelection()
				restrictionEditWarning(editorLayer.selectedNode)
            }
        } else if ((editorLayer.selectedPrimary?.isNode()) != nil) {
            restrictionEditWarning(editorLayer.selectedNode)
        }
    }

    func dragConnection(for node: OsmNode, segment: inout Int) -> OsmBaseObject? {
		guard let way = editorLayer.selectedWay,
			  let index = way.nodes.firstIndex(of: node)
		else { return nil }

		var ignoreList: [OsmBaseObject] = []
		let parentWays = node.wayCount == 1 ? [way] : editorLayer.mapData.waysContaining(node)
		if way.nodes.count < 3 {
			ignoreList = parentWays + way.nodes
        } else if index == 0 {
            // if end-node then okay to connect to self-nodes except for adjacent
			let nodes = [way.nodes[0],
						 way.nodes[1],
						 way.nodes[2]]
			ignoreList = parentWays + nodes
		} else if index == way.nodes.count - 1 {
			// if end-node then okay to connect to self-nodes except for adjacent
			let nodes = [way.nodes[index],
						 way.nodes[index - 1],
						 way.nodes[index - 2]]
			ignoreList = parentWays + nodes
        } else {
			// if middle node then never connect to self
            if !parentWays.isEmpty {
				ignoreList = parentWays + way.nodes
            }
        }
		let hit = editorLayer.osmHitTest(
			pushpinView?.arrowPoint ?? CGPoint.zero,
			radius: DragConnectHitTestRadius,
            isDragConnect: true,
            ignoreList: ignoreList,
            segment: &segment
        )
        return hit
    }

    func removePin() {
        if let pushpinView = pushpinView {
            pushpinView.removeFromSuperview()
        }
		self.pushpinView = nil
		updateEditControl()
    }

	private func pushpinDragCallbackFor(object: OsmBaseObject) -> PushPinViewDragCallback {
		return { [self] state, dx, dy, gesture in
			switch state {
				case .began:
					self.editorLayer.mapData.beginUndoGrouping()
					pushpinDragTotalMove = CGPoint(x: 0, y: 0)
					gestureDidMove = false
				case .ended, .cancelled, .failed:
					self.editorLayer.mapData.endUndoGrouping()
					DisplayLink.shared().removeName("dragScroll")

					let isRotate = self.isRotateObjectMode != nil
					if isRotate {
						self.endObjectRotation()
					}
					self.unblinkObject()

					if let way = object.isWay() {
						// update things if we dragged a multipolygon inner member to become outer
						self.editorLayer.mapData.updateParentMultipolygonRelationRoles(for: way)
					} else if let selectedWay = self.editorLayer.selectedWay,
							  object.isNode() != nil
					{
						// you can also move an inner to an outer by dragging nodes one at a time
						self.editorLayer.mapData.updateParentMultipolygonRelationRoles(for: selectedWay)
					}

					if let selectedWay = self.editorLayer.selectedWay,
					   let object = object.isNode()
					{
						// dragging a node that is part of a way
						if let dragNode = object.isNode() {
							let dragWay = selectedWay
							var segment = -1
							let hit = self.dragConnection(for: dragNode, segment: &segment)
							if var hit = hit as? OsmNode {
								// replace dragged node with hit node
								var error: String? = nil
								let merge: EditActionReturnNode? = editorLayer.mapData.canMerge( dragNode, into:hit, error:&error)
								if merge == nil {
									self.showAlert(error, message: nil)
									return
								}
								hit = merge!()
								if dragWay.isArea() {
									self.editorLayer.selectedNode = nil
									let pt = self.screenPoint(forLatitude: hit.lat, longitude: hit.lon, birdsEye: true)
									self.placePushpin(at: pt, object: dragWay)
								} else {
									self.editorLayer.selectedNode = hit
									self.placePushpinForSelection()
								}
							} else if let hit = hit as? OsmWay {
								// add new node to hit way
								let pt = hit.pointOnObjectForPoint(dragNode.location())
								self.editorLayer.mapData.setLongitude(pt.x, latitude: pt.y, for: dragNode)
								var error: String? = nil
								let add: EditActionWithNode? = editorLayer.canAddNode(toWay: hit, atIndex:segment+1, error:&error)
								if let add = add {
									add(dragNode)
								} else {
									self.showAlert(NSLocalizedString("Error connecting to way", comment: ""), message: error)
								}
							}
						}
						return
					}
					if isRotate {
						break
					}
					if self.editorLayer.selectedWay != nil && editorLayer.selectedWay?.tags.count ?? 0 == 0 && editorLayer.selectedWay?.parentRelations.count ?? 0 == 0 {
						break
					}
					if self.editorLayer.selectedWay != nil && self.editorLayer.selectedNode != nil {
						break
					}
					if self.confirmDrag {
						self.confirmDrag = false

						let alertMove = UIAlertController(title: NSLocalizedString("Confirm move", comment: ""), message: NSLocalizedString("Move selected object?", comment: ""), preferredStyle: .alert)
						alertMove.addAction(UIAlertAction(title: NSLocalizedString("Undo", comment: ""), style: .cancel, handler: { action in
							// cancel move
							self.editorLayer.mapData.undo()
							self.editorLayer.mapData.removeMostRecentRedo()
							self.editorLayer.selectedNode = nil
							self.editorLayer.selectedWay = nil
							self.editorLayer.selectedRelation = nil
							self.removePin()
							self.editorLayer.setNeedsLayout()
						}))
						alertMove.addAction(UIAlertAction(title: NSLocalizedString("Move", comment: ""), style: .default, handler: { action in
							// okay
						}))
						self.mainViewController.present(alertMove, animated: true)
					}
				case .changed:
					// define the drag function
					let dragObject: ((_ dragx: CGFloat, _ dragy: CGFloat) -> Void) = { dragx, dragy in
						// don't accumulate undo moves
						self.pushpinDragTotalMove.x += dragx
						self.pushpinDragTotalMove.y += dragy
						if self.gestureDidMove {
							self.editorLayer.mapData.endUndoGrouping()
							self.silentUndo = true
							let dict = self.editorLayer.mapData.undo()
							self.silentUndo = false
							self.editorLayer.mapData.beginUndoGrouping()
							if let dict = dict as? [String : String] {
								// maintain the original pin location:
								self.editorLayer.mapData.registerUndoCommentContext(dict)
							}
						}
						self.gestureDidMove = true

						// move all dragged nodes
						if let rotate = self.isRotateObjectMode {
							// rotate object
							let delta = Double(-((self.pushpinDragTotalMove.x) + (self.pushpinDragTotalMove.y)) / 100)
							let axis = self.screenPoint(forLatitude: rotate.rotateObjectCenter.y,
														longitude: rotate.rotateObjectCenter.x,
														birdsEye: true)
							let nodeSet = (object.isNode() != nil) ? self.editorLayer.selectedWay?.nodeSet() : object.nodeSet()
							for node in nodeSet ?? [] {
								let pt = self.screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: true)
								let diff = OSMPoint(x: Double(pt.x - axis.x), y: Double(pt.y - axis.y))
								let radius = hypot(diff.x, diff.y)
								var angle = atan2(diff.y, diff.x)
								angle += delta
								let new = OSMPoint(x: Double(axis.x) + radius * Double(cos(angle)),y: Double(axis.y) + Double(radius * sin(angle)))
								let dist = CGPoint(x: Double(new.x - Double(pt.x)), y: Double(-(Double(new.y) - Double(pt.y))))
								self.editorLayer.adjust(node, byDistance: dist)
							}
						} else {
							// drag object
							let delta = CGPoint(x: Double(self.pushpinDragTotalMove.x), y: Double(-(self.pushpinDragTotalMove.y)))

							for node in object.nodeSet() {
								self.editorLayer.adjust(node, byDistance: delta)
							}
						}

						// do hit testing for connecting to other objects
						if (self.editorLayer.selectedWay != nil) && (object.isNode() != nil) {
							var segment = -1
							if let hit = self.dragConnection(for: object as! OsmNode, segment: &segment),
							   hit.isWay() != nil || hit.isNode() != nil
							{
								self.blink(hit, segment: segment)
							} else {
								self.unblinkObject()
							}
						}
					}

					// scroll screen if too close to edge
					let MinDistanceSide: CGFloat = 40.0
					let MinDistanceTop = MinDistanceSide + 10.0
					let MinDistanceBottom = MinDistanceSide + 120.0
					let arrow = self.pushpinView?.arrowPoint ?? .zero
					let screen = self.bounds
					let SCROLL_SPEED: CGFloat = 10.0
					var scrollx: CGFloat = 0
					var scrolly: CGFloat = 0

					if (arrow.x) < (screen.origin.x + MinDistanceSide) {
						scrollx = -SCROLL_SPEED
					} else if (arrow.x) > (screen.origin.x) + (screen.size.width) - MinDistanceSide {
						scrollx = SCROLL_SPEED
					}
					if (arrow.y) < screen.origin.y + MinDistanceTop {
						scrolly = -SCROLL_SPEED
					} else if arrow.y > screen.origin.y + screen.size.height - MinDistanceBottom {
						scrolly = SCROLL_SPEED
					}

					if scrollx != 0.0 || scrolly != 0.0 {

						// if we're dragging at a diagonal then scroll diagonally as well, in the direction the user is dragging
						let center = CGRectCenter(self.bounds)
						let v = UnitVector(Sub(OSMPoint(arrow), OSMPoint(center)))
						scrollx = SCROLL_SPEED * CGFloat(v.x)
						scrolly = SCROLL_SPEED * CGFloat(v.y)

						// scroll the screen to keep pushpin centered
						let displayLink = DisplayLink.shared()
						var prevTime = TimeInterval(CACurrentMediaTime())
						displayLink.addName("dragScroll", block: { [self] in
							let now = TimeInterval(CACurrentMediaTime())
							let duration = now - prevTime
							prevTime = now
							let sx = scrollx * CGFloat(duration) * 60.0 // scale to 60 FPS assumption, need to move farther if framerate is slow
							let sy = scrolly * CGFloat(duration) * 60.0
							self.adjustOrigin(by: CGPoint(x: -sx, y: -sy))
							dragObject(sx, sy)
							// update position of pushpin
							if let pt = self.pushpinView?.arrowPoint.withOffset(sx, sy) {
								self.pushpinView?.arrowPoint = pt
							}
							// update position of blink layer
							if let pt = blinkLayer?.position.withOffset(-sx, -sy) {
								self.blinkLayer?.position = pt
							}
						})
					} else {
						DisplayLink.shared().removeName("dragScroll")
					}

					// move the object
					dragObject(dx, dy)
				default:
					break
			}
		}
	}

    func placePushpin(at point: CGPoint, object: OsmBaseObject?) {
        // drop in center of screen
        removePin()

        confirmDrag = false
		let pushpinView = PushPinView()
		self.pushpinView = pushpinView
		self.refreshPushpinText()
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
		pushpinView?.text = text
    }

    func createNode(at dropPoint: CGPoint) {
        if editorLayer.isHidden {
            flashMessage(NSLocalizedString("Editing layer not visible", comment: ""))
            return
        }

		// we are either creating a brand new node unconnected to an existing way,
		// converting a dropped pin to a way by adding a new node
		// or adding a node to a selected way/node combination
		guard let pushpinView = pushpinView,
			  editorLayer.selectedNode == nil || editorLayer.selectedWay != nil
		else {
			// drop a new pin
			editorLayer.selectedNode = nil
			editorLayer.selectedWay = nil
			editorLayer.selectedRelation = nil
			placePushpin(at: dropPoint, object: nil)
			return
		}

		let prevPointIsOffScreen = !bounds.contains(pushpinView.arrowPoint)
		let offscreenWarning: (()->Void) = {
			self.flashMessage(NSLocalizedString("Selected object is off screen", comment: ""))
		}

		if let selectedWay = editorLayer.selectedWay,
		   let selectedNode = editorLayer.selectedNode
		{
			// already editing a way so try to extend it
			if selectedWay.isClosed() || !(selectedNode == selectedWay.nodes.first || selectedNode == selectedWay.nodes.last) {
				if prevPointIsOffScreen {
					offscreenWarning()
					return
				}
			}
		} else if editorLayer.selectedPrimary == nil {
			// just dropped a pin, so convert it into a way
		} else if editorLayer.selectedWay != nil && editorLayer.selectedNode == nil {
			// add a new node to a way at location of pushpin
			if prevPointIsOffScreen {
				offscreenWarning()
				return
			}
		} else {
			// not supported
			return
		}
		switch editorLayer.extendSelectedWay(to: dropPoint, from: pushpinView.arrowPoint) {
		case let .success(pt):
			placePushpinForSelection(at: pt)
		case let .failure(error):
			if case .text(let text) = error {
				showAlert(NSLocalizedString("Can't extend way", comment: ""), message: text)
			}
		}
	}

	func setTagsForCurrentObject(_ tags: [String : String]) {
        if let selectedPrimary = editorLayer.selectedPrimary {
			// update current object
			editorLayer.mapData.setTags(tags, for: selectedPrimary)
			refreshPushpinText()
			refreshNoteButtonsFromDatabase()
		} else {
            // create new object
            assert((pushpinView != nil))
            let point = pushpinView?.arrowPoint
            let node = editorLayer.createNode(at: point ?? CGPoint())
            editorLayer.mapData.setTags(tags, for: node)
            editorLayer.selectedNode = node
            // create new pushpin for new object
            placePushpinForSelection()
		}
        editorLayer.setNeedsLayout()
		confirmDrag = false
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
		if object == self.blinkObject && segment == blinkSegment {
			return
        }
		blinkLayer?.removeFromSuperlayer()
		blinkObject = object
		blinkSegment = segment

        // create a layer for the object
        let path = CGMutablePath()
		if let node = object as? OsmNode {
			let center = screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: true)
			var rect = CGRect(x: center.x, y: center.y, width: 0, height: 0)
			rect = rect.insetBy(dx: -10, dy: -10)
			path.addEllipse(in: rect, transform: .identity)
		} else if let way = object as? OsmWay {
			if segment >= 0 {
                assert(way.nodes.count >= segment + 2)
                let n1 = way.nodes[segment]
                let n2 = way.nodes[segment + 1]
                let p1 = screenPoint(forLatitude: n1.lat, longitude: n1.lon, birdsEye: true)
                let p2 = screenPoint(forLatitude: n2.lat, longitude: n2.lon, birdsEye: true)
                path.move(to: CGPoint(x: p1.x, y: p1.y))
                path.addLine(to: CGPoint(x: p2.x, y: p2.y))
            } else {
                var isFirst = true
				for node in way.nodes {
					let pt = screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: true)
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
			let rc = screenLongitudeLatitude()
            notesDatabase.updateRegion(rc, withDelay: delay, fixmeData: editorLayer.mapData) { [self] in
                refreshNoteButtonsFromDatabase()
            }
        } else {
            refreshNoteButtonsFromDatabase()
        }
    }

    func refreshNoteButtonsFromDatabase() {
        DispatchQueue.main.async(execute: { [self] in
            // need this to disable implicit animation

            UIView.performWithoutAnimation({ [self] in
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
                notesDatabase.enumerateNotes({ [self] note in
					if viewOverlayMask.contains( MapViewOverlays.NOTES ) {

                        // hide unwanted keep right buttons
                        if note.isKeepRight && notesDatabase.isIgnored(note) {
							if let button = notesViewDict[ note.tagId ] {
								button.removeFromSuperview()
							}
                            return
                        }

						if notesViewDict[ note.tagId ] == nil {
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
							notesViewDict[ note.tagId ] = button
						}
						let button = notesViewDict[ note.tagId ]!

                        if note.status == "closed" {
                            button.removeFromSuperview()
                        } else if note.isFixme && editorLayer.mapData.object(withExtendedIdentifier: note.noteId)?.tags["fixme"] == nil {
                            button.removeFromSuperview()
                        } else {
                            let offsetX = note.isKeepRight || note.isFixme ? 0.00001 : 0.0
                            let pos = screenPoint(forLatitude: note.lat, longitude: note.lon + offsetX, birdsEye: true)
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
						if let button = notesViewDict[ note.tagId ] {
							button.removeFromSuperview()
							notesViewDict.removeValue(forKey: note.tagId)
						}
                    }
                })
            })

			if !viewOverlayMask.contains(.NOTES) {
                notesDatabase.reset()
            }
        })
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

					let pt = object.pointOnObjectForPoint(OSMPoint(x: note.lon, y: note.lat))
                    let point = screenPoint(forLatitude: pt.y, longitude: pt.x, birdsEye: true)
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
            alertKeepRight.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: { action in
            }))
            alertKeepRight.addAction(UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .default, handler: { [self] action in
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
		while view != nil && !((view is UIControl) || (view is UIToolbar)) {
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
            let displayLink = DisplayLink.shared()
            displayLink.removeName(DisplayLinkPanning)
        } else if pan.state == .changed {
            // move pan
			if SHOW_3D {
				// multi-finger drag to initiate 3-D view
				if enableBirdsEye && pan.numberOfTouches == 3 {
					let translation = pan.translation(in: self)
					let delta = Double(-(translation.y) / 40 / 180 * .pi)
					rotateBirdsEye(by: CGFloat(delta))
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
                let displayLink = DisplayLink.shared()
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

            let displayLink = DisplayLink.shared()
            displayLink.removeName(DisplayLinkPanning)

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

            let displayLink = DisplayLink.shared()
            displayLink.removeName(DisplayLinkPanning)

            let delta = tapAndDrag.translation(in: self)
            //        CGPoint delta = [tapAndDrag translationInView:self];
			let scale = 1.0 + delta.y * 0.01
			let zoomCenter = CGRectCenter(bounds)
            adjustZoom(by: scale, aroundScreenPoint: zoomCenter)
        } else if tapAndDrag.state == .ended {
            updateNotesFromServer(withDelay: 0)
        }
    }

	/// Invoked to select an object on the screen
    @IBAction func screenTapGesture(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended {
            let point = tap.location(in: self)
            if plusButtonTimestamp != 0.0 {
				// user is doing a long-press on + button
				createNode(at: point)
            } else {
				selectObjectAtPoint(point)
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
                        createNode(at: crossHairs.position)
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
        if longPress.state == .began && !editorLayer.isHidden {
            let point = longPress.location(in: self)

			let objects = editorLayer.osmHitTestMultiple(point, radius: DefaultHitTestRadius)
			if objects.count == 0 {
                return
            }

            // special case for adding members to relations:
            if editorLayer.selectedPrimary?.isRelation()?.isMultipolygon() ?? false {
				let ways = objects.compactMap({ $0 as? OsmWay })
				if ways.count == 1 {
                    let confirm = UIAlertController(title: NSLocalizedString("Add way to multipolygon?", comment: ""), message: nil, preferredStyle: .alert)
                    let addMmember: ((String?) -> Void) = { [self] role in
                        var error: String? = nil
						let add: EditAction? = editorLayer.mapData.canAdd( ways[0], to:editorLayer.selectedRelation!, withRole:role, error:&error)
						if let add = add {
                            add()
                            flashMessage(NSLocalizedString("added to multipolygon relation", comment: ""))
                            editorLayer.setNeedsLayout()
                        } else {
                            showAlert(NSLocalizedString("Error", comment: ""), message: error)
                        }
                    }
                    confirm.addAction(UIAlertAction(title: NSLocalizedString("Add outer member", comment: "Add to relation"), style: .default, handler: { action in
                        addMmember("outer")
                    }))
                    confirm.addAction(UIAlertAction(title: NSLocalizedString("Add inner member", comment: "Add to relation"), style: .default, handler: { action in
                        addMmember("inner")
                    }))
                    confirm.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
                    mainViewController.present(confirm, animated: true)
                }
                return
            }

            let multiSelectSheet = UIAlertController(title: NSLocalizedString("Select Object", comment: ""), message: nil, preferredStyle: .actionSheet)
            for object in objects {
				var title = object.friendlyDescription()
                if !title.hasPrefix("(") {
                    // indicate what type of object it is
                    if (object.isNode() != nil) {
                        title = title + NSLocalizedString(" (node)", comment: "")
                    } else if (object.isWay() != nil) {
                        title = title + NSLocalizedString(" (way)", comment: "")
                    } else if (object.isRelation() != nil) {
                        let type = object.tags["type"] ?? NSLocalizedString("relation", comment: "")
                        title = title + " (\(type))"
                    }
                }
                multiSelectSheet.addAction(UIAlertAction(title: title, style: .default, handler: { [self] action in
                    // processing for selecting one of multipe objects
                    editorLayer.selectedNode = nil
                    editorLayer.selectedWay = nil
                    editorLayer.selectedRelation = nil
                    if let node = object.isNode() {
						// select the way containing the node, then select the node in the way
						editorLayer.selectedWay  = objects.first(where: { ($0 as? OsmWay)?.nodes.contains(node) ?? false}) as? OsmWay
						editorLayer.selectedNode = node
					} else if object.isWay() != nil {
						editorLayer.selectedWay = object.isWay()
					} else if object.isRelation() != nil {
						editorLayer.selectedRelation = object.isRelation()
					}
					let pos = self.point(on: object, for: point)
					placePushpin(at: pos, object: object)
                }))
            }
            multiSelectSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            mainViewController.present(multiSelectSheet, animated: true)
            // set position
			let rc = CGRect(x: point.x, y: point.y, width: 0.0, height: 0.0)
			multiSelectSheet.popoverPresentationController?.sourceView = self
            multiSelectSheet.popoverPresentationController?.sourceRect = rc
        }
    }

    @IBAction func handleRotationGesture(_ rotationGesture: UIRotationGestureRecognizer) {
		if let rotate = self.isRotateObjectMode {
			// Rotate object on screen
            if rotationGesture.state == .began {
                editorLayer.mapData.beginUndoGrouping()
                gestureDidMove = false
            } else if rotationGesture.state == .changed {
                if gestureDidMove {
                    // don't allows undo list to accumulate
                    editorLayer.mapData.endUndoGrouping()
                    silentUndo = true
                    editorLayer.mapData.undo()
                    silentUndo = false
                    editorLayer.mapData.beginUndoGrouping()
                }
                gestureDidMove = true

                let delta = rotationGesture.rotation
				let axis = screenPoint(forLatitude: rotate.rotateObjectCenter.y, longitude: rotate.rotateObjectCenter.x, birdsEye: true)
				let rotatedObject = editorLayer.selectedRelation ?? editorLayer.selectedWay
                if let nodeSet = rotatedObject?.nodeSet() {
                    for node in nodeSet {
                        let pt = screenPoint(forLatitude: node.lat, longitude: node.lon, birdsEye: true)
                        let diff = OSMPoint(x: Double(CGFloat(pt.x - axis.x)), y: Double(CGFloat(pt.y - axis.y)))
                        let radius = hypot(diff.x, diff.y)
                        var angle = atan2(diff.y, diff.x)

                        angle += Double(delta)
                        let new = OSMPoint(x: Double(axis.x) + radius * cos(angle), y: Double(axis.y) + radius * sin(angle))
                        let dist = CGPoint(x: CGFloat(new.x) - pt.x, y: -(CGFloat(new.y) - pt.y))
                        editorLayer.adjust(node, byDistance: dist)
                    }
                }
            } else {
                // ended
                endObjectRotation()
                editorLayer.mapData.endUndoGrouping()
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

    func updateSpeechBalloonPosition() {
    }

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

    func selectObjectAtPoint(_ point: CGPoint) {

        // disable rotation if in action
        if isRotateObjectMode != nil {
			endObjectRotation()
        }

        unblinkObject() // used by Mac Catalyst, harmless otherwise

        if editorLayer.selectedWay != nil,
			// check for selecting node inside previously selected way
			let hit = editorLayer.osmHitTestNode(inSelectedWay: point, radius: DefaultHitTestRadius)
		{
			editorLayer.selectedNode = hit

		} else {

            // hit test anything
			var segment = -1
			if let hit = editorLayer.osmHitTest(point, radius: DefaultHitTestRadius, isDragConnect: false, ignoreList: [], segment: &segment) {
                if let hit = hit as? OsmNode {
                    editorLayer.selectedNode = hit
                    editorLayer.selectedWay = nil
                    editorLayer.selectedRelation = nil
                } else if let hit = hit as? OsmWay {
					if let selectedRelation = editorLayer.selectedRelation,
						hit.parentRelations.contains(selectedRelation)
					{
						// selecting way inside previously selected relation
						editorLayer.selectedNode = nil
						editorLayer.selectedWay = hit
					} else if hit.parentRelations.count > 0 {
						// select relation the way belongs to
						var relations = hit.parentRelations.filter { relation in
							return relation.isMultipolygon() || relation.isBoundary() || relation.isWaterway()
						}
						if relations.count == 0 && !hit.hasInterestingTags() {
							relations = hit.parentRelations // if the way doesn't have tags then always promote to containing relation
						}
						if let relation = relations.first {
							editorLayer.selectedNode = nil
							editorLayer.selectedWay = nil
							editorLayer.selectedRelation = relation
						} else {
							editorLayer.selectedNode = nil
							editorLayer.selectedWay = hit
							editorLayer.selectedRelation = nil
						}
					} else {
						editorLayer.selectedNode = nil
						editorLayer.selectedWay = hit
						editorLayer.selectedRelation = nil
					}
                } else if let hit = hit as? OsmRelation {
                    editorLayer.selectedNode = nil
                    editorLayer.selectedWay = nil
                    editorLayer.selectedRelation = hit
				} else {
					fatalError()
				}
			} else {
                editorLayer.selectedNode = nil
                editorLayer.selectedWay = nil
                editorLayer.selectedRelation = nil
            }
        }

        removePin()

        if let selectedPrimary = editorLayer.selectedPrimary {
            // adjust tap point to touch object
            let latLon = longitudeLatitude(forScreenPoint: point, birdsEye: true)
            var pt = OSMPoint(x: latLon.longitude, y: Double(latLon.latitude))
			pt = selectedPrimary.pointOnObjectForPoint(pt)
			let point = screenPoint(forLatitude: pt.y, longitude: pt.x, birdsEye: true)

			placePushpin(at: point, object: selectedPrimary)

            if selectedPrimary is OsmWay || selectedPrimary is OsmRelation {
				// if they later try to drag this way ask them if they really wanted to
                confirmDrag = selectedPrimary.modifyCount == 0
            }
        }
    }

    func rightClick(atLocation location: CGPoint) {
        // right-click is equivalent to holding + and clicking
        createNode(at: location)
    }
}
