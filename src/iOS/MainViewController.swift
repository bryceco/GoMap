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

enum BUTTON_LAYOUT : Int {
    case _ADD_ON_LEFT
    case _ADD_ON_RIGHT
}

class MainViewController: UIViewController, UIActionSheetDelegate, UIGestureRecognizerDelegate, UIContextMenuInteractionDelegate {
    @IBOutlet var _uploadButton: UIButton!
    @IBOutlet var _undoButton: UIButton!
    @IBOutlet var _redoButton: UIButton!
    @IBOutlet var _undoRedoView: UIView!
    @IBOutlet var _searchButton: UIButton!
    
    @IBOutlet var mapView: MapView!
    @IBOutlet var locationButton: UIButton!
    
    private var _buttonLayout: BUTTON_LAYOUT!
    var buttonLayout: BUTTON_LAYOUT! {
        get {
            return _buttonLayout
        }
        set(buttonLayout) {
            _buttonLayout = buttonLayout
            
            UserDefaults.standard.set(_buttonLayout.rawValue, forKey: "buttonLayout")
            
            let left = buttonLayout == ._ADD_ON_LEFT
            let attribute: NSLayoutConstraint.Attribute = left ? .leading : .trailing
            let addButton = mapView.addNodeButton
            let superview = addButton?.superview
            for c in superview?.constraints ?? [] {
                if (c.firstItem as? UIView) != addButton {
                    continue
                }
                if !((c.secondItem is UILayoutGuide) || (c.secondItem is UIView)) {
                    continue
                }
                if (c.firstAttribute == .leading || c.firstAttribute == .trailing) && (c.secondAttribute == .leading || c.secondAttribute == .trailing) {
                    superview?.removeConstraint(c)
                    let c2 = NSLayoutConstraint(
						item: c.firstItem as Any,
                        attribute: attribute,
                        relatedBy: .equal,
                        toItem: c.secondItem,
                        attribute: attribute,
                        multiplier: 1.0,
                        constant: CGFloat(left ? abs(Float(c.constant)) : -abs(Float(c.constant))))
                    superview?.addConstraint(c2)
                    return
                }
            }
            assert(false) // didn't find the constraint
        }
    }
    @IBOutlet private weak var settingsButton: UIButton!
    @IBOutlet private weak var displayButton: UIButton!
    
    func updateUndoRedoButtonState() {
		guard _undoButton != nil else { return }	// during init it can be null
		_undoButton.isEnabled = mapView.editorLayer.mapData.canUndo() && !mapView.editorLayer.isHidden
        _redoButton.isEnabled = mapView.editorLayer.mapData.canRedo() && !mapView.editorLayer.isHidden
        _uploadButton.isHidden = !_undoButton.isEnabled
        _undoRedoView.isHidden = !_undoButton.isEnabled && !_redoButton.isEnabled
    }
    
    func updateUploadButtonState() {
        let yellowCount = 25
        let redCount = 50
        let changeCount = mapView.editorLayer.mapData.modificationCount()
        var color: UIColor? = nil
        if changeCount < yellowCount {
            color = nil // default color
        } else if changeCount < redCount {
            color = UIColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0) // yellow
        } else {
            color = UIColor.red // red
        }
        _uploadButton.tintColor = color
        _uploadButton.isEnabled = changeCount > 0
    }
    
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(UIApplicationDelegate.applicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    func setupAccessibility() {
        locationButton.accessibilityIdentifier = "location_button"
        _undoButton.accessibilityLabel = NSLocalizedString("Undo", comment: "")
        _redoButton.accessibilityLabel = NSLocalizedString("Redo", comment: "")
        settingsButton.accessibilityLabel = NSLocalizedString("Settings", comment: "")
        _uploadButton.accessibilityLabel = NSLocalizedString("Upload your changes", comment: "")
        displayButton.accessibilityLabel = NSLocalizedString("Display options", comment: "")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = true
        
        // update button layout constraints
        UserDefaults.standard.register(defaults: [
            "buttonLayout": NSNumber(value: BUTTON_LAYOUT._ADD_ON_RIGHT.rawValue)
        ])
        buttonLayout = BUTTON_LAYOUT(rawValue: UserDefaults.standard.integer(forKey: "buttonLayout"))
        
        setButtonAppearances()
        
        #if targetEnvironment(macCatalyst)
        // mouseover support for Mac Catalyst:
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hover(_:)))
        mapView.addGestureRecognizer(hover)
        
        // right-click support for Mac Catalyst:
        let rightClick = UIContextMenuInteraction(delegate: self)
        mapView.addInteraction(rightClick)
        #endif
    }
    
    @objc func hover(_ recognizer: UIGestureRecognizer) {
		let loc = recognizer.location(in: mapView)
		var segment = 0
        var hit: OsmBaseObject? = nil
		if recognizer.state == .changed && !mapView.editorLayer.isHidden {
			if mapView.editorLayer.selectedWay != nil {
				hit = mapView.editorLayer.osmHitTestNode(inSelectedWay: loc, radius: DefaultHitTestRadius)
			}
			if hit == nil {
				hit = mapView.editorLayer.osmHitTest(loc, radius: DefaultHitTestRadius, isDragConnect: false, ignoreList: [], segment: &segment)
			}
			if let chit = hit,
			   chit == mapView.editorLayer.selectedNode || chit == mapView.editorLayer.selectedWay || chit.isRelation() != nil
			{
				hit = nil
			}
		}
		mapView.blink(hit, segment: -1)
    }
    
    @available(iOS 13.0, *)
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        mapView.rightClick(atLocation: location)
        return nil
    }

	#if targetEnvironment(macCatalyst)
	func keypressAction( key: UIKey ) {
		let size = self.view.bounds.size
		let delta = CGPoint(x: size.width * 0.15, y: size.height * 0.15)
		switch key.keyCode {
		case .keyboardRightArrow:	mapView.adjustOrigin(by: CGPoint(x: -delta.x, y: 0))
		case .keyboardLeftArrow:	mapView.adjustOrigin(by: CGPoint(x: delta.x, y: 0))
		case .keyboardDownArrow:	mapView.adjustOrigin(by: CGPoint(x: 0, y: -delta.y))
		case .keyboardUpArrow:		mapView.adjustOrigin(by: CGPoint(x: 0, y: delta.y))
		default:					break
		}
	}
	var keypressTimers: Dictionary<UIKey,Timer> = [:]
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		if #available(macCatalyst 13.4, *) {
            for press in presses {
				if let key = press.key {
					keypressAction(key: key)
					if keypressTimers[key] == nil {
						let timer = Timer(fire: Date.init(timeInterval: 0.5, since: Date()), interval: 0.25, repeats: true, block: {_ in
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

    func setButtonAppearances() {
        // update button styling
        let buttons = [
            // these aren't actually buttons, but they get similar tinting and shadows
            mapView.editControl,
            _undoRedoView,
            // these are buttons
            locationButton,
            _undoButton,
            _redoButton,
            mapView.addNodeButton,
            mapView.compassButton,
            mapView.centerOnGPSButton,
            mapView.helpButton,
            settingsButton,
            _uploadButton,
            displayButton,
            _searchButton
        ]
        for view in buttons {
            
            // corners
            if view == mapView.compassButton || view == mapView.editControl {
                // these buttons take care of themselves
            } else if view == mapView.helpButton || view == mapView.addNodeButton {
                // The button is a circle.
                if let bounds = view?.bounds.size.width {
                    view?.layer.cornerRadius = bounds / 2
                }
            } else {
                // rounded corners
                view?.layer.cornerRadius = 10.0
            }
            // shadow
            if view?.superview != _undoRedoView {
                view?.layer.shadowColor = UIColor.black.cgColor
                view?.layer.shadowOffset = CGSize(width: 0, height: 0)
                view?.layer.shadowRadius = 3
                view?.layer.shadowOpacity = 0.5
                view?.layer.masksToBounds = false
            }
            // image blue tint
            if view is UIButton {
                let button = view as? UIButton
                if button != mapView.compassButton && button != mapView.helpButton {
                    let image = button?.currentImage?.withRenderingMode(.alwaysTemplate)
                    button?.setImage(image, for: .normal)
                    if #available(iOS 13.0, *) {
                        button?.tintColor = UIColor.link
                    } else {
                        button?.tintColor = UIColor.systemBlue
                    }
                    if button == mapView.addNodeButton {
                        button?.imageEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15) // resize images on button to be smaller
                    } else {
                        button?.imageEdgeInsets = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9) // resize images on button to be smaller
                    }
                }
            }
            
            // normal background color
            makeButtonNormal(view)
            
            // background selection color
            if view is UIButton {
                let button = view as? UIButton
                button?.addTarget(self, action: #selector(makeButtonHighlight(_:)), for: .touchDown)
                button?.addTarget(self, action: #selector(makeButtonNormal(_:)), for: .touchUpInside)
                button?.addTarget(self, action: #selector(makeButtonNormal(_:)), for: .touchUpOutside)
                button?.addTarget(self, action: #selector(makeButtonNormal(_:)), for: .touchCancel)
                
                button?.showsTouchWhenHighlighted = true
            }
        }
    }
    
    @objc func makeButtonHighlight(_ button: UIView?) {
        if #available(iOS 13.0, *) {
            button?.backgroundColor = UIColor.secondarySystemBackground
        } else {
            button?.backgroundColor = UIColor.lightGray
        }
    }
    
    @objc func makeButtonNormal(_ button: UIView?) {
        if #available(iOS 13.0, *) {
            button?.backgroundColor = UIColor.systemBackground
        } else {
            button?.backgroundColor = UIColor.white
        }
    }
    
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
            _undoRedoView,
            locationButton,
            _searchButton,
            mapView.addNodeButton,
            settingsButton,
            _uploadButton,
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
        let alert = UIAlertController(title: "Attention Testers!", message: message, preferredStyle: .alert)
        let ok = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { action in
            alert.dismiss(animated: true)
        })
        alert.addAction(ok)
        present(alert, animated: true)
    }
    
    @objc func buttonPan(_ pan: UIPanGestureRecognizer?) {
        if pan?.state == .began {
        } else if pan?.state == .changed {
            pan?.view?.center = pan?.location(in: view) ?? CGPoint.zero
        } else {
        }
    }
#endif
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
#if USER_MOVABLE_BUTTONS
            makeMovableButtons()
#endif
        
        // this is necessary because we need the frame to be set on the view before we set the previous lat/lon for the view
        mapView.viewDidAppear()
        
#if false && DEBUG
            let speech = SpeechBalloonView(text: "Press here to create a new node,\nor to begin a way")
            speech.targetView = toolbar
            view.addSubview(speech)
#endif
    }

	@IBAction func openHelp() {
		let urlAsString = "https://wiki.openstreetmap.org/w/index.php?title=Go_Map!!&mobileaction=toggle_view_mobile"
		guard let url = URL(string: urlAsString) else { return }

		let safariViewController = SFSafariViewController(url: url)
		safariViewController.modalPresentationStyle = .pageSheet
		safariViewController.popoverPresentationController?.sourceView = view
		present(safariViewController, animated: true)
	}

	// MARK: Keyboard shortcuts
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(undo(_:)) {
            return mapView.editorLayer.mapData.canUndo()
        }
        if action == #selector(redo(_:)) {
            return mapView.editorLayer.mapData.canRedo()
        }
        if action == #selector(copy(_:)) {
            return mapView.editorLayer.selectedPrimary != nil
        }
        if action == #selector(paste(_:)) {
            return mapView.editorLayer.selectedPrimary != nil && mapView.editorLayer.canPasteTags()
        }
        if action == #selector(delete(_:)) {
            return (mapView.editorLayer.selectedPrimary != nil) && (mapView.editorLayer.selectedRelation == nil)
        }
        if action == #selector(showHelp(_:)) {
            return true
        }
        return false
    }
    
    @objc func undo(_ sender: Any?) {
        mapView.undo(sender)
    }
    
    @objc func redo(_ sender: Any?) {
        mapView.redo(sender)
    }
    
    @objc override func copy(_ sender: Any?) {
		mapView.performEdit(EDIT_ACTION.COPYTAGS)
    }
    
    @objc override func paste(_ sender: Any?) {
		mapView.performEdit(EDIT_ACTION.PASTETAGS)
    }
    
    @objc override func delete(_ sender: Any?) {
		mapView.performEdit(EDIT_ACTION.DELETE)
    }
    
    @objc func showHelp(_ sender: Any?) {
        openHelp()
    }
    
    // MARK: Gesture recognizers
    
    func addNodeQuick(_ recognizer: UILongPressGestureRecognizer?) {
        if recognizer?.state == .began {
            print("go")
        }
    }
    
    func installGestureRecognizer(_ gesture: UIGestureRecognizer?, on button: UIButton?) {
        let view = button
        if (view?.gestureRecognizers?.count ?? 0) == 0 {
            if let gesture = gesture {
                view?.addGestureRecognizer(gesture)
            }
        }
    }
    
    @objc func displayButtonLongPressGesture(_ recognizer: UILongPressGestureRecognizer?) {
        if recognizer?.state == .began {
            // show the most recently used aerial imagery
            let aerialList = mapView.customAerials
            let actionSheet = UIAlertController(
                title: NSLocalizedString("Recent Aerial Imagery", comment: "Alert title message"),
                message: nil,
                preferredStyle: .actionSheet)
			for service in aerialList.recentlyUsed() {
				actionSheet.addAction(UIAlertAction(title: service.name, style: .default, handler: { [self] action in
					aerialList.currentAerial = service
					mapView.setAerialTileService(service)
					if mapView.viewState == MapViewState.EDITOR {
						mapView.viewState = MapViewState.EDITORAERIAL
					} else if mapView.viewState == MapViewState.MAPNIK {
						mapView.viewState = MapViewState.EDITORAERIAL
					}
				}))
            }
            
            // add options for changing display
            let prefix = "🌐 "
            let editorOnly = UIAlertAction(
                title: prefix + NSLocalizedString("Editor only", comment: ""),
                style: .default,
                handler: { [self] action in
					mapView.viewState = MapViewState.EDITOR
                })
            let aerialOnly = UIAlertAction(
                title: prefix + NSLocalizedString("Aerial only", comment: ""),
                style: .default,
                handler: { [self] action in
					mapView.viewState = MapViewState.AERIAL
                })
            let editorAerial = UIAlertAction(
                title: prefix + NSLocalizedString("Editor with Aerial", comment: ""),
                style: .default,
                handler: { [self] action in
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
			case .MAPNIK:
                actionSheet.addAction(editorAerial)
                actionSheet.addAction(editorOnly)
                actionSheet.addAction(aerialOnly)
            }
            
            actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            present(actionSheet, animated: true)
            // set location of popup
            actionSheet.popoverPresentationController?.sourceView = displayButton
            actionSheet.popoverPresentationController?.sourceRect = displayButton.bounds
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        DLog("memory warning: \(MemoryUsedMB()) MB used")
        
        mapView.flashMessage(NSLocalizedString("Low memory: clearing cache", comment: ""))
        
        mapView.editorLayer.didReceiveMemoryWarning()
    }
    
    func setGpsState(_ state: GPS_STATE) {
        if mapView.gpsState != state {
            mapView.gpsState = state
            
            // update GPS icon
			let imageName = (mapView.gpsState == GPS_STATE.NONE) ? "location2" : "location.fill"
            var image = UIImage(named: imageName)
            image = image?.withRenderingMode(.alwaysTemplate)
            locationButton.setImage(image, for: .normal)
        }
    }
    
    @IBAction func toggleLocation(_ sender: Any) {
        switch mapView.gpsState {
		case GPS_STATE.NONE:
			setGpsState(GPS_STATE.LOCATION)
            mapView.rotateToNorth()
		case GPS_STATE.LOCATION,
			 GPS_STATE.HEADING:
			setGpsState(GPS_STATE.NONE)
        }
    }
    
    @objc func applicationDidEnterBackground(_ sender: Any?) {
        let appDelegate = AppDelegate.shared
        if appDelegate.mapView!.gpsInBackground && appDelegate.mapView!.enableGpxLogging {
			// allow GPS collection in background
        } else {
            // turn off GPS tracking
			setGpsState(GPS_STATE.NONE)
		}
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { [self] context in
            var rc = mapView.frame
            rc.size = size
            mapView.frame = rc
        }) { context in
        }
    }
    
#if true
    // disable gestures inside toolbar buttons
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer
        
        if (touch.view is UIControl) || (touch.view is UIToolbar) {
            // we touched a button, slider, or other UIControl
            return false // ignore the touch
        }
        return true // handle the touch
    }
#endif
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if sender is OsmNote {
            var con: NotesTableViewController?
            if segue.destination is NotesTableViewController {
                /// The `NotesTableViewController` is presented directly.
                con = segue.destination as? NotesTableViewController
            } else if segue.destination is UINavigationController {
                let navigationController = segue.destination as? UINavigationController
                if navigationController?.viewControllers.first is NotesTableViewController {
                    /// The `NotesTableViewController` is wrapped in an `UINavigationController´.
                    con = navigationController?.viewControllers.first as? NotesTableViewController
                }
            }
            
            con?.note = sender as? OsmNote
            con?.mapView = mapView
        }
    }
}

let USER_MOVABLE_BUTTONS = 0
