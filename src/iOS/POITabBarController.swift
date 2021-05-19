//
//  POITabBarController.swift
//  Go Map!!
//
//  Created by Ibrahim Hassan on 17/03/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

@objcMembers
class POITabBarController: UITabBarController {
    var keyValueDict = [String : String]()
    var relationList: [AnyHashable]?
    var selection: OsmBaseObject?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func removeValueFromKeyValueDict(key: String) {
        keyValueDict.removeValue(forKey: key)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let appDelegate = AppDelegate.shared
        let selection = appDelegate?.mapView?.editorLayer.selectedPrimary
        self.selection = selection
        relationList = [AnyHashable]()
        if let selection = selection {
            for (key, obj) in selection.tags {
                keyValueDict[key] = obj
            }
            relationList = selection.parentRelations
        }
        
        let tabIndex = UserDefaults.standard.integer(forKey: "POITabIndex")
        selectedIndex = tabIndex
        
        // hide attributes tab on new objects
        updatePOIAttributesTabBarItemVisibility(withSelectedObject: selection)
    }
    
    override var keyCommands: [UIKeyCommand]? {
        let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeKeyPress(_:)))
        return [esc]
    }
    
    @objc func escapeKeyPress(_ keyCommand: UIKeyCommand?) {
        let vc = selectedViewController
        vc?.view.endEditing(true)
        vc?.dismiss(animated: true)
    }
    
    /// Hides the POI attributes tab bar item when the user is adding a new item, since it doesn't have any attributes yet.
    /// - Parameter selectedObject: The object that the user selected on the map.
    func updatePOIAttributesTabBarItemVisibility(withSelectedObject selectedObject: OsmBaseObject?) {
        let isAddingNewItem = selectedObject == nil
        if isAddingNewItem {
            // Remove the `POIAttributesViewController`.
            var viewControllersToKeep: [UIViewController] = []
            for controller in self.viewControllers ?? [] {
                if (controller is UINavigationController) && ((controller as? UINavigationController)?.viewControllers.first is POIAttributesViewController) {
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

    func setFeatureKey(_ key: String?, value: String?) {
        if let key = key {
            if let value = value {
                keyValueDict[key] = value
            } else {
                keyValueDict.removeValue(forKey: key)
            }
        }
    }

    func commitChanges() {
        let appDelegate = AppDelegate.shared
        appDelegate?.mapView?.setTagsForCurrentObject(keyValueDict)
    }
    
    func isTagDictChanged(_ newDictionary: [String : String]?) -> Bool {
        let appDelegate = AppDelegate.shared
        
        let tags = appDelegate?.mapView?.editorLayer.selectedPrimary.tags
        if tags?.count == 0 {
            return newDictionary?.count != 0
        }
        
        return !(newDictionary == tags)
    }

    func isTagDictChanged() -> Bool {
        return isTagDictChanged(keyValueDict)
    }
    
    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let tabIndex = tabBar.items?.firstIndex(of: item) ?? NSNotFound
        UserDefaults.standard.set(tabIndex, forKey: "POITabIndex")
    }
}
