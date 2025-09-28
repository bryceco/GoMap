//
//  FirstViewController.h
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

class MainViewController: UIViewController, UIActionSheetDelegate, UIGestureRecognizerDelegate,
	UIContextMenuInteractionDelegate, UIPointerInteractionDelegate, UIAdaptivePresentationControllerDelegate
{
	@IBOutlet var uploadButton: UIButton!
	@IBOutlet var undoButton: UIButton!
	@IBOutlet var redoButton: UIButton!
	@IBOutlet var undoRedoView: UIVisualEffectView!
	@IBOutlet var searchButton: UIButton!

	@IBOutlet var mapView: MapView!
	@IBOutlet var locationButton: UIButton!

	override var shouldAutorotate: Bool { true }
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

	var buttonLayout: MainViewButtonLayout! {
		didSet {
			updateButtonPositionsFor(layout: buttonLayout)
		}
	}

	@IBOutlet private var settingsButton: UIButton!
	@IBOutlet private var displayButton: UIButton!

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

	func updateButtonPositionsFor(layout: MainViewButtonLayout) {
		UserPrefs.shared.mapViewButtonLayout.value = layout.rawValue

		guard
			let addButton = mapView.addNodeButton,
			let superview = addButton.superview,
			let c = superview.constraints.first(where: {
				if ($0.firstItem as? UIView) == addButton,
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

	// MARK: Initialization

	override func viewDidLoad() {
		super.viewDidLoad()

		mapView.mainViewController = self

		AppDelegate.shared.mapView = mapView

		// undo/redo buttons
		updateUndoRedoButtonState()
		updateUploadButtonState()

		weak var weakSelf = self
		mapView.editorLayer.mapData.addChangeCallback({
			weakSelf?.updateUndoRedoButtonState()
			weakSelf?.updateUploadButtonState()
		})

		setupAccessibility()

		// long press for quick access to aerial imagery
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(displayButtonLongPressGesture(_:)))
		displayButton.addGestureRecognizer(longPress)

		// customize buttons
		setButtonAppearances()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.isNavigationBarHidden = true

		// update button layout constraints
		buttonLayout = MainViewButtonLayout(rawValue: UserPrefs.shared.mapViewButtonLayout.value
			?? MainViewButtonLayout.buttonsOnRight.rawValue)

		if #available(iOS 13.4, macCatalyst 13.0, *) {
			// mouseover support for Mac Catalyst and iPad:
			let hover = UIHoverGestureRecognizer(target: self, action: #selector(hover(_:)))
			mapView.addGestureRecognizer(hover)

#if targetEnvironment(macCatalyst)
			// right-click support for Mac Catalyst
			let rightClick = UIContextMenuInteraction(delegate: self)
			mapView.addInteraction(rightClick)
#else
			// right-click support for iPad:
			let rightClick = UITapGestureRecognizer(target: self, action: #selector(rightClick(_:)))
			rightClick.allowedTouchTypes = [NSNumber(integerLiteral: UITouch.TouchType.indirect.rawValue)]
			rightClick.buttonMaskRequired = .secondary
			mapView.addGestureRecognizer(rightClick)
#endif
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
#if USER_MOVABLE_BUTTONS
		makeMovableButtons()
#endif

		// this is necessary because we need the frame to be set on the view before we set the previous lat/lon for the view
		mapView.viewDidAppear()
	}

	func setupAccessibility() {
		locationButton.accessibilityIdentifier = "location_button"
		undoButton.accessibilityLabel = NSLocalizedString("Undo", comment: "")
		redoButton.accessibilityLabel = NSLocalizedString("Redo", comment: "")
		settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "")
		uploadButton.accessibilityLabel = NSLocalizedString("Upload your changes", comment: "")
		displayButton.accessibilityLabel = NSLocalizedString("Display options", comment: "")
	}

	// MARK: Notifications

	func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
		// We were just displayed so update map
	}

	@objc func rightClick(_ recognizer: UIGestureRecognizer) {
		let location = recognizer.location(in: mapView)
		mapView.rightClick(atLocation: location)
	}

	@available(iOS 13.0, *)
	func contextMenuInteraction(
		_ interaction: UIContextMenuInteraction,
		configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration?
	{
		mapView.rightClick(atLocation: location)
		return nil
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
				hit = mapView.editorLayer.osmHitTestNode(inSelectedWay: loc, radius: DefaultHitTestRadius)
			}
			if hit == nil {
				hit = mapView.editorLayer.osmHitTest(
					loc,
					radius: DefaultHitTestRadius,
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
		case .keyboardRightArrow: mapView.adjustOrigin(by: CGPoint(x: -delta.x, y: 0))
		case .keyboardLeftArrow: mapView.adjustOrigin(by: CGPoint(x: delta.x, y: 0))
		case .keyboardDownArrow: mapView.adjustOrigin(by: CGPoint(x: 0, y: -delta.y))
		case .keyboardUpArrow: mapView.adjustOrigin(by: CGPoint(x: 0, y: delta.y))
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
			mapView.addNodeButton,
			mapView.compassButton,
			mapView.centerOnGPSButton,
			mapView.helpButton,
			mapView.aerialAlignmentButton,
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
					case mapView.aerialAlignmentButton, mapView.helpButton:
						// These button have tighter spacing to deemphasize them
						config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
					case mapView.addNodeButton:
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

					// Adjust sizes of buttons to make them a little larger
					if button != mapView.helpButton,
					   button != mapView.aerialAlignmentButton,
					   button != mapView.addNodeButton
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
			if view == mapView.compassButton || view == mapView.editToolbar {
				// these buttons take care of themselves
			} else if view == mapView.helpButton || view == mapView.addNodeButton {
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
			   button != mapView.compassButton,
			   button != mapView.helpButton,
			   button != mapView.aerialAlignmentButton
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
			if !mapView.aerialServiceLogo.interactions.contains(where: { $0.isKind(of: UIPointerInteraction.self) }) {
				let interaction = UIPointerInteraction(delegate: self)
				mapView.aerialServiceLogo.interactions.append(interaction)
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
		if button == mapView.aerialAlignmentButton {
			button.backgroundColor = button.backgroundColor?.withAlphaComponent(0.4)
		}
#endif
	}

	// MARK: User-movable buttons

#if USER_MOVABLE_BUTTONS
	func removeConstrains(on view: UIView?) {
		var superview = view?.superview
		while superview != nil {
			for c in superview?.constraints ?? [] {
				if (c.firstItem as? UIView) == view || (c.secondItem as? UIView) == view {
					superview?.removeConstraint(c)
				}
			}
			superview = superview?.superview
		}
		for c in view?.constraints ?? [] {
			if (c.firstItem as? UIView)?.superview == view || (c.secondItem as? UIView)?.superview == view {
				// skip
			} else {
				view?.removeConstraint(c)
			}
		}
	}

	func makeMovableButtons() {
		let buttons = [
			//		_mapView.editControl,
			undoRedoView,
			locationButton,
			searchButton,
			mapView.addNodeButton,
			settingsButton,
			uploadButton,
			displayButton,
			mapView.compassButton,
			mapView.helpButton,
			mapView.centerOnGPSButton
			//		_mapView.rulerView,
		]
		// remove layout constraints
		for button in buttons {
			guard let button = button as? UIButton else {
				continue
			}
			removeConstrains(on: button)
			button.translatesAutoresizingMaskIntoConstraints = true
		}
		for button in buttons {
			guard let button = button as? UIButton else {
				continue
			}
			let panGesture = UIPanGestureRecognizer(target: self, action: #selector(buttonPan(_:)))
			// panGesture.delegate = self;
			button.addGestureRecognizer(panGesture)
		}
		let message = """
		This build has a temporary feature: Drag the buttons in the UI to new locations that looks and feel best for you.\n\n\
		* Submit your preferred layouts either via email or on GitHub.\n\n\
		* Positions reset when the app terminates\n\n\
		* Orientation changes are not supported\n\n\
		* Buttons won't move when they're disabled (undo/redo, upload)
		"""
		let alert = UIAlertController(buttonLabel: "Attention Testers!", message: message, preferredStyle: .alert)
		let ok = UIAlertAction(buttonLabel: NSLocalizedString("OK", comment: ""), style: .default, handler: { _ in
			alert.dismiss(animated: true)
		})
		alert.addAction(ok)
		present(alert, animated: true)
	}

	@objc func buttonPan(_ pan: UIPanGestureRecognizer?) {
		if pan?.state == .began {
		} else if pan?.state == .changed {
			pan?.view?.center = pan?.location(in: view) ?? CGPoint.zero
		} else {}
	}
#endif

	// MARK: Keyboard shortcuts

	override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
		switch action {
		case #selector(undo(_:)):
			return mapView.editorLayer.mapData.canUndo()
		case #selector(redo(_:)):
			return mapView.editorLayer.mapData.canRedo()
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

	// MARK: Gesture recognizers

	// disable gestures inside toolbar buttons
	func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		// http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer
		if (touch.view is UIControl) || (touch.view is UIToolbar) {
			// we touched a button, slider, or other UIControl
			return false // ignore the touch
		}
		return true // handle the touch
	}

	func installGestureRecognizer(_ gesture: UIGestureRecognizer, on button: UIButton) {
		if (button.gestureRecognizers?.count ?? 0) == 0 {
			button.addGestureRecognizer(gesture)
		}
	}

	@objc func displayButtonLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
		if recognizer.state == .began {
			showPopupToSelectFromRecentAerialImagery()
		}
	}

	func showPopupToSelectFromRecentAerialImagery() {
		// show the most recently used aerial imagery
		let tileServerlList = mapView.tileServerList
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

	// MARK: Other stuff

	@IBAction func openHelp() {
		let urlAsString = "https://wiki.openstreetmap.org/w/index.php?title=Go_Map!!&mobileaction=toggle_view_mobile"
		guard let url = URL(string: urlAsString) else { return }

		let safariViewController = SFSafariViewController(url: url)
		safariViewController.modalPresentationStyle = .pageSheet
		safariViewController.popoverPresentationController?.sourceView = view
		present(safariViewController, animated: true)
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
		mapView.flashMessage(title: nil,
		                     message: NSLocalizedString("Low memory: clearing cache", comment: ""))
		mapView.editorLayer.didReceiveMemoryWarning()
	}

	func setGpsState(_ state: GPS_STATE) {
		if mapView.gpsState != state {
			mapView.gpsState = state

			// update GPS icon
			let isActive = mapView.gpsState != GPS_STATE.NONE
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
	}

	@IBAction func toggleLocationButton(_ sender: Any) {
		switch mapView.gpsState {
		case GPS_STATE.NONE:
			// if the user hasn't rotated the screen then start facing north, otherwise follow heading
			if fabs(mapView.screenFromMapTransform.rotation()) < 0.0001 {
				setGpsState(GPS_STATE.LOCATION)
			} else {
				setGpsState(GPS_STATE.HEADING)
			}
		case GPS_STATE.LOCATION,
		     GPS_STATE.HEADING:
			setGpsState(GPS_STATE.NONE)
		}
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

let USER_MOVABLE_BUTTONS = 0
