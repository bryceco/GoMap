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

enum GPS_STATE: Int {
	case NONE // none
	case LOCATION // location only
	case HEADING // location and heading
}

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

struct ViewStateAndOverlays {
	let onChange = NotificationService<ViewStateAndOverlays>()

	public var state: MapViewState = UserPrefs.shared.mapViewState.value
		.flatMap(MapViewState.init(rawValue:)) ?? .EDITORAERIAL
	{
		didSet {
			if state != oldValue {
				onChange.notify(self)
				UserPrefs.shared.mapViewState.value = state.rawValue
			}
		}
	}

	public var overlayMask = MapViewOverlays(rawValue: UserPrefs.shared.mapViewOverlays.value ?? 0) {
		didSet {
			if oldValue != overlayMask {
				onChange.notify(self)
				UserPrefs.shared.mapViewOverlays.value = overlayMask.rawValue
			}
		}
	}

	var zoomedOut = true { // initial value is true since viewPort transform initial value is identity
		didSet {
			if oldValue != zoomedOut {
				onChange.notify(self)
			}
		}
	}
}

final class MainViewController: UIViewController, DPadDelegate,
	UIActionSheetDelegate, UIGestureRecognizerDelegate,
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

		@Notify var buttonLayout = MainViewButtonLayout(rawValue: UserPrefs.shared.mapViewButtonLayout.value ?? -1)
			?? .buttonsOnRight
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

		@Notify var tileOverlaySelections = UserPrefs.shared.tileOverlaySelections.value ?? [] {
			didSet {
				UserPrefs.shared.tileOverlaySelections.value = tileOverlaySelections
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
	@IBOutlet private var statusBarBackground: StatusBarGradient!

	@IBOutlet var mapView: MapView!
	let locationBallView = LocationBallView()
	let mapLayersView = MapLayersView()

	let settings = DisplaySettings()

	var viewState = ViewStateAndOverlays()
	override var shouldAutorotate: Bool { true }
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

	var isInitialized = false

	let viewPort = MapViewPortObject()

	// This contains the user's general vicinity. Although it contains a lat/lon it only
	// gets updated if the user moves a large distance.
	private(set) var currentRegion = RegionInfoForLocation.fromUserPrefs() ?? .none {
		didSet {
			currentRegion.saveToUserPrefs()
		}
	}

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

		navigationController?.isNavigationBarHidden = true

		// set up references
		AppDelegate.shared.mainView = self

		// configure MapView
		// in the storyboard mapView is embedded in MainView, but we're going
		// to make it a child of MapLayersView instead:
		mapView.setUpChildViews(with: self)
		mapView.removeFromSuperview()

		// set up layers view
		mapLayersView.initDefaultChildViews(andAlso: [mapView])
		mapLayersView.setUpChildViews()
		view.addSubview(mapLayersView)
		mapLayersView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			mapLayersView.topAnchor.constraint(equalTo: view.topAnchor),
			mapLayersView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			mapLayersView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			mapLayersView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
		view.sendSubviewToBack(mapLayersView)

		userInstructionLabel.text = NSLocalizedString("Zoom to Edit", comment: "")

		rulerView.mapView = mapView

		// undo/redo buttons
		updateUndoRedoButtonState()
		updateUploadButtonState()
		mapView.mapData.addChangeCallback({ [weak self] in
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

		setupAccessibility()

		// initialize map markers database
		updateMapMarkers(withState: viewState,
		                 delay: 1.0,
		                 including: [])

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
		locationBallView.layer.zPosition = ZLAYER.LOCATION_BALL.rawValue
		locationBallView.viewPort = viewPort
		mapLayersView.addSubview(locationBallView)

		// Compass button
		compassButton.viewPort = viewPort

		// customize buttons
		setButtonAppearances()

		// update button layout constraints
		settings.$buttonLayout.callAndSubscribe(self) { [weak self] buttonLayout in
			self?.updateButtonPositionsFor(layout: buttonLayout)
		}

		progressIndicator.color = UIColor.green

		// tell our error display manager where to display messages
		MessageDisplay.shared.topViewController = self
		MessageDisplay.shared.flashLabel = flashLabel

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
			// pan gesture to recognize mouse-wheel scrolling (zoom) on iPad and Mac Catalyst
			let scrollWheelGesture = UIPanGestureRecognizer(
				target: self,
				action: #selector(handleScrollWheelGesture(_:)))
			scrollWheelGesture.allowedScrollTypesMask = .discrete
			scrollWheelGesture.maximumNumberOfTouches = 0
			view.addGestureRecognizer(scrollWheelGesture)
		}

		// Bindings

		LocationProvider.shared.onChangeLocation.subscribe(self) { [weak self] location in
			self?.locationUpdated(to: location)
			self?.locationBallView.updateLocation(location)
		}

		LocationProvider.shared.onChangeSmoothHeading.subscribe(self) { [weak self] heading, accuracy in
			self?.headingChanged(heading, accuracy: accuracy)
		}

		settings.$enableRotation.subscribe(self) { [weak self] newValue in
			guard let self else { return }
			if !newValue {
				// remove rotation
				let centerPoint = viewPort.screenCenterPoint()
				let angle = CGFloat(viewPort.mapTransform.rotation())
				viewPort.animateRotation(by: -angle, aroundPoint: centerPoint)
			}
		}

		// set initial visible layers
		viewState.onChange.subscribe(self) { [weak self] state in
			guard let self else { return }
			self.viewStateDidChange(to: state)
		}
		viewStateDidChange(to: viewState)

		AppState.shared.tileServerList.onChange.subscribe(self) { [weak self] in
			self?.promptForBetterBackgroundImagery()
		}

		updateAerialAttributionButton()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		if !isInitialized {
			isInitialized = true

			// Don't set viewPort until layout has occurred for child views.
			do {
				try viewPort.loadFromUserDefaults()
			} catch {
				viewPort.mapTransform.transform = .identity
				// turn on GPS which will move us to current location
				gpsState = .LOCATION
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
		viewPort.saveToUserDefaults()

		UserPrefs.shared.synchronize()

		AppState.shared.save()

		// then save data
		mapView.mapData.archiveModifiedData()
	}

	override func viewDidLayoutSubviews() {
		let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
		statusBarBackground.isHidden = windowScene?.statusBarManager?.isStatusBarHidden ?? false
	}

	// MARK: Button state updates

	func updateUndoRedoButtonState() {
		guard undoButton != nil else { return } // during init it can be null
		undoButton.isEnabled = mapView.mapData.canUndo()
		redoButton.isEnabled = mapView.mapData.canRedo()
		undoRedoView.isHidden = mapView.isHidden || (!undoButton.isEnabled && !redoButton.isEnabled)
	}

	func updateUploadButtonState() {
		let yellowCount = 25
		let redCount = 50
		let changeCount = mapView.mapData.modificationCount()
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

	private func updateButtonPositionsFor(layout: MainViewButtonLayout) {
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

	@available(iOS 13.4, *)
	func keypressAction(key: UIKey) {
		let size = view.bounds.size
		let delta = CGPoint(x: size.width * 0.15, y: size.height * 0.15)
		switch key.keyCode {
		case .keyboardRightArrow: viewPort.adjustOrigin(by: CGPoint(x: -delta.x, y: 0))
		case .keyboardLeftArrow: viewPort.adjustOrigin(by: CGPoint(x: delta.x, y: 0))
		case .keyboardDownArrow: viewPort.adjustOrigin(by: CGPoint(x: 0, y: -delta.y))
		case .keyboardUpArrow: viewPort.adjustOrigin(by: CGPoint(x: 0, y: delta.y))
		default:
			mapView.keypressAction(key: key)
		}
	}

	// Maintain timers for repeated keypress handling
	var keypressTimers: [AnyHashable: Timer] = [:]

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		if #available(iOS 13.4, *) {
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
		} else {
			super.pressesBegan(presses, with: event)
		}
	}

	override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		if #available(iOS 13.4, *) {
			for press in presses {
				if let key = press.key {
					if let timer = keypressTimers[key] {
						timer.invalidate()
						keypressTimers.removeValue(forKey: key)
					}
				}
			}
		} else {
			super.pressesEnded(presses, with: event)
		}
	}

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
						let interaction = UIPointerInteraction()
						button.interactions.append(interaction)
					}
				}
			}
		}

		// special handling for aerial logo button
		if #available(iOS 13.4, *) {
			if !aerialServiceLogo.interactions.contains(where: { $0.isKind(of: UIPointerInteraction.self) }) {
				let interaction = UIPointerInteraction()
				aerialServiceLogo.interactions.append(interaction)
			}
		}
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
			return !mapView.isHidden && mapView.mapData.canUndo()
		case #selector(redo(_:)):
			return !mapView.isHidden && mapView.mapData.canRedo()
		case #selector(copy(_:)):
			return mapView.selectedPrimary != nil
		case #selector(paste(_:)):
			return mapView.selectedPrimary != nil && mapView.canPasteTags()
		case #selector(delete(_:)):
			return mapView.selectedPrimary != nil && mapView.selections.relation == nil
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
		mapView.copy(sender)
	}

	@objc override func paste(_ sender: Any?) {
		mapView.paste(sender)
	}

	@objc override func delete(_ sender: Any?) {
		mapView.delete(sender)
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
		guard
			mapView.isRotateObjectMode == nil
		else {
			return
		}

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
		guard settings.enableRotation,
		      mapView.isRotateObjectMode == nil
		else {
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
			updateMapMarkers()
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
					mapView.rightClick(at: mapView.bounds.center())
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
				setAerialTileServer(service)
				if viewState.state == .EDITOR {
					viewState.state = .EDITORAERIAL
				} else if viewState.state == .BASEMAP {
					viewState.state = .EDITORAERIAL
				}
			}))
		}

		// add options for changing display
		let prefix = "🌐 "
		let editorOnly = UIAlertAction(
			title: prefix + NSLocalizedString("Editor only", comment: ""),
			style: .default,
			handler: { [self] _ in
				viewState.state = MapViewState.EDITOR
			})
		let aerialOnly = UIAlertAction(
			title: prefix + NSLocalizedString("Aerial only", comment: ""),
			style: .default,
			handler: { [self] _ in
				viewState.state = MapViewState.AERIAL
			})
		let editorAerial = UIAlertAction(
			title: prefix + NSLocalizedString("Editor with Aerial", comment: ""),
			style: .default,
			handler: { [self] _ in
				viewState.state = MapViewState.EDITORAERIAL
			})

		switch viewState.state {
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

	// MARK: GPS and Location-based updates

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
		   !mapView.isHidden
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

		updateCurrentRegionForLocationUsingCountryCoder()
		checkForChangedTileOverlayLayers()

		// This does an expensive update of map markers, debounced
		updateMapMarkers()
	}

	func moveToLocation(_ location: MapLocation) {
		let zoom = location.zoom > 0 ? location.zoom : 21.0
		let latLon = LatLon(latitude: location.latitude, longitude: location.longitude)
		let rotation = location.direction * .pi / 180.0
		viewPort.centerOn(latLon: latLon,
		                  zoom: zoom,
		                  rotation: rotation)
		if let state = location.view {
			viewState.state = state
		}
	}

	private func updateCurrentRegionForLocationUsingCountryCoder() {
		// if we moved a significant distance then check our location
		let latLon = viewPort.screenCenterLatLon()
		if GreatCircleDistance(latLon, currentRegion.latLon) < 10 * 1000 {
			return
		}
		currentRegion = CountryCoder.shared.regionInfoFor(latLon: latLon)
	}

	private func checkForChangedTileOverlayLayers() {
		// If the user has overlay imagery enabled that is no longer present at this location
		// then remove it.
		// Check if we've moved a long distance from the last check
		let latLon = viewPort.screenCenterLatLon()
		if let plist = UserPrefs.shared.latestOverlayCheckLatLon.value,
		   let prevLatLon = LatLon(plist),
		   GreatCircleDistance(latLon, prevLatLon) < 10 * 1000
		{
			return
		}
		mapLayersView.updateTileOverlayLayers(latLon: latLon)
		UserPrefs.shared.latestOverlayCheckLatLon.value = latLon.plist
	}

	private func promptForBetterBackgroundImagery() {
		if mapLayersView.aerialLayer.isHidden {
			return
		}

		// Check if we've moved a long distance from the last check
		let latLon = viewPort.screenCenterLatLon()
		if let plist = UserPrefs.shared.latestAerialCheckLatLon.value,
		   let prevLatLon = LatLon(plist),
		   GreatCircleDistance(latLon, prevLatLon) < 10 * 1000
		{
			return
		}

		// check whether we need to change aerial imagery
		let tileServerList = AppState.shared.tileServerList
		if !tileServerList.currentServer.coversLocation(latLon) {
			// current imagery layer doesn't exist at current location
			let best = tileServerList.bestService(at: latLon) ?? tileServerList.builtinServers()[0]
			tileServerList.currentServer = best
			setAerialTileServer(best)
		} else if viewPort.mapTransform.zoom() < 15 {
			// the user has zoomed out, so don't bother them until they zoom in.
			// return here instead of updating last check location.
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
			                              	AppState.shared.tileServerList.currentServer = best
			                              	self.setAerialTileServer(best)
			                              }))
			present(alert, animated: true)
		}

		UserPrefs.shared.latestAerialCheckLatLon.value = latLon.plist
	}

	// MARK: Button actions

	@IBAction func toggleLocationButton() {
		switch gpsState {
		case GPS_STATE.NONE:
			// if the user hasn't rotated the screen then start facing north, otherwise follow heading
			if abs(viewPort.mapTransform.rotation()) < 0.0001 {
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

	func viewStateDidChange(to state: ViewStateAndOverlays) {
		// Things are complicated because the user has their own preference for the view
		// but when they zoom out we make automatic substitutions:
		// 	Editor only --> Basemap
		//	Editor+Aerial --> Aerial+Locator
		let newState: MapViewState
		let newOverlays: MapViewOverlays
		switch (state.zoomedOut, state.state) {
		case (true, .EDITOR):
			newState = .BASEMAP
			newOverlays = state.overlayMask
		case (true, .EDITORAERIAL):
			newState = .AERIAL
			newOverlays = state.overlayMask.union(.LOCATOR)
		default:
			newState = state.state
			newOverlays = state.overlayMask
		}

		CATransaction.begin()
		CATransaction.setAnimationDuration(0.5)

		mapLayersView.locatorLayer.isHidden = !newOverlays.contains(.LOCATOR)
			|| mapLayersView.locatorLayer.tileServer.apiKey == ""

		aerialAlignmentButton.isHidden = true
		dPadView.isHidden = true

		switch newState {
		case MapViewState.EDITOR:
			mapView.isHidden = false
			mapLayersView.aerialLayer.isHidden = true
			mapLayersView.basemapLayer.isHidden = true
		case MapViewState.EDITORAERIAL:
			mapLayersView.aerialLayer.tileServer = AppState.shared.tileServerList.currentServer
			mapView.isHidden = false
			mapLayersView.aerialLayer.isHidden = false
			mapLayersView.basemapLayer.isHidden = true
			aerialAlignmentButton.isHidden = false
		case MapViewState.AERIAL:
			mapLayersView.aerialLayer.tileServer = AppState.shared.tileServerList.currentServer
			mapView.isHidden = true
			mapLayersView.aerialLayer.isHidden = false
			mapLayersView.basemapLayer.isHidden = true
		case MapViewState.BASEMAP:
			mapView.isHidden = true
			mapLayersView.aerialLayer.isHidden = true
			mapLayersView.basemapLayer.isHidden = false
		}

		userInstructionLabel.isHidden = (newState != .EDITOR && newState != .EDITORAERIAL) || !state.zoomedOut

		mapLayersView.quadDownloadLayer?.isHidden = mapView.isHidden

		if let noName = mapLayersView.noNameLayer() {
			noName.isHidden = !mapView.isHidden
		}

		CATransaction.commit()

		// enable/disable editing buttons based on visibility
		updateUndoRedoButtonState()
		updateAerialAttributionButton()
		updateUploadButtonState()
		addNodeButton.isHidden = mapView.isHidden

		updateMapMarkers(withState: state,
		                 delay: 0,
		                 including: [])

		// FIXME:
		mapView.whiteText = !mapLayersView.aerialLayer.isHidden
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
		let aerial = mapLayersView.aerialLayer.tileServer
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
		let offset = mapLayersView.aerialLayer.imageryOffsetMeters
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
		let newOffset = mapLayersView.aerialLayer.imageryOffsetMeters.plus(CGPoint(
			x: shift.x * scale,
			y: shift.y * scale))
		mapLayersView.aerialLayer.imageryOffsetMeters = newOffset
		updateAerialAlignmentButton()
	}

	// MARK: Other stuff

	func setAerialTileServer(_ service: TileServer) {
		mapLayersView.aerialLayer.tileServer = service
		updateAerialAttributionButton()
		// update imagery offset
		mapLayersView.aerialLayer.imageryOffsetMeters = CGPointZero
		updateAerialAlignmentButton()
	}

	func updateAerialAttributionButton() {
		let service = mapLayersView.aerialLayer.tileServer
		let icon = service.attributionIcon(height: aerialServiceLogo.frame.size.height,
		                                   completion: { [weak self] in
		                                   	self?.updateAerialAttributionButton()
		                                   })
		aerialServiceLogo.isHidden = mapLayersView.aerialLayer.isHidden
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
		mapView.didReceiveMemoryWarning()
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

	// MARK: Map Markers

	func updateMapMarkers(including: MapMarkerDatabase.MapMarkerSet = []) {
		updateMapMarkers(withState: viewState, delay: 0.0, including: including)
	}

	// This performs an expensive update with a time delay, coalescing multiple calls
	// into a single update.
	private func updateMapMarkers(withState viewState: ViewStateAndOverlays,
	                              delay: CGFloat,
	                              including: MapMarkerDatabase.MapMarkerSet)
	{
		let delay = max(delay, 0.5)
		var including = including
		if including.isEmpty {
			// compute the list
			if viewState.overlayMask.contains(.NOTES) {
				including.insert(.notes)
				including.insert(.fixme)
			}
			if viewState.overlayMask.contains(.QUESTS) {
				including.insert(.quest)
			}
			if settings.displayGpxTracks {
				including.insert(.gpx)
			}
			if mapLayersView.displayDataOverlayLayers {
				including.insert(.geojson)
			}
		} else if !viewState.overlayMask.contains(.QUESTS) {
			including.remove(.quest)
		}

		mapLayersView.mapMarkersView.updateRegion(withDelay: delay,
		                                          including: including)
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
