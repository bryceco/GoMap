//
//  MapView.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

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
	case NONE // none
	case LOCATION // location only
	case HEADING // location and heading
}

struct MapLocation {
	let longitude: Double
	let latitude: Double
	let zoom: Double
	let direction: Double // degrees clockwise from north
	let view: MapViewState?

	init(longitude: Double,
	     latitude: Double,
	     zoom: Double = 0,
	     direction: Double = 0,
	     viewState: MapViewState? = nil)
	{
		self.longitude = longitude
		self.latitude = latitude
		self.zoom = zoom
		self.direction = direction
		self.view = viewState
	}

	init(exif: EXIFInfo) {
		longitude = exif.longitude
		latitude = exif.latitude
		direction = exif.direction ?? 0.0
		zoom = 0
		view = nil
	}
}

// MARK: MapView

final class MapView: UIView,
	UIGestureRecognizerDelegate, UISheetPresentationControllerDelegate
{
	var isRotateObjectMode: (rotateObjectOverlay: CAShapeLayer, rotateObjectCenter: LatLon)?

	var voiceAnnouncement: VoiceAnnouncement?
	var objectRotationGesture: UIRotationGestureRecognizer!

	@IBOutlet var editToolbar: CustomSegmentedControl!

	private var magnifyingGlass: MagnifyingGlass!

	private var editControlActions: [EDIT_ACTION] = []

	var mainView: MainViewController!
	var viewPort: MapViewPort { mainView.viewPort }

	private(set) lazy var mapMarkerDatabase = MapMarkerDatabase()

	private(set) var editorLayer: EditorMapLayer!

	private(set) var pushPin: PushPinView?
	var pushPinIsOnscreen = false

	private(set) var crossHairs: CAShapeLayer!

	// This contains the user's general vicinity. Although it contains a lat/lon it only
	// gets updated if the user moves a large distance.
	private(set) var currentRegion: RegionInfoForLocation

	@IBOutlet private var statusBarBackground: StatusBarGradient!

	// MARK: initialization

	required init?(coder: NSCoder) {
		currentRegion = RegionInfoForLocation.none

		super.init(coder: coder)
	}

	override func awakeFromNib() {
		super.awakeFromNib()

		// set up action button
		editToolbar.isHidden = true
		editToolbar.layer.cornerRadius = 8.0
		editToolbar.layer.masksToBounds = true
#if targetEnvironment(macCatalyst)
		// We add a constraint in the storyboard to make the edit control buttons taller
		// so they're easier to push, but on Mac the constraints doesn't work correctly
		// and the buttons look ugly, so remove it.
		if let height = editToolbar.constraints.first(where: {
			$0.firstAttribute == .height && $0.constant == 43.0
		}) {
			editToolbar.removeConstraint(height)
		}
#endif

		// long press for selecting from multiple objects (for multipolygon members)
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(screenLongPressGesture(_:)))
		longPress.delegate = self
		addGestureRecognizer(longPress)

		// two-finger rotation of OSM objects
		objectRotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(_:)))
		objectRotationGesture.delegate = self
		objectRotationGesture.isEnabled = false // disabled until needed
		addGestureRecognizer(objectRotationGesture)

		// magnifying glass
		magnifyingGlass = MagnifyingGlass(sourceView: self, radius: 70.0, scale: 2.0)
		superview!.addSubview(magnifyingGlass)
		magnifyingGlass.setPosition(.topLeft, animated: false)
		magnifyingGlass.isHidden = true
	}

	func setUpChildViews(with main: MainViewController) {
		self.mainView = main

		viewPort.mapTransform.onChange.subscribe(self) { [weak self] in
			self?.mapTransformDidChange()
		}

		AppState.shared.tileServerList.onChange.subscribe(self) { [weak self] in
			self?.promptForBetterBackgroundImagery()
		}

		layer.masksToBounds = true
		backgroundColor = .clear

		editorLayer = EditorMapLayer(owner: self,
		                             viewPort: viewPort,
		                             display: MessageDisplay.shared,
		                             progress: mainView)
		editorLayer.zPosition = ZLAYER.EDITOR.rawValue

		// implement crosshairs
		crossHairs = CrossHairsLayer(radius: 12.0)
		crossHairs.position = bounds.center()
		crossHairs.zPosition = ZLAYER.CROSSHAIRS.rawValue
		layer.addSublayer(crossHairs)

#if false
		voiceAnnouncement = VoiceAnnouncement()
		voiceAnnouncement?.mapView = self
		voiceAnnouncement?.radius = 30 // meters
#endif

		mainView.settings.$enableTurnRestriction.subscribe(self) { [weak self] _ in
			self?.editorLayer.clearCachedProperties()
		}

		currentRegion = RegionInfoForLocation.fromUserPrefs() ?? RegionInfoForLocation.none

		mapMarkerDatabase.mapData = editorLayer.mapData

		MainActor.runAfter(nanoseconds: 2000_000000) {
			self.updateCurrentRegionForLocationUsingCountryCoder()
			self.promptForBetterBackgroundImagery()
			self.checkForChangedTileOverlayLayers()
		}

		// get notes, etc.
		updateMapMarkersFromServer(withDelay: 1.0, including: [])
	}

	func acceptsFirstResponder() -> Bool {
		return true
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		bounds.origin = CGPoint(x: -frame.size.width / 2, y: -frame.size.height / 2)
		crossHairs.position = bounds.center()

		let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
		statusBarBackground.isHidden = windowScene?.statusBarManager?.isStatusBarHidden ?? false
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		if #available(iOS 13.0, *),
		   traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection),
		   let view = mainView.mapLayersView.basemapLayer as? MercatorTileLayer
		{
			view.updateDarkMode()
		}
	}

	// MARK: Utility

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
		mainView.mapLayersView.updateTileOverlayLayers(latLon: latLon)
		UserPrefs.shared.latestOverlayCheckLatLon.value = latLon.plist
	}

	private func promptForBetterBackgroundImagery() {
		if mainView.mapLayersView.aerialLayer.isHidden {
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
			mainView.setAerialTileServer(best)
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
			                              	self.mainView.setAerialTileServer(best)
			                              }))
			mainView.present(alert, animated: true)
		}

		UserPrefs.shared.latestAerialCheckLatLon.value = latLon.plist
	}

	func updateCurrentRegionForLocationUsingCountryCoder() {
		if editorLayer.isHidden {
			return
		}

		// if we moved a significant distance then check our location
		let latLon = viewPort.screenCenterLatLon()
		if GreatCircleDistance(latLon, currentRegion.latLon) < 10 * 1000 {
			return
		}

		currentRegion = CountryCoder.shared.regionInfoFor(latLon: latLon)
	}

	// MARK: ViewPort changed

	func mapTransformDidChange() {
		// we could move the blink outline similar to pushpin, but it's complicated and less important
		unblinkObject()

		// Determine if we've zoomed out enough to disable editing
		// We can only compute a precise surface area size at high zoom since it's possible
		// for the screen to be larger than the earth
		let area = viewPort.mapTransform.zoom() > 8
			? SurfaceAreaOfRect(viewPort.boundingLatLonForScreen())
			: Double.greatestFiniteMagnitude
		var isZoomedOut = area > 2.0 * 1000 * 1000
		if !editorLayer.isHidden,
		   !editorLayer.atVisibleObjectLimit,
		   area < 1000.0 * 1000 * 1000
		{
			isZoomedOut = false
		}
		mainView.viewState.zoomedOut = isZoomedOut

		updateCurrentRegionForLocationUsingCountryCoder()
		promptForBetterBackgroundImagery()
		checkForChangedTileOverlayLayers()

		// notify user if pushpin goes off-screen
		if let pushPin {
			let isInside = bounds.contains(pushPin.arrowPoint)
			if pushPinIsOnscreen,
			   !isInside,
			   !pushPin.isDragging
			{
				// generate feedback if the user scrolled the pushpin off the screen
				let feedback = UINotificationFeedbackGenerator()
				feedback.notificationOccurred(.warning)
			}
			pushPinIsOnscreen = isInside
		}

		// We moved to a new location so update markers
		updateMapMarkerButtonPositions()

		// This does a more expensive update, but debounced
		updateMapMarkersFromServer(withDelay: 0, including: [])
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
		let center = viewPort.mapTransform.screenPoint(forLatLon: rotateObjectCenter, birdsEye: true)
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
		objectRotationGesture.isEnabled = true
	}

	func endObjectRotation() {
		isRotateObjectMode?.rotateObjectOverlay.removeFromSuperlayer()
		placePushpinForSelection()
		editorLayer.dragState.confirmDrag = false
		isRotateObjectMode = nil
		objectRotationGesture.isEnabled = false
	}

	// MARK: Discard stale data

	func discardStaleData() {
		if mainView.settings.enableAutomaticCacheManagement {
			let changed = editorLayer.mapData.discardStaleData()
			if changed {
				MessageDisplay.shared.flashMessage(title: nil, message: NSLocalizedString("Cache trimmed", comment: ""))
				editorLayer.updateMapLocation() // download data if necessary
			}
		}
	}

	// MARK: Undo/Redo

	@IBAction func undo(_ sender: Any?) {
		if editorLayer.isHidden {
			MessageDisplay.shared.flashMessage(
				title: nil,
				message: NSLocalizedString("Editing layer not visible", comment: ""))
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
			MessageDisplay.shared.flashMessage(
				title: nil,
				message: NSLocalizedString("Editing layer not visible", comment: ""))
			return
		}
		removePin()
		editorLayer.redo()
	}

	// MARK: Key presses

	/// Offers the option to either merge tags or replace them with the copied tags.
	/// - Parameter sender: nil
	override func paste(_ sender: Any?) {
		editorLayer.pasteTags(string: nil)
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

	// UIPasteControl stops initializing itself correctly after the app has been in the
	// background several hours, so to get around this we instantiate UIPasteControl once
	// and reuse the same button as needed. We need light and dark versions of it because
	// the control doesn't update it's appearance dynamically when switching between modes.
	static func pasteButtonWith(style: UIUserInterfaceStyle) -> UIControl? {
		// Special case for paste button that accesses the clipboard
		if #available(iOS 16.0, *) {
			let trait = UITraitCollection(userInterfaceStyle: style)
			let bgColor = MapView.editToolbarBackgroundColor.resolvedColor(with: trait)
			let fgColor = MapView.editToolbarForegroundColor.resolvedColor(with: trait)

			let configuration = UIPasteControl.Configuration()
			configuration.baseBackgroundColor = bgColor
			configuration.baseForegroundColor = fgColor
			configuration.cornerStyle = .dynamic
			configuration.displayMode = .labelOnly
			let pasteButton = UIPasteControl(configuration: configuration)
			pasteButton.translatesAutoresizingMaskIntoConstraints = false
			pasteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
			pasteButton.setContentCompressionResistancePriority(.required, for: .vertical)
			pasteButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
			pasteButton.setContentHuggingPriority(.required, for: .vertical)
			return pasteButton
		} else {
			return nil
		}
	}

	static let editToolbarBackgroundColor = UIColor.systemBackground
	static let editToolbarForegroundColor = UIColor.label
	let editToolbarPasteButtonLight: UIView? = pasteButtonWith(style: .light)
	let editToolbarPasteButtonDark: UIView? = pasteButtonWith(style: .dark)

	// show/hide edit control based on selection
	func updateEditControl() {
		let show = pushPin != nil || editorLayer.selectedPrimary != nil
		editToolbar.isHidden = !show
		mainView.rulerView.isHidden = show
		if show {
			let backgroundColor = UIColor.systemBackground
			let foregroundColor = UIColor.label
			editToolbar.backgroundColor = backgroundColor
			if editorLayer.selectedPrimary == nil {
				// brand new node
				editControlActions = [.EDITTAGS, .ADDNOTE, .PASTETAGS]
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

			func editToolbarItemForAction(_ action: EDIT_ACTION) -> UIControl {
				if action == .PASTETAGS,
				   #available(iOS 16.0, *),
				   !ProcessInfo.processInfo.isMacCatalystApp
				{
					// Special case for paste that accesses the clipboard
					let pasteButton = traitCollection.userInterfaceStyle == .light
						? editToolbarPasteButtonLight as! UIPasteControl
						: editToolbarPasteButtonDark as! UIPasteControl
					pasteButton.target = editorLayer
					return pasteButton
				} else {
					let titleIcon = action.actionTitle(abbreviated: true)
					let button = ButtonClosure(type: .system)
					button.translatesAutoresizingMaskIntoConstraints = false
					button.setTitle(titleIcon.label, for: .normal)
					button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
					button.titleLabel?.adjustsFontForContentSizeCategory = true
					button.backgroundColor = backgroundColor
					button.setTitleColor(foregroundColor, for: .normal)
					button.layer.cornerRadius = editToolbar.layer.cornerRadius
					button.layer.masksToBounds = true
					button.setContentHuggingPriority(.defaultLow, for: .vertical)
					button.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
					button.backgroundColor = backgroundColor
					button.onTap = { [weak self] _ in
						self?.editorLayer.performEdit(action)
					}
					return button
				}
			}
			var actions: [UIView] = editControlActions.map {
				editToolbarItemForAction($0)
			}

			// add spacers between UIButtons (but not UIPasteControl since it provides it's own space
			var index = 0
			while index < actions.count - 1 {
				if actions[index] is UIButton, actions[index + 1] is UIButton {
					let spacer = UIView()
					spacer.translatesAutoresizingMaskIntoConstraints = false
					spacer.widthAnchor.constraint(equalToConstant: 12).isActive = true
					actions.insert(spacer, at: index + 1)
					index += 1 // Skip over the spacer
				}
				index += 1
			}
			let spacer1 = UIView()
			spacer1.translatesAutoresizingMaskIntoConstraints = false
			spacer1.widthAnchor.constraint(equalToConstant: 6).isActive = true
			actions.insert(spacer1, at: 0)
			let spacer2 = UIView()
			spacer2.translatesAutoresizingMaskIntoConstraints = false
			spacer2.widthAnchor.constraint(equalToConstant: 12).isActive = true
			actions.append(spacer2)

			editToolbar.controls = actions
		}
	}

	func presentEditActionSheet(_ sender: Any?) {
		let actionList = editorLayer.editActionsAvailable()
		if actionList.isEmpty {
			// nothing selected
			return
		}

		let actionSheet = CustomActionSheetController(title: nil, message: nil)
		for value in actionList {
			let titleIcon = value.actionTitle()
			actionSheet.addAction(title: titleIcon.label,
			                      image: titleIcon.image,
			                      handler: {
			                      	self.editorLayer.performEdit(value)
			                      })
		}
		actionSheet.addAction(title: NSLocalizedString("Cancel", comment: ""),
		                      image: nil,
		                      isCancel: true,
		                      handler: nil)
		mainView.present(actionSheet, animated: true)

		// compute location for action sheet to originate
		let trigger = editToolbar.controls.last!
		actionSheet.popoverPresentationController?.sourceView = trigger
		actionSheet.popoverPresentationController?.sourceRect = trigger.bounds
	}

	@IBAction func presentTagEditor(_ sender: Any?) {
		mainView.performSegue(withIdentifier: "poiSegue", sender: nil)
	}

	// Turn restriction panel
	func presentTurnRestrictionEditor() {
		guard let selectedPrimary = editorLayer.selectedPrimary,
		      let pushPin = pushPin
		else { return }

		func showRestrictionEditor() {
			guard
				let myVc = TurnRestrictController.instantiate()
			else { return }
			myVc.centralNode = editorLayer.selectedNode
			myVc.modalPresentationStyle = UIModalPresentationStyle.overCurrentContext
			mainView.present(myVc, animated: true)

			// if GPS is running don't keep moving around
			mainView.userOverrodeLocationPosition = true

			// ensure view is loaded before we access frame info
			myVc.loadViewIfNeeded()

			// scroll view so intersection stays visible
			let rc = myVc.viewWithTitle.frame
			let pt = pushPin.arrowPoint
			let delta = CGPoint(x: Double(bounds.midX - pt.x),
			                    y: Double(bounds.midY - rc.size.height / 2 - pt.y))
			viewPort.adjustOrigin(by: delta)
		}

		// check if this is a fancy relation type we don't support well
		func restrictionEditWarning(viaNode: OsmNode?) {
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
				alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
				                              style: .cancel,
				                              handler: nil))
				mainView.present(alert, animated: true)
			} else {
				showRestrictionEditor()
			}
		}

		// if we currently have a relation selected then select the via node instead

		if let relation = selectedPrimary as? OsmRelation {
			let fromWay = relation.member(byRole: "from")?.obj as? OsmWay
			guard
				let viaNode = relation.member(byRole: "via")?.obj as? OsmNode
			else {
				// not supported yet
				MessageDisplay.shared.showAlert(
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
				restrictionEditWarning(viaNode: editorLayer.selectedNode)
			}
		} else if selectedPrimary.isNode() != nil {
			restrictionEditWarning(viaNode: editorLayer.selectedNode)
		}
	}

	// MARK: PushPin

	func placePushpinForSelection(at point: CGPoint? = nil) {
		guard let selection = editorLayer.selectedPrimary
		else {
			removePin()
			return
		}

		// Make sure editor is visible
		switch mainView.viewState.state {
		case .AERIAL, .BASEMAP:
			mainView.viewState.state = .EDITORAERIAL
		case .EDITOR, .EDITORAERIAL:
			break
		}

		let loc: LatLon
		if let point = point {
			let latLon = viewPort.mapTransform.latLon(forScreenPoint: point)
			loc = selection.latLonOnObject(forLatLon: latLon)
		} else {
			loc = selection.selectionPoint()
		}

		let point = viewPort.mapTransform.screenPoint(forLatLon: loc, birdsEye: true)
		placePushpin(at: point, object: selection)

		if mainView.viewState.zoomedOut {
			// set location and zoom in
			viewPort.centerOn(latLon: loc, metersWide: 30.0)
		} else if !bounds.contains(pushPin!.arrowPoint) {
			// set location without changing zoom
			viewPort.centerOn(latLon: loc,
			                  zoom: nil,
			                  rotation: nil)
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

	// This function gets called by the pushpin when the user is dragging it.
	// If the pin is attached to an editor object we drag the object.
	// If the pin is being dragged off the edge of the
	// screen we scroll the screen to keep the pin in bounds.
	func onPushPinDrag(pushPin: PushPinView, state: UIPanGestureRecognizer.State,
	                   object: OsmBaseObject?,
	                   dx: Double, dy: Double)
	{
		switch state {
		case .ended, .cancelled, .failed:

			DisplayLink.shared.removeName("dragScroll")
			let isRotate = self.isRotateObjectMode != nil
			if isRotate {
				self.endObjectRotation()
			}
			self.unblinkObject()
			if let object {
				self.editorLayer.dragFinish(object: object, isRotate: isRotate)
			}
		case .began:
			self.editorLayer.dragBegin(from: pushPin.arrowPoint.minus(CGPoint(x: dx, y: dy)))
			fallthrough // begin state can have movement
		case .changed:
			// define the drag function
			func dragObjectToPushpin() {
				if let object {
					self.editorLayer.dragContinue(object: object,
					                              toPoint: pushPin.arrowPoint,
					                              isRotateObjectMode: self.isRotateObjectMode)
				}
			}

			// scroll screen if too close to edge
			let MinDistanceSide: CGFloat = 40.0
			let MinDistanceTop = MinDistanceSide + self.safeAreaInsets.top
			let MinDistanceBottom = MinDistanceSide + 120.0
			let arrow = pushPin.arrowPoint
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
				let center = viewPort.screenCenterPoint()
				let v = Sub(OSMPoint(arrow), OSMPoint(center)).unitVector()
				scrollx = SCROLL_SPEED * CGFloat(v.x)
				scrolly = SCROLL_SPEED * CGFloat(v.y)

				// scroll the screen to keep pushpin on-screen
				var prevTime = TimeInterval(CACurrentMediaTime())
				DisplayLink.shared.addName("dragScroll", block: { [self] in
					let now = TimeInterval(CACurrentMediaTime())
					let duration = now - prevTime
					prevTime = now
					// scale to 60 FPS assumption, need to move farther if framerate is slow
					let sx = scrollx * CGFloat(duration) * 60.0
					let sy = scrolly * CGFloat(duration) * 60.0
					self.viewPort.adjustOrigin(by: CGPoint(x: -sx, y: -sy))
					// because we moved the screen the pushpin is now back on-screen, but
					// for smooth continuous operation we put the pushpin back off-screen:
					let newArrowPoint = pushPin.arrowPoint.withOffset(sx, sy)
					pushPin.location = viewPort.mapTransform.latLon(forScreenPoint: newArrowPoint)

					// update position of blink layer
					if let pt = self.blinkLayer?.position.withOffset(-sx, -sy) {
						self.blinkLayer?.position = pt
					}
					dragObjectToPushpin()
					self.magnifyingGlass.setSourceCenter(arrow, in: self,
					                                     visible: !self.mainView.mapLayersView.aerialLayer.isHidden)
				})
			} else {
				DisplayLink.shared.removeName("dragScroll")
			}

			// move the object
			dragObjectToPushpin()
			self.magnifyingGlass.setSourceCenter(arrow, in: self,
			                                     visible: !self.mainView.mapLayersView.aerialLayer.isHidden)
		default:
			break
		}
	}

	func placePushpin(at point: CGPoint, object: OsmBaseObject?) {
		removePin()

		editorLayer.dragState.confirmDrag = false
		let pushpinView = PushPinView()
		pushpinView.viewPort = viewPort
		pushPin = pushpinView
		refreshPushpinText()
		pushpinView.location = viewPort.mapTransform.latLon(forScreenPoint: point)
		addSubview(pushpinView)

		pushpinView.dragCallback = { [weak self, weak object] pushPin, state, dx, dy in
			self?.onPushPinDrag(pushPin: pushPin, state: state, object: object, dx: dx, dy: dy)
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

			magnifyingGlass.setSourceCenter(pushpinView.arrowPoint, in: self,
			                                visible: !mainView.mapLayersView.aerialLayer.isHidden)
		}

		updateEditControl()
	}

	func refreshPushpinText() {
		let text = editorLayer.selectedPrimary?.friendlyDescription() ?? NSLocalizedString("(new object)", comment: "")
		pushPin?.text = text
	}

	var blinkObject: OsmBaseObject? // used for creating a moving dots animation during selection
	var blinkSegment = 0
	var blinkLayer: CAShapeLayer?

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
			let center = viewPort.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
			var rect = CGRect(x: center.x, y: center.y, width: 0, height: 0)
			rect = rect.insetBy(dx: -10, dy: -10)
			path.addEllipse(in: rect, transform: .identity)
		} else if let way = object as? OsmWay {
			if segment >= 0 {
				assert(way.nodes.count >= segment + 2)
				let n1 = way.nodes[segment]
				let n2 = way.nodes[segment + 1]
				let p1 = viewPort.mapTransform.screenPoint(forLatLon: n1.latLon, birdsEye: true)
				let p2 = viewPort.mapTransform.screenPoint(forLatLon: n2.latLon, birdsEye: true)
				path.move(to: CGPoint(x: p1.x, y: p1.y))
				path.addLine(to: CGPoint(x: p2.x, y: p2.y))
			} else {
				var isFirst = true
				for node in way.nodes {
					let pt = viewPort.mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
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
			if mainView.viewState.overlayMask.contains(.NOTES) {
				including.insert(.notes)
				including.insert(.fixme)
			}
			if mainView.viewState.overlayMask.contains(.QUESTS) {
				including.insert(.quest)
			}
			if mainView.settings.displayGpxTracks {
				including.insert(.gpx)
			}
			if mainView.mapLayersView.displayDataOverlayLayers {
				including.insert(.geojson)
			}
		} else if !mainView.viewState.overlayMask.contains(.QUESTS) {
			including.remove(.quest)
		}

		mapMarkerDatabase.updateRegion(withDelay: delay,
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
		let pos = viewPort.mapTransform.screenPoint(forLatLon: LatLon(latitude: marker.latLon.lat,
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
			let point = viewPort.mapTransform.screenPoint(forLatLon: pt, birdsEye: true)
			placePushpin(at: point, object: object)
		}

		if (marker is WayPointMarker) || (marker is KeepRightMarker) || (marker is GeoJsonMarker) {
			let comment: NSAttributedString
			let title: String
			switch marker {
			case let marker as WayPointMarker:
				title = "Waypoint"
				comment = marker.description
			case let marker as GeoJsonMarker:
				title = "GeoJSON"
				comment = NSAttributedString(string: marker.description)
			case let marker as KeepRightMarker:
				title = "Keep Right"
				comment = NSAttributedString(string: marker.description)
			default:
				title = ""
				comment = NSAttributedString(string: "")
			}

			let alert = AlertPopup(title: title, message: comment)
			if let marker = marker as? KeepRightMarker {
				alert.addAction(
					title: NSLocalizedString("Ignore", comment: ""),
					handler: { [self] in
						// they want to hide this button from now on
						marker.ignore()
						editorLayer.selectedNode = nil
						editorLayer.selectedWay = nil
						editorLayer.selectedRelation = nil
						removePin()
					})
			}
			mainView.present(alert, animated: true)
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
					mainView.present(vc, animated: true)
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
				mainView.present(alert, animated: true)
			}
		} else if let note = marker as? OsmNoteMarker {
			mainView.performSegue(withIdentifier: "NotesSegue", sender: note)
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
			viewPort.adjustOrigin(by: translation)
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
		if gestureRecognizer is UILongPressGestureRecognizer ||
			otherGestureRecognizer is UILongPressGestureRecognizer
		{
			// don't register long-press when other gestures are occuring
			return false
		}

		if gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer {
			// don't register taps during panning/zooming/rotating
			return false
		}

		return true
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
					let pt = viewPort.mapTransform.screenPoint(forLatLon: tapAndDragPushpinLatLon, birdsEye: true)
					placePushpinForSelection(at: pt)
				} else {
					removePin()
				}
				self.tapAndDragSelections = nil
			}
		case .changed:
			mainView.userOverrodeLocationZoom = true

			DisplayLink.shared.removeName(DisplayLinkPanning)

			let delta = tapAndDrag.translation(in: self)
			let scale = 1.0 - delta.y * 0.01
			let zoomCenter = viewPort.screenCenterPoint()
			viewPort.adjustZoom(by: scale, aroundScreenPoint: zoomCenter)
		case .ended:
			break
		default:
			break
		}
	}

	/// Invoked to select an object on the screen
	@objc func handleTapGesture(_ tap: UITapGestureRecognizer) {
		switch tap.state {
		case .ended:
			// we don't want the initial tap of a tap-and-drag to change object selection
			tapAndDragSelections = editorLayer.selections
			if let pushPin = pushPin {
				tapAndDragPushpinLatLon = viewPort.mapTransform.latLon(forScreenPoint: pushPin.arrowPoint)
			} else {
				tapAndDragPushpinLatLon = nil
			}

			// disable rotation if in action
			if isRotateObjectMode != nil {
				endObjectRotation()
			}

			let point = tap.location(in: self)
			if mainView.plusButtonTimestamp != 0.0 {
				// user is doing a long-press on + button
				editorLayer.addNode(at: point)
			} else {
				editorLayer.selectObjectAtPoint(point)
			}
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

	// user rotating an OSM object
	@IBAction func handleRotationGesture(_ rotationGesture: UIRotationGestureRecognizer) {
		guard let rotate = isRotateObjectMode else {
			return
		}
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
	}

	func updateSpeechBalloonPosition() {}
}

// MARK: EditorMapLayerOwner delegate methods

// EditorMap extensions
extension MapView: EditorMapLayerOwner {
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

	func useTurnRestrictions() -> Bool {
		return mainView.settings.enableTurnRestriction
	}

	func useUnnamedRoadHalo() -> Bool {
		return mainView.mapLayersView.noNameLayer() != nil
	}

	func useAutomaticCacheManagement() -> Bool {
		return mainView.settings.enableAutomaticCacheManagement
	}

	func pushpinView() -> PushPinView? {
		return pushPin
	}

	func addNote() {
		if let pushpinView = pushPin {
			let pos = viewPort.mapTransform.latLon(forScreenPoint: pushpinView.arrowPoint)
			let note = OsmNoteMarker(latLon: pos)
			mainView.performSegue(withIdentifier: "NotesSegue", sender: note)
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

extension MapView: MapLayersView.LayerOrView {
	var hasTileServer: TileServer? {
		return nil
	}

	func removeFromSuper() {
		removeFromSuperview()
	}
}
