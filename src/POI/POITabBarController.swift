//
//  POITabBarController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class POITabBarController: UITabBarController {
	var keyValueDict = [String: String]()
	var relationList: [OsmRelation] = []
	var selection: OsmBaseObject?
	var preservedFeatureTypeSearchText: String?
	var allAutocompleteTagKeys: [String] = []

	/// Identifies a tab when saving the user's preferred tab, since not all tabs are always present.
	private enum TabID: Int {
		case commonTags = 0
		case allTags = 1
		case attributes = 2
		case relations = 3
	}

	/// The tabs that are present, in the order they're displayed
	private var tabIDs: [TabID] = [.commonTags, .allTags, .attributes]

#if targetEnvironment(macCatalyst)
	/// One segmented control per tab, kept in sync, providing tab switching since the tab bar
	/// doesn't render inside a macCatalyst modal window (iOS 26 Liquid Glass regression).
	private var macSegControls: [UISegmentedControl] = []
#endif

	override func viewDidLoad() {
		super.viewDidLoad()

		let appDelegate = AppDelegate.shared
		let selection = appDelegate.mapView.selectedPrimary
		self.selection = selection
		keyValueDict = selection?.tags ?? [:]
		relationList = selection?.parentRelations ?? []

		rebuildAutocompleteTagKeys()

		if selection == nil {
			// don't show attributes page
			var vcList = viewControllers!
			vcList.removeLast()
			self.viewControllers = vcList
			tabIDs.removeLast()
		}
		if #available(iOS 15.0, *),
		   let selection,
		   selection is OsmRelation || !relationList.isEmpty
		{
			// show relations page after the other tabs
			let nav = UINavigationController(rootViewController: POIRelationsViewController())
			nav.tabBarItem = UITabBarItem(
				title: NSLocalizedString("Relations", comment: "Title of the page listing relation members"),
				image: UIImage(systemName: "point.3.connected.trianglepath.dotted"),
				selectedImage: nil)
			viewControllers?.append(nav)
			tabIDs.append(.relations)
		}
		selectedIndex = tabIDs.firstIndex(where: { $0.rawValue == UserPrefs.shared.poiTabIndex.value }) ?? 0

		// hide attributes tab on new objects
		updatePOIAttributesTabBarItemVisibility(withSelectedObject: selection)

#if targetEnvironment(macCatalyst)
		setupMacTabSwitcher()
		preferredContentSize = CGSize(width: 750, height: 620)
#else
		if #available(iOS 17, *) {
			// On iPad UITabBar may render incorrectly; forcing compact keeps it consistent.
			// See https://forums.developer.apple.com/forums/thread/759478
			traitOverrides.horizontalSizeClass = .compact
		}
#endif
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if isBeingDismissed {
			preservedFeatureTypeSearchText = nil
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		// make window resizable on MacCatalyst
		if let windowScene = view.window?.windowScene {
			windowScene.sizeRestrictions?.minimumSize = CGSize(width: 600, height: 450)
			windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 2000)
		}
	}

	private func rebuildAutocompleteTagKeys() {
		var keys = PresetsDatabase.shared.allTagKeys()
		keys.formUnion(AppDelegate.shared.mapView.mapData.tagKeys())
		let popularKeys = PresetsDatabase.shared.taginfoCache.popularKeys(count: 500) { [weak self] in
			self?.rebuildAutocompleteTagKeys()
		}
		keys.formUnion(popularKeys)
		allAutocompleteTagKeys = Array(keys)
	}

	func removeValueFromKeyValueDict(key: String) {
		keyValueDict.removeValue(forKey: key)
	}

	override var keyCommands: [UIKeyCommand]? {
		let esc = UIKeyCommand(
			input: UIKeyCommand.inputEscape,
			modifierFlags: [],
			action: #selector(escapeKeyPress(_:)))
		return [esc]
	}

	@objc func escapeKeyPress(_ keyCommand: UIKeyCommand?) {
		selectedViewController?.view.endEditing(true)
		selectedViewController?.dismiss(animated: true)
	}

	/// Hides the POI attributes tab bar item when the user is adding a new item, since it doesn't have any attributes yet.
	/// - Parameter selectedObject: The object that the user selected on the map.
	func updatePOIAttributesTabBarItemVisibility(withSelectedObject selectedObject: OsmBaseObject?) {
		let isAddingNewItem = selectedObject == nil
		if isAddingNewItem {
			// Remove the `POIAttributesViewController`.
			var viewControllersToKeep: [UIViewController] = []
			for controller in viewControllers ?? [] {
				if controller is UINavigationController,
				   (controller as? UINavigationController)?.viewControllers.first is POIAttributesViewController
				{
					// For new objects, the navigation controller that contains the view controller
					// for POI attributes is not needed; ignore it.
					return
				} else {
					viewControllersToKeep.append(controller)
				}
			}

			setViewControllers(viewControllersToKeep, animated: false)
		}
	}

	/// Dismiss ourself and reopen on a different object, such as a parent relation or a relation member.
	/// This isn't allowed if the current object has unsaved changes.
	func switchSelection(to object: OsmBaseObject, currentTags: [String: String]) {
		if isTagDictChanged(currentTags) {
			let alert = UIAlertController(
				title: NSLocalizedString("Object modified", comment: ""),
				message: NSLocalizedString(
					"You must save or discard changes to the current object before editing its associated relation",
					comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			present(alert, animated: true)
			return
		}

		let mapView = AppDelegate.shared.mapView!

		var newPoint = mapView.pushPin!.arrowPoint
		let latLon1 = mapView.viewPort.mapTransform.latLon(forScreenPoint: newPoint)
		let latLon = object.latLonOnObject(forLatLon: latLon1)

		newPoint = mapView.viewPort.mapTransform.screenPoint(forLatLon: latLon, birdsEye: true)
		if !mapView.bounds.contains(newPoint) {
			// new object is far away
			mapView.selectObject(object)
		} else {
			mapView.selectObject(object)
			mapView.placePushpin(at: newPoint, object: object)
		}

		// dismiss ourself and switch to the new object
		mapView.refreshPushpinText() // update pushpin description to the new object
		let presenter = presentingViewController
		dismiss(animated: true) {
			if let presenter {
				presenter.performSegue(withIdentifier: "poiSegue", sender: nil)
			}
		}
	}

	func setFeatureKey(_ key: String, value: String?) {
		if let value = value,
		   value.count > 0
		{
			keyValueDict[key] = value
		} else {
			keyValueDict.removeValue(forKey: key)
		}
	}

	func commitChanges() {
		AppDelegate.shared.mapView.setTagsForCurrentObject(tags: keyValueDict)
	}

	func isTagDictChanged(_ newDictionary: [String: String]) -> Bool {
		guard let tags = AppDelegate.shared.mapView.selectedPrimary?.tags
		else {
			// it's a brand new object
			return newDictionary.count > 0
		}
		return newDictionary != tags
	}

	func isTagDictChanged() -> Bool {
		return isTagDictChanged(keyValueDict)
	}

	override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
		guard
			let tabIndex = tabBar.items?.firstIndex(of: item),
			tabIndex != selectedIndex
		else { return }
		UserPrefs.shared.poiTabIndex.value = tabIDs[tabIndex].rawValue
		selectedIndex = tabIndex
	}

#if targetEnvironment(macCatalyst)
	/// Hides the native tab bar and installs a segmented control into each tab's navigation bar.
	private func setupMacTabSwitcher() {
		tabBar.isHidden = true

		let navControllers = viewControllers?.compactMap { $0 as? UINavigationController } ?? []
		let titles = tabBar.items?.map { $0.title ?? "" } ?? []

		macSegControls = navControllers.map { navVC in
			let seg = UISegmentedControl(items: titles)
			seg.selectedSegmentIndex = selectedIndex
			seg.addTarget(self, action: #selector(macSegmentChanged(_:)), for: .valueChanged)
			navVC.viewControllers.first?.navigationItem.titleView = seg
			return seg
		}
	}

	@objc private func macSegmentChanged(_ sender: UISegmentedControl) {
		let newIndex = sender.selectedSegmentIndex
		guard newIndex != selectedIndex else { return }
		selectedIndex = newIndex
		UserPrefs.shared.poiTabIndex.value = tabIDs[newIndex].rawValue
		// Keep all copies in sync so the correct tab is highlighted after switching.
		for seg in macSegControls {
			seg.selectedSegmentIndex = newIndex
		}
	}
#endif

	func tabButtonItems() -> [KeyboardToolbar.Item] {
		guard let items = tabBar.items else { return [] }
		return items.enumerated().compactMap { index, item in
			guard let image = item.image else { return nil }
			let displayImage = index == selectedIndex
				? image.withTintColor(.systemGray, renderingMode: .alwaysOriginal)
				: image.withRenderingMode(.alwaysTemplate)
			return .image(displayImage) { [weak self] _ in
				self?.view.window?.endEditing(true)
				self?.selectedIndex = index
			}
		}
	}
}
