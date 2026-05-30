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

	override func viewDidLoad() {
		super.viewDidLoad()

		let appDelegate = AppDelegate.shared
		let selection = appDelegate.mapView.selectedPrimary
		self.selection = selection
		keyValueDict = selection?.tags ?? [:]
		relationList = selection?.parentRelations ?? []

		let hideAttributesTab = Self.shouldHideAttributesTab(for: selection)
		var tabIndex = UserPrefs.shared.poiTabIndex.value ?? 0
		if hideAttributesTab, tabIndex == 2 {
			tabIndex = 0
		}
		if hideAttributesTab {
			removeAttributesTabFromViewControllers()
		}
		selectedIndex = tabIndex

		if #available(iOS 17, *) {
			// On MacCatalyst (and maybe iPad) UITabBar is broken.
			// This fixes it.
			// See https://forums.developer.apple.com/forums/thread/759478
			traitOverrides.horizontalSizeClass = .compact
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		// make window resizable on MacCatalyst
		if let windowScene = view.window?.windowScene {
			windowScene.sizeRestrictions?.minimumSize = CGSize(width: 400, height: 300)
			windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 2000)
		}
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

	/// Attributes are only useful for objects that exist on the server (positive OSM id).
	private static func shouldHideAttributesTab(for selection: OsmBaseObject?) -> Bool {
		guard let selection else { return true }
		return selection.ident < 0
	}

	private func removeAttributesTabFromViewControllers() {
		var vcList = viewControllers ?? []
		guard vcList.count > 2 else { return }
		vcList.removeLast()
		viewControllers = vcList
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
		UserPrefs.shared.poiTabIndex.value = tabIndex
		slideTabTo(tabIndex: tabIndex)
	}

	// Do a sliding animation of the views
	func slideTabTo(tabIndex: Int) {
		guard let newVC = viewControllers?[tabIndex],
		      let fromView = selectedViewController?.view,
		      let toView = newVC.view else { return }
		let moveRight = selectedIndex < tabIndex
		let screenWidth = UIScreen.main.bounds.width
		toView.frame.origin.x = moveRight ? screenWidth : -screenWidth

		view.addSubview(toView)

		UIView.animate(withDuration: 0.3, animations: {
			fromView.frame.origin.x = moveRight ? -screenWidth : screenWidth
			toView.frame.origin.x = 0
		}) { _ in
			fromView.removeFromSuperview()
			self.selectedViewController = newVC
		}
	}
}
