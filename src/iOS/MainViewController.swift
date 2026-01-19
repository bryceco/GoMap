//
//  MainViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import SafariServices
import UIKit

enum MainViewButtonLayout: Int {
	case buttonsOnLeft
	case buttonsOnRight
}

protocol MapViewProgress {
	func progressIncrement(_ delta: Int)
	func progressDecrement()
}

protocol MainViewSharedState: AnyObject {
	var mapView: MapView! { get }
	var gpsState: GPS_STATE { get set }
	var viewPort: MapViewPortObject { get }
	var topViewController: UIViewController { get }
	var fpsLabel: FpsLabel! { get }
	var settings: MainViewController.DisplaySettings { get }

	func toggleLocationButton()
	func applicationWillEnterBackground()
	func askToRate(uploadCount: Int)
	func save()
	func moveToLocation(_ location: MapLocation)
}

final class MainViewController: UIViewController, MainViewSharedState, DPadDelegate,
	UIActionSheetDelegate, UIGestureRecognizerDelegate,
	UIContextMenuInteractionDelegate, UIPointerInteractionDelegate,
	UIAdaptivePresentationControllerDelegate
{
	class DisplaySettings {
		@Notify var enableRotation: Bool = UserPrefs.shared.mapViewEnableRotation.value ?? true {
			didSet {
				UserPrefs.shared.mapViewEnableRotation.value = enableRotation
			}
		}

		@Notify var enableBirdsEye = UserPrefs.shared.mapViewEnableBirdsEye.value ?? false {
			didSet {
				UserPrefs.shared.mapViewEnableBirdsEye.value = enableBirdsEye
			}
		}

		var enableAutomaticCacheManagement: Bool = UserPrefs.shared.automaticCacheManagement.value ?? true {
			didSet {
				UserPrefs.shared.automaticCacheManagement.value = enableAutomaticCacheManagement
			}
		}

		@Notify var displayGpxTracks: Bool = UserPrefs.shared.mapViewEnableBreadCrumb.value ?? false {
			didSet {
				UserPrefs.shared.mapViewEnableBreadCrumb.value = displayGpxTracks
			}
		}

		@Notify var buttonLayout = MainViewButtonLayout(rawValue: UserPrefs.shared.mapViewButtonLayout.value ?? -1) ??
			.buttonsOnRight
		{
			didSet {
				UserPrefs.shared.mapViewButtonLayout.value = buttonLayout.rawValue
			}
		}

		@Notify var enableTurnRestriction = UserPrefs.shared.mapViewEnableTurnRestriction.value ?? false {
			didSet {
				UserPrefs.shared.mapViewEnableTurnRestriction.value = enableTurnRestriction
			}
		}
	}

	@IBOutlet var settingsButton: UIButton!
	@IBOutlet var displayButton: UIButton!
	@IBOutlet var uploadButton: UIButton!
	@IBOutlet var undoButton: UIButton!
	@IBOutlet var redoButton: UIButton!
	@IBOutlet var undoRedoView: UIVisualEffectView!
	@IBOutlet var searchButton: UIButton!
	@IBOutlet var compassButton: CompassButton!
	@IBOutlet var aerialServiceLogo: UIButton!
	@IBOutlet var helpButton: UIButton!
	@IBOutlet var centerOnGPSButton: UIButton!
	@IBOutlet var addNodeButton: UIButton!
	@IBOutlet var rulerView: RulerView!
	@IBOutlet var aerialAlignmentButton: UIButton!
	@IBOutlet var dPadView: DPadView!
	@IBOutlet var progressIndicator: UIActivityIndicatorView!
	@IBOutlet var fpsLabel: FpsLabel!
	@IBOutlet var userInstructionLabel: UILabel!
	@IBOutlet var locationButton: UIButton!
	@IBOutlet var flashLabel: UILabel!

	@IBOutlet var mapView: MapView!
	let locationBallView = LocationBallView()

	let settings = DisplaySettings()

	override var shouldAutorotate: Bool { true }
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

	let viewPort = MapViewPortObject()

	var topViewController: UIViewController { self }

	var addNodeButtonLongPressGestureRecognizer: UILongPressGestureRecognizer?
	var plusButtonTimestamp: TimeInterval = 0.0

	// Set true when the user moved the screen manually, so GPS updates shouldn't recenter screen on user
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

	// MARK: Initialization

	override func viewDidLoad() {
		super.viewDidLoad()

		// set up delegates
		AppDelegate.shared.mainView = self

		// configure views in MapView
		mapView.setUpChildViews(with: self)

		navigationController?.isNavigationBarHidden = true

		rulerView.mapView = mapView
		//    _rulerView.layer.zPosition = Z_RULER;

		// undo/redo buttons
		updateUndoRedoButtonState()
		updateUploadButtonState()

		mapView.editorLayer.mapData.addChangeCallback({ [weak self] in
			self?.updateUndoRedoButtonState()
			self?.updateUploadButtonState()
		})

		AppDelegate.shared.mainView.settings.$enableBirdsEye.subscribe(self) { [weak self] enableBirdsEye in
			if !enableBirdsEye,
			   let viewPort = self?.viewPort
			{
				// remove birdsEye
				viewPort.rotateBirdsEye(by: -viewPort.mapTransform.birdsEyeRotation)
			}
		}

		LocationProvider.shared.onChangeLocation.subscribe(self) { [weak self] location in
			self?.locationUpdated(to: location)
		}

		setupAccessibility()

		// long press for quick access to aerial imagery
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(displayButtonLongPressGesture(_:)))
		displayButton.addGestureRecognizer(longPress)

		// long-press on + for adding nodes via taps
		addNodeButtonLongPressGestureRecognizer = UILongPressGestureRecognizer(
			target: self,
			action: #selector(plusButtonLongPressHandler(_:)))
		addNodeButtonLongPressGestureRecognizer?.minimumPressDuration = 0.001
		addNodeButtonLongPressGestureRecognizer?.delegate = self
		addNodeButton.addGestureRecognizer(addNodeButtonLongPressGestureRecognizer!)

		// center button
		centerOnGPSButton.isHidden = true

		// dPadView
		dPadView.delegate = self
		dPadView.isHidden = true

		// Zoom to Edit message:
		userInstructionLabel.layer.cornerRadius = 5
		userInstructionLabel.layer.masksToBounds = true
		userInstructionLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.3)
		userInstructionLabel.textColor = UIColor.white
		userInstructionLabel.isHidden = true

		// Location ball appearance
		locationBallView.heading = 0.0
		locationBallView.showHeading = true
		locationBallView.isHidden = true
		locationBallView.viewPort = viewPort
		LocationProvider.shared.onChangeLocation.subscribe(self) { [weak self] location in
			self?.locationUpdated(to: location)
			self?.locationBallView.updateLocation(location)
		}
		LocationProvider.shared.onChangeSmoothHeading.subscribe(self) { [weak self] heading, accuracy in
			self?.headingChanged(heading, accuracy: accuracy)
		}
		mapView.addSubview(locationBallView)

		// Compass button
		compassButton.viewPort = viewPort

		// customize buttons
		setButtonAppearances()

		// update button layout constraints
		updateButtonPositionsFor(layout: settings.buttonLayout)
		settings.$buttonLayout.subscribe(self) { [weak self] buttonLayout in
			self?.updateButtonPositionsFor(layout: buttonLayout)
		}

		progressIndicator.color = UIColor.green

		// tell our error display manager where to display messages
		MessageDisplay.shared.topViewController = self
		MessageDisplay.shared.flashLabel = flashLabel

		updateAerialAttributionButton()

		// Install gesture recognizers

		let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
		tap.delegate = self
		view.addGestureRecognizer(tap)

		let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
		pan.delegate = self
		view.addGestureRecognizer(pan)

		let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
		pinch.delegate = self
		view.addGestureRecognizer(pinch)

		// two-finger rotation
		let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
		view.addGestureRecognizer(rotate)

		// Support zoom via tap and drag
		let tapAndDragGesture = TapAndDragGesture(target: self, action: #selector(handleTapAndDragGesture(_:)))
		tapAndDragGesture.delegate = self
		tapAndDragGesture.delaysTouchesBegan = false
		tapAndDragGesture.delaysTouchesEnded = false
		view.addGestureRecognizer(tapAndDragGesture)

		if #available(iOS 13.4, macCatalyst 13.0, *) {
			// mouseover support for Mac Catalyst and iPad:
			let hover = UIHoverGestureRecognizer(target: self, action: #selector(hover(_:)))
			mapView.addGestureRecognizer(hover)

#if targetEnvironment(macCatalyst)
			// right-click support for Mac Catalyst
			let rightClick = UIContextMenuInteraction(delegate: self)
			view.addInteraction(rightClick)
#else
			// right-click support for iPad:
			let rightClick = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
			rightClick.allowedTouchTypes = [NSNumber(integerLiteral: UITouch.TouchType.indirect.rawValue)]
			rightClick.buttonMaskRequired = .secondary
			view.addGestureRecognizer(rightClick)
#endif

			// pan gesture to recognize mouse-wheel scrolling (zoom) on iPad and Mac Catalyst
			let scrollWheelGesture = UIPanGestureRecognizer(
				target: self,
				action: #selector(handleScrollWheelGesture(_:)))
			scrollWheelGesture.allowedScrollTypesMask = .discrete
			scrollWheelGesture.maximumNumberOfTouches = 0
			view.addGestureRecognizer(scrollWheelGesture)
		}

		// get current location
		if let lat = UserPrefs.shared.view_latitude.value,
		   let lon = UserPrefs.shared.view_longitude.value,
		   let scale = UserPrefs.shared.view_scale.value
		{
			viewPort.setTransformFor(latLon: LatLon(latitude: lat, longitude: lon),
			                         scale: scale,
			                         rotation: 0.0)
		} else {
			let rc = OSMRect(mapView.layer.bounds)
			viewPort.mapTransform.transform = OSMTransform.translation(rc.origin.x + rc.size.width / 2 - 128,
			                                                           rc.origin.y + rc.size.height / 2 - 128)
			// turn on GPS which will move us to current location
			gpsState = .LOCATION
		}

		// Bindings

		settings.$enableRotation.subscribe(self) { [weak self] newValue in
			guard let self else { return }
			if !newValue {
				// remove rotation
				let centerPoint = viewPort.screenCenterPoint()
				let angle = CGFloat(viewPort.mapTransform.rotation())
				viewPort.animateRotation(by: -angle, aroundPoint: centerPoint)
			}
		}
	}

	func setupAccessibility() {
		locationButton.accessibilityIdentifier = "location_button"
		undoButton.accessibilityLabel = NSLocalizedString("Undo", comment: "")
		redoButton.accessibilityLabel = NSLocalizedString("Redo", comment: "")
		settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "")
		uploadButton.accessibilityLabel = NSLocalizedString("Upload your changes", comment: "")
		displayButton.accessibilityLabel = NSLocalizedString("Display options", comment: "")
	}

	func applicationWillEnterBackground() {
		mapView.voiceAnnouncement?.removeAll()
		save()
	}

	func save() {
		// save preferences first
		let latLon = viewPort.screenCenterLatLon()
		let scale = viewPort.mapTransform.scale()
#if false && DEBUG
		assert(scale > 1.0)
#endif
		UserPrefs.shared.view_scale.value = scale
		UserPrefs.shared.view_latitude.value = latLon.lat
		UserPrefs.shared.view_longitude.value = latLon.lon

		UserPrefs.shared.mapViewState.value = mapView.viewState.rawValue
		UserPrefs.shared.mapViewOverlays.value = mapView.viewOverlayMask.rawValue

		UserPrefs.shared.mapViewEnableDataOverlay.value = mapView.mapLayersView.displayDataOverlayLayers

		mapView.currentRegion.saveToUserPrefs()

		UserPrefs.shared.synchronize()

		AppState.shared.save()

		// then save data
		mapView.editorLayer.save()
	}

	// MARK: Button state

	func updateUndoRedoButtonState() {
		guard undoButton != nil else { return } // during init it can be null
		undoButton.isEnabled = mapView.editorLayer.mapData.canUndo()
		redoButton.isEnabled = mapView.editorLayer.mapData.canRedo()
		undoRedoView.isHidden = mapView.editorLayer.isHidden || (!undoButton.isEnabled && !redoButton.isEnabled)
	}

	func updateUploadButtonState() {
		let yellowCount = 25
		let redCount = 50
		let changeCount = mapView.editorLayer.mapData.modificationCount()
		var color: UIColor?
		if changeCount < yellowCount {
			color = nil // default color
		} else if changeCount < redCount {
			color = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0) // yellow
		} else {
			color = UIColor.red // red
		}
		uploadButton.tintColor = color
		uploadButton.isEnabled = changeCount > 0
		uploadButton.isHidden = changeCount == 0
	}

	func updateGpsButtonState() {
		// update GPS icon
		let isActive = gpsState != GPS_STATE.NONE
		let imageName = isActive ? "location.fill" : "location"
		var image = UIImage(systemName: imageName)
		let color = UIColor.systemBlue
		if #available(iOS 26.0, *) {
			locationButton.setImage(image, for: .normal)
			locationButton.tintColor = color
			locationButton.configuration?.image = image
			locationButton.configuration?.baseForegroundColor = color
		} else {
			image = image?.withRenderingMode(.alwaysTemplate)
			locationButton.setImage(image, for: .normal)
		}
	}

	func updateButtonPositionsFor(layout: MainViewButtonLayout) {
		UserPrefs.shared.mapViewButtonLayout.value = layout.rawValue

		guard
			let superview = addNodeButton.superview,
			let c = superview.constraints.first(where: {
				if ($0.firstItem as? UIView) == addNodeButton,
				   ($0.secondItem is UILayoutGuide) || ($0.secondItem is UIView),
				   $0.firstAttribute == .leading || $0.firstAttribute == .trailing,
				   $0.secondAttribute == .leading || $0.secondAttribute == .trailing
				{
					return true
				}
				return false
			})
		else { return }

		superview.removeConstraint(c)
		let isLeft = layout == .buttonsOnLeft
		let attribute: NSLayoutConstraint.Attribute = isLeft ? .leading : .trailing
		let c2 = NSLayoutConstraint(
			item: c.firstItem as Any,
			attribute: attribute,
			relatedBy: .equal,
			toItem: c.secondItem,
			attribute: attribute,
			multiplier: 1.0,
			constant: isLeft ? abs(c.constant) : -abs(c.constant))
		superview.addConstraint(c2)
	}

	// MARK: Notifications

	func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
		// We were just displayed so update map
	}

	@available(iOS 13.0, *)
	func contextMenuInteraction(
		_ interaction: UIContextMenuInteraction,
		configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration?
	{
		let location = interaction.location(in: mapView)
		rightClick(at: location)
		return nil
	}

	@objc func handleRightClick(_ recognizer: UIGestureRecognizer) {
		let location = recognizer.location(in: mapView)
		rightClick(at: location)
	}

	func rightClick(at location: CGPoint) {
		// right-click is equivalent to holding + and clicking
		mapView.editorLayer.addNode(at: location)
	}

	@objc func hover(_ recognizer: UIGestureRecognizer) {
		let loc = recognizer.location(in: mapView)
		var segment = 0
		var hit: OsmBaseObject?
		if recognizer.state == .changed,
		   !mapView.editorLayer.isHidden,
		   mapView.hitTest(loc, with: nil) == mapView
		{
			if mapView.editorLayer.selectedWay != nil {
				hit = mapView.editorLayer.osmHitTestNode(inSelectedWay: loc,
				                                         radius: EditorMapLayer.DefaultHitTestRadius)
			}
			if hit == nil {
				hit = mapView.editorLayer.osmHitTest(
					loc,
					radius: EditorMapLayer.DefaultHitTestRadius,
					isDragConnect: false,
					ignoreList: [],
					segment: &segment)
			}
			if let chit = hit,
			   chit == mapView.editorLayer.selectedNode || chit == mapView.editorLayer.selectedWay || chit
			   .isRelation() != nil
			{
				hit = nil
			}
		}
		mapView.blink(hit, segment: -1)
	}

#if targetEnvironment(macCatalyst)
	func keypressAction(key: UIKey) {
		let size = view.bounds.size
		let delta = CGPoint(x: size.width * 0.15, y: size.height * 0.15)
		switch key.keyCode {
		case .keyboardRightArrow: viewPort.adjustOrigin(by: CGPoint(x: -delta.x, y: 0))
		case .keyboardLeftArrow: viewPort.adjustOrigin(by: CGPoint(x: delta.x, y: 0))
		case .keyboardDownArrow: viewPort.adjustOrigin(by: CGPoint(x: 0, y: -delta.y))
		case .keyboardUpArrow: viewPort.adjustOrigin(by: CGPoint(x: 0, y: delta.y))
		default: break
		}
	}

	var keypressTimers: [UIKey: Timer] = [:]
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		if #available(macCatalyst 13.4, *) {
			for press in presses {
				if let key = press.key {
					keypressAction(key: key)
					if keypressTimers[key] == nil {
						let timer = Timer(
							fire: Date(timeInterval: 0.5, since: Date()),
							interval: 0.25,
							repeats: true,
							block: { _ in
								self.keypressAction(key: key)
							})
						RunLoop.current.add(timer, forMode: .default)
						keypressTimers[key] = timer
					}
				}
			}
		}
	}

	override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		for press in presses {
			if let key = press.key {
				if let timer = keypressTimers[key] {
					timer.invalidate()
					keypressTimers.removeValue(forKey: key)
				}
			}
		}
	}
#endif

	// MARK: Button configuration

	func setButtonAppearances() {
		// Update button styling
		// This is called every time fonts change, screen rotates, etc so
		// it needs to be idempotent.
		let buttons: [UIView] = [
			// these aren't actually buttons, but they get similar tinting and shadows
			undoRedoView,
			// these are buttons
			undoButton,
			redoButton,
			locationButton,
			addNodeButton,
			compassButton,
			centerOnGPSButton,
			helpButton,
			aerialAlignmentButton,
			settingsButton,
			uploadButton,
			displayButton,
			searchButton
		]

		for view in buttons {
			if #available(iOS 26.0, macOS 26.0,*) {
				// use glass styles in iOS 26
				var config: UIButton.Configuration = view == locationButton ? .prominentGlass() : .glass()
				config.cornerStyle = .capsule

				view.overrideUserInterfaceStyle = .dark

				switch view {
				case let effect as UIVisualEffectView:
					// frame for undo/redo buttons
					let glassEffect = UIGlassEffect(style: .regular)
					glassEffect.isInteractive = true
					effect.effect = glassEffect
					effect.cornerConfiguration = .capsule()
					effect.contentView.clipsToBounds = false
				case let button as UIButton:
					button.backgroundColor = nil
					switch button {
					case undoButton, redoButton:
						// make these transparent
						let oldConfig = config
						config = UIButton.Configuration.plain()
						config.baseBackgroundColor = .clear
						config.cornerStyle = oldConfig.cornerStyle
						config.contentInsets = oldConfig.contentInsets
					case aerialAlignmentButton, helpButton:
						// These button have tighter spacing to deemphasize them
						config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
					case addNodeButton:
						config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
					case locationButton:
						config.baseForegroundColor = .systemBlue
					default:
						break
					}
					// Some buttons reassign config so make changes after switch statement
					config.baseBackgroundColor = .clear
					config.image = button.currentImage
					config.title = button.titleLabel?.text
					button.configuration = config

#if targetEnvironment(macCatalyst)
					// adjust look of buttons on MacCatalyst
					button.preferredBehavioralStyle = .pad
#endif

					// Adjust sizes of buttons to make them a little larger
					if button != helpButton,
					   button != aerialAlignmentButton,
					   button != addNodeButton
					{
						button.constraints.first(where: { $0.firstAttribute == .width })?.constant = 47
						button.constraints.first(where: { $0.firstAttribute == .height })?.constant = 47
					}
				default:
					break
				}
				continue
			}

			// Below here is for non-glass, prior to iOS 26

			// corners
			if view == compassButton || view == mapView.editToolbar {
				// these buttons take care of themselves
			} else if view == helpButton || view == addNodeButton {
				// The button is a circle.
				let width = view.bounds.size.width
				view.layer.cornerRadius = width / 2
			} else {
				// rounded corners
				view.layer.cornerRadius = 10.0
				view.clipsToBounds = true
			}
			// image blue tint
			if let button = view as? UIButton,
			   button != compassButton,
			   button != helpButton,
			   button != aerialAlignmentButton
			{
				let image = button.currentImage?.withRenderingMode(.alwaysTemplate)
				button.setImage(image, for: .normal)
				if #available(iOS 13.0, *) {
					button.tintColor = UIColor.link
				} else {
					button.tintColor = UIColor.systemBlue
				}
				button.setImage(image?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 24)), for: .normal)
			}

			// normal background color
			makeButtonNormal(view)

			// background selection color
			if let button = view as? UIButton {
				button.addTarget(self, action: #selector(makeButtonHighlight(_:)), for: .touchDown)
				button.addTarget(self, action: #selector(makeButtonNormal(_:)), for: .touchUpInside)
				button.addTarget(self, action: #selector(makeButtonNormal(_:)), for: .touchUpOutside)
				button.addTarget(self, action: #selector(makeButtonNormal(_:)), for: .touchCancel)

				// pointer interaction when using a mouse
				if #available(iOS 13.4, *) {
					if !button.interactions.contains(where: { $0.isKind(of: UIPointerInteraction.self) }) {
						let interaction = UIPointerInteraction(delegate: self)
						button.interactions.append(interaction)
					}
				}
			}
		}

		// special handling for aerial logo button
		if #available(iOS 13.4, *) {
			if !aerialServiceLogo.interactions.contains(where: { $0.isKind(of: UIPointerInteraction.self) }) {
				let interaction = UIPointerInteraction(delegate: self)
				aerialServiceLogo.interactions.append(interaction)
			}
		}
	}

	/// Change the button/cursor shape when hovering over a button with a mouse on iPad
	@available(iOS 13.4, *)
	func pointerInteraction(_ interaction: UIPointerInteraction, styleFor: UIPointerRegion) -> UIPointerStyle? {
		if let interactionView = interaction.view {
			let targetedPreview = UITargetedPreview(view: interactionView)
			return UIPointerStyle(effect: UIPointerEffect.automatic(targetedPreview))
		}
		return nil
	}

	@objc func makeButtonHighlight(_ button: UIView) {
#if targetEnvironment(macCatalyst)
// This messes up the button styling on macOS
#else
		if #available(iOS 26.0, *) {
			// don't modify glass
		} else if #available(iOS 13.0, *) {
			button.backgroundColor = UIColor.secondarySystemBackground
		} else {
			button.backgroundColor = UIColor.lightGray
		}
#endif
	}

	@objc func makeButtonNormal(_ button: UIView) {
#if targetEnvironment(macCatalyst)
// This messes up the button styling on macOS
#else
		if #available(iOS 26.0, *) {
			// don't modify glass
		} else if #available(iOS 13.0, *) {
			button.backgroundColor = UIColor.systemBackground
		} else {
			button.backgroundColor = UIColor.white
		}
		if button == aerialAlignmentButton {
			button.backgroundColor = button.backgroundColor?.withAlphaComponent(0.4)
		}
#endif
	}

	// MARK: Keyboard shortcuts

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		switch action {
		case #selector(undo(_:)):
			return !mapView.editorLayer.isHidden && mapView.editorLayer.mapData.canUndo()
		case #selector(redo(_:)):
			return !mapView.editorLayer.isHidden && mapView.editorLayer.mapData.canRedo()
		case #selector(copy(_:)):
			return mapView.editorLayer.selectedPrimary != nil
		case #selector(paste(_:)):
			return mapView.editorLayer.selectedPrimary != nil && mapView.editorLayer.canPasteTags()
		case #selector(delete(_:)):
			return (mapView.editorLayer.selectedPrimary != nil) && (mapView.editorLayer.selectedRelation == nil)
		case #selector(showHelp(_:)):
			return true
		default:
			return false
		}
	}

	@objc func undo(_ sender: Any?) {
		mapView.undo(sender)
	}

	@objc func redo(_ sender: Any?) {
		mapView.redo(sender)
	}

	@objc override func copy(_ sender: Any?) {
		mapView.editorLayer.performEdit(EDIT_ACTION.COPYTAGS)
	}

	@objc override func paste(_ sender: Any?) {
		mapView.editorLayer.performEdit(EDIT_ACTION.PASTETAGS)
	}

	@objc override func delete(_ sender: Any?) {
		mapView.editorLayer.performEdit(EDIT_ACTION.DELETE)
	}

	@objc func showHelp(_ sender: Any?) {
		openHelp()
	}

	// MARK: Progress indicator

	var progressActive = AtomicInt(0)

	// MARK: Gesture recognizers

	// disable gestures inside toolbar buttons
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

	@objc func displayButtonLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
		if recognizer.state == .began {
			displayButtonLongPressHandler()
		}
	}

	@objc func handlePanGesture(_ pan: UIPanGestureRecognizer) {
		userOverrodeLocationPosition = true

		if pan.state == .began {
			// start pan
			DisplayLink.shared.removeName(DisplayLinkPanning)
			// disable frame rate test if active
			fpsLabel.automatedFramerateTestActive = false
		} else if pan.state == .changed {
			// move pan
			if SHOW_3D {
				// multi-finger drag to initiate 3-D view
				if settings.enableBirdsEye, pan.numberOfTouches == 3 {
					let translation = pan.translation(in: self.view)
					let delta = Double(-translation.y / 40 / 180 * .pi)
					viewPort.rotateBirdsEye(by: delta)
					return
				}
			}
			let translation = pan.translation(in: mapView)
			viewPort.adjustOrigin(by: translation)
			pan.setTranslation(CGPoint(x: 0, y: 0), in: self.view)
		} else if pan.state == .ended || pan.state == .cancelled {
			// cancelled occurs when we throw an error dialog
			let duration = 0.5

			// finish pan with inertia
			let initialVelecity = pan.velocity(in: self.view)
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
						self.viewPort.adjustOrigin(by: translation)
					}
				})
			}
		} else if pan.state == .failed {
			DLog("pan gesture failed")
		} else {
			DLog("pan gesture \(pan.state)")
		}
	}

	@objc func handleTapGesture(_ tap: UITapGestureRecognizer) {
		mapView.handleTapGesture(tap)
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
			let zoomCenter = viewPort.screenCenterPoint()
#else
			let zoomCenter = pinch.location(in: mapView)
#endif
			let scale = pinch.scale / prevousPinchScale
			viewPort.adjustZoom(by: scale, aroundScreenPoint: zoomCenter)
			prevousPinchScale = pinch.scale
		case .ended:
			break
		default:
			break
		}
	}

	@objc func handleRotationGesture(_ rotationGesture: UIRotationGestureRecognizer) {
		// Rotate screen
		guard settings.enableRotation else {
			return
		}

		switch rotationGesture.state {
		case .began:
			break // ignore
		case .changed:
#if targetEnvironment(macCatalyst)
			// On Mac we want to rotate around the screen center, not the cursor.
			// This is better determined by testing for indirect touches, but
			// that information isn't exposed by the gesture recognizer.
			let centerPoint = viewPort.screenCenterPoint()
#else
			let centerPoint = rotationGesture.location(in: mapView)
#endif
			let angle = rotationGesture.rotation
			viewPort.rotate(by: angle, aroundScreenPoint: centerPoint)
			rotationGesture.rotation = 0.0

			if gpsState == .HEADING {
				gpsState = .LOCATION
			}
		case .ended:
			mapView.updateMapMarkersFromServer(withDelay: 0, including: [])
		default:
			break // ignore
		}
	}

	@objc func handleTapAndDragGesture(_ tapAndDrag: TapAndDragGesture) {
		mapView.handleTapAndDragGesture(tapAndDrag)
	}

	@objc func handleScrollWheelGesture(_ pan: UIPanGestureRecognizer) {
		if pan.state == .changed {
			let delta = pan.translation(in: mapView)
			var center = pan.location(in: mapView)
			center.y -= delta.y
			let zoom = delta.y >= 0 ? (1000.0 + delta.y) / 1000.0 : 1000.0 / (1000.0 - delta.y)
			viewPort.adjustZoom(by: zoom, aroundScreenPoint: center)
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
					mapView.editorLayer.addNode(at: mapView.crossHairs.position)
				}
			}
			plusButtonTimestamp = 0.0
		case .cancelled, .failed:
			plusButtonTimestamp = 0.0
		default:
			break
		}
	}

	func displayButtonLongPressHandler() {
		// show the most recently used aerial imagery
		let tileServerlList = AppState.shared.tileServerList
		let actionSheet = UIAlertController(
			title: NSLocalizedString("Recent Aerial Imagery", comment: "Alert title message"),
			message: nil,
			preferredStyle: .actionSheet)
		for service in tileServerlList.recentlyUsed() {
			actionSheet.addAction(UIAlertAction(title: service.name, style: .default, handler: { [self] _ in
				tileServerlList.currentServer = service
				mapView.setAerialTileServer(service)
				if mapView.viewState == MapViewState.EDITOR {
					mapView.viewState = MapViewState.EDITORAERIAL
				} else if mapView.viewState == MapViewState.BASEMAP {
					mapView.viewState = MapViewState.EDITORAERIAL
				}
			}))
		}

		// add options for changing display
		let prefix = "🌐 "
		let editorOnly = UIAlertAction(
			title: prefix + NSLocalizedString("Editor only", comment: ""),
			style: .default,
			handler: { [self] _ in
				mapView.viewState = MapViewState.EDITOR
			})
		let aerialOnly = UIAlertAction(
			title: prefix + NSLocalizedString("Aerial only", comment: ""),
			style: .default,
			handler: { [self] _ in
				mapView.viewState = MapViewState.AERIAL
			})
		let editorAerial = UIAlertAction(
			title: prefix + NSLocalizedString("Editor with Aerial", comment: ""),
			style: .default,
			handler: { [self] _ in
				mapView.viewState = MapViewState.EDITORAERIAL
			})

		switch mapView.viewState {
		case .EDITOR:
			actionSheet.addAction(editorAerial)
			actionSheet.addAction(aerialOnly)
		case .EDITORAERIAL:
			actionSheet.addAction(editorOnly)
			actionSheet.addAction(aerialOnly)
		case .AERIAL:
			actionSheet.addAction(editorAerial)
			actionSheet.addAction(editorOnly)
		case .BASEMAP:
			actionSheet.addAction(editorAerial)
			actionSheet.addAction(editorOnly)
			actionSheet.addAction(aerialOnly)
		}

		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
		                                    style: .cancel,
		                                    handler: nil))
		// set location of popup
		actionSheet.popoverPresentationController?.sourceView = displayButton
		actionSheet.popoverPresentationController?.sourceRect = displayButton.bounds

		present(actionSheet, animated: true)
	}

	// MARK: GPS tracking

	var gpsState: GPS_STATE = .NONE {
		didSet {
			if gpsState != oldValue {
				if gpsState == .NONE {
					centerOnGPSButton.isHidden = true
					LocationProvider.shared.stop()
					locationBallView.isHidden = true
					mapView.voiceAnnouncement?.enabled = false
					AppState.shared.gpxTracks.endActiveTrack(continuingCurrentTrack: false)
				} else {
					userOverrodeLocationPosition = false
					userOverrodeLocationZoom = false
					locationBallView.isHidden = false
					LocationProvider.shared.start()
					mapView.voiceAnnouncement?.enabled = true
					if oldValue == .NONE {
						// because recording GPX tracks is cheap we record them any time GPS is enabled
						AppState.shared.gpxTracks.startNewTrack(continuingCurrentTrack: false)
					}
				}
			}
		}
	}

	func headingChanged(_ heading: Double, accuracy: Double) {
		let screenAngle = viewPort.mapTransform.rotation()

		if gpsState == .HEADING {
			// rotate to new heading
			let center = viewPort.screenCenterPoint()
			let delta = -(heading + screenAngle)
			viewPort.rotate(by: CGFloat(delta), aroundScreenPoint: center)
		} else {
			// rotate location ball
			locationBallView.headingAccuracy = CGFloat(accuracy * (.pi / 180))
			locationBallView.showHeading = true
			locationBallView.heading = CGFloat(heading + screenAngle - .pi / 2)
		}
	}

	private func locationUpdated(to newLocation: CLLocation) {
		if let voiceAnnouncement = mapView.voiceAnnouncement,
		   !mapView.editorLayer.isHidden
		{
			voiceAnnouncement.announce(forLocation: LatLon(newLocation.coordinate))
		}

		if AppState.shared.gpxTracks.activeTrack != nil {
			AppState.shared.gpxTracks.addPoint(newLocation)
		}

		if !userOverrodeLocationPosition,
		   UIApplication.shared.applicationState == .active
		{
			// move view to center on new location
			if userOverrodeLocationZoom {
				viewPort.centerOn(latLon: LatLon(newLocation.coordinate),
				                  zoom: nil,
				                  rotation: nil)
			} else {
				viewPort.centerOn(latLon: LatLon(newLocation.coordinate),
				                  metersWide: 20.0)
			}
		}
	}

	func moveToLocation(_ location: MapLocation) {
		let zoom = location.zoom > 0 ? location.zoom : 21.0
		let latLon = LatLon(latitude: location.latitude, longitude: location.longitude)
		let rotation = location.direction * .pi / 180.0
		viewPort.centerOn(latLon: latLon,
		                  zoom: zoom,
		                  rotation: rotation)
		if let state = location.view {
			mapView.viewState = state
		}
	}

	// MARK: Button actions

	@IBAction func toggleLocationButton() {
		switch gpsState {
		case GPS_STATE.NONE:
			// if the user hasn't rotated the screen then start facing north, otherwise follow heading
			if fabs(viewPort.mapTransform.rotation()) < 0.0001 {
				gpsState = .LOCATION
			} else {
				gpsState = .HEADING
			}
		case GPS_STATE.LOCATION, GPS_STATE.HEADING:
			gpsState = .NONE
		}
		updateGpsButtonState()
	}

	@IBAction func compassPressed(_ sender: Any?) {
		switch gpsState {
		case .HEADING:
			gpsState = .LOCATION
			viewPort.rotateToNorth()
		case .LOCATION:
			gpsState = .HEADING
			if let clHeading = LocationProvider.shared.currentHeading {
				let heading = LocationProvider.headingAdjustedForInterfaceOrientation(clHeading)
				viewPort.rotateToHeading(heading)
			}
		case .NONE:
			viewPort.rotateToNorth()
		}
	}

	@IBAction func centerOnGPS(_ sender: Any) {
		if let location = LocationProvider.shared.currentLocation {
			userOverrodeLocationPosition = false
			viewPort.centerOn(latLon: LatLon(location.coordinate),
			                  zoom: nil, // don't change zoom
			                  rotation: nil) // don't change rotation
		}
	}

	@IBAction func openHelp() {
		let urlAsString = "https://wiki.openstreetmap.org/w/index.php?title=Go_Map!!&mobileaction=toggle_view_mobile"
		guard let url = URL(string: urlAsString) else { return }

		let safariViewController = SFSafariViewController(url: url)
		safariViewController.modalPresentationStyle = .pageSheet
		safariViewController.popoverPresentationController?.sourceView = view
		present(safariViewController, animated: true)
	}

	@IBAction func requestAerialServiceAttribution(_ sender: Any) {
		let aerial = mapView.mapLayersView.aerialLayer.tileServer
		if aerial.isBingAerial() {
			// present bing metadata
			performSegue(withIdentifier: "BingMetadataSegue", sender: self)
		} else if aerial.attributionUrl.count > 0 {
			// open the attribution url
			if let url = URL(string: aerial.attributionUrl) {
				let safariViewController = SFSafariViewController(url: url)
				present(safariViewController, animated: true)
			}
		}
	}

	func showInAppStore() {
		let appStoreId = "592990211"
		let urlText = "itms-apps://itunes.apple.com/app/id\(appStoreId)"
		let url = URL(string: urlText)
		if let url = url {
			UIApplication.shared.open(url, options: [:], completionHandler: nil)
		}
	}

	// MARK: Aerial imagery alignment

	@IBAction func aerialAlignmentPressed(_ sender: Any) {
		dPadView.isHidden = !dPadView.isHidden
	}

	func updateAerialAlignmentButton() {
		let offset = mapView.mapLayersView.aerialLayer.imageryOffsetMeters
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
		let newOffset = mapView.mapLayersView.aerialLayer.imageryOffsetMeters.plus(CGPoint(
			x: shift.x * scale,
			y: shift.y * scale))
		mapView.mapLayersView.aerialLayer.imageryOffsetMeters = newOffset
		updateAerialAlignmentButton()
	}

	// MARK: Other stuff

	func updateAerialAttributionButton() {
		let service = mapView.mapLayersView.aerialLayer.tileServer
		let icon = service.attributionIcon(height: aerialServiceLogo.frame.size.height,
		                                   completion: { [weak self] in
		                                   	self?.updateAerialAttributionButton()
		                                   })
		aerialServiceLogo.isHidden = mapView.mapLayersView.aerialLayer.isHidden
			|| (service.attributionString.isEmpty && icon == nil)

		let gap = icon != nil && service.attributionString.count > 0 ? " " : ""
		let title = gap + service.attributionString
		aerialServiceLogo.setImage(icon, for: .normal)
		aerialServiceLogo.setTitle(title, for: .normal)
	}

	func askToRate(uploadCount: Int) {
		// Don't ask if running under TestFlight
		if Bundle.main.appStoreReceiptURL?.path.contains("sandboxReceipt") ?? false {
			return
		}
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
			present(alertViewRateApp, animated: true)
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()

		if var memoryUsed = MemoryUsed(),
		   var memoryTotal = TotalDeviceMemory()
		{
			let bytesPerMB = Double(1024 * 1024)
			memoryUsed /= bytesPerMB
			memoryTotal /= bytesPerMB

			DLog("memory warning: \(memoryUsed) of \(memoryTotal) MB used")
#if !DEBUG
			if memoryUsed / memoryTotal < 0.4 {
				// ignore unless we're being a memory hog
				return
			}
#endif
		}
		MessageDisplay.shared.flashMessage(title: nil,
		                                   message: NSLocalizedString("Low memory: clearing cache", comment: ""))
		mapView.editorLayer.didReceiveMemoryWarning()
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		// This is necessary so we can be notified if the user drags down
		// to dismiss a view that we presented.
		if let nav = segue.destination as? UINavigationController {
			nav.presentationController?.delegate = self
		}

		if sender is OsmNoteMarker {
			let vc: NotesTableViewController
			if let dest = segue.destination as? NotesTableViewController {
				/// The `NotesTableViewController` is presented directly.
				vc = dest
			} else if let navigationController = segue.destination as? UINavigationController,
			          let dest = navigationController.viewControllers.first as? NotesTableViewController
			{
				/// The `NotesTableViewController` is wrapped in an `UINavigationController´.
				vc = dest
			} else {
				return
			}
			vc.note = sender as? OsmNoteMarker
			vc.mapView = mapView
		}
	}
}

extension MainViewController: MapViewProgress {

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
	}
}
