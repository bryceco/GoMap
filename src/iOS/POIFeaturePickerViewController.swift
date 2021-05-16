//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  NewItemController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

//
//  NewItemController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

//  Converted to Swift 5.4 by Swiftify v5.4.24202 - https://swiftify.com/

import UIKit

protocol POITypeViewControllerDelegate: NSObjectProtocol {
    func typeViewController(_ typeViewController: POIFeaturePickerViewController?, didChangeFeatureTo feature: PresetFeature?)
}

private let MOST_RECENT_DEFAULT_COUNT = 5
private let MOST_RECENT_SAVED_MAXIMUM = 100

class FeaturePickerCell: UITableViewCell {
    var featureID: String?
    @IBOutlet var title: UILabel!
    @IBOutlet var details: UILabel!
    @IBOutlet var _image: UIImageView!
}

var mostRecentArray: NSMutableArray = []
var mostRecentMaximum: Int = 0
var logoCache: PersistentWebCache<UIImage>? // static so memory cache persists each time we appear

class POIFeaturePickerViewController: UITableViewController, UISearchBarDelegate {
    
    var _featureList: NSArray = []
    var _searchArrayRecent: NSArray = []
    var _searchArrayAll: NSArray = []
    @IBOutlet var _searchBar: UISearchBar!
    var _isTopLevel = false
    
    var parentCategory: PresetCategory?
    weak var delegate: POITypeViewControllerDelegate?
    
    class func loadMostRecent(forGeometry geometry: String) {
        let max = UserDefaults.standard.object(forKey: "mostRecentTypesMaximum") as? NSNumber
        mostRecentMaximum = (max != nil) ? (max?.intValue ?? 0) : MOST_RECENT_DEFAULT_COUNT
        
        let defaults: String = "mostRecentTypes.\(geometry)"
        let a: NSArray = (UserDefaults.standard.object(forKey: defaults) as? NSArray) ?? []
        mostRecentArray = NSMutableArray.init(capacity: (a.count + 1))
        for featureID in a {
            guard let featureID = featureID as? String else {
                continue
            }
            let feature = PresetsDatabase.shared.presetFeatureForFeatureID(featureID)
            if let feature = feature {
                mostRecentArray.add(feature)
            }
        }
    }
    
    func currentSelectionGeometry() -> String? {
        let tabController = tabBarController as? POITabBarController
        let selection = tabController?.selection
        var geometry = selection?.geometryName()
        if geometry == nil {
            geometry = GEOMETRY_NODE // a brand new node
        }
        return geometry
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if logoCache == nil {
            logoCache = PersistentWebCache<UIImage>(name: "presetLogoCache", memorySize: 5 * 1000000)
        }
        
        tableView.estimatedRowHeight = 44.0 // or could use UITableViewAutomaticDimension;
        tableView.rowHeight = UITableView.automaticDimension
        
        var geometry: String? = currentSelectionGeometry()
        if geometry == nil {
            geometry = GEOMETRY_NODE // a brand new node
        }
        if let geometry = geometry {
            POIFeaturePickerViewController.loadMostRecent(forGeometry: geometry)
        }
        
        if parentCategory == nil {
            _isTopLevel = true
            if let geometry = geometry {
                _featureList = NSArray.init(array: PresetsDatabase.shared.featuresAndCategoriesForGeometry(geometry))
            }
        } else {
            _featureList = NSArray.init(array: parentCategory!.members)
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return _isTopLevel ? 2 : 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if _isTopLevel {
            return section == 0 ? NSLocalizedString("Most recent", comment: "") : NSLocalizedString("All choices", comment: "")
        } else {
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if _isTopLevel && section == 1 {
            let countryCode = AppDelegate.shared?.mapView?.countryCodeForLocation
            let locale = NSLocale.current as NSLocale
            let countryName = locale.displayName(forKey: .countryCode, value: countryCode ?? "")
            
            if (countryCode?.count ?? 0) == 0 || (countryName?.count ?? 0) == 0 {
                // There's nothing to display.
                return nil
            }
            
            return String.localizedStringWithFormat(NSLocalizedString("Results for %@ (%@)", comment: "country name,2-character country code"), countryName ?? "", countryCode?.uppercased() ?? "")
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if _searchArrayAll.count != 0 {
            return section == 0 && _isTopLevel ? _searchArrayRecent.count : _searchArrayAll.count
        } else {
            if _isTopLevel && section == 0 {
                let count = mostRecentArray.count
                return count < mostRecentMaximum ? count : mostRecentMaximum
            } else {
                return _featureList.count
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var feature: PresetFeature? = nil
        if _searchArrayAll.count != 0 {
            feature = (indexPath.section == 0 && _isTopLevel) ? (_searchArrayRecent[indexPath.row] as? PresetFeature) : (_searchArrayAll[indexPath.row] as? PresetFeature)
        } else if _isTopLevel && indexPath.section == 0 {
            // most recents
            feature = mostRecentArray[indexPath.row] as? PresetFeature
        } else {
            // type array
            let tagInfo = _featureList[indexPath.row]
            if tagInfo is PresetCategory {
                let category = tagInfo as? PresetCategory
                let cell = tableView.dequeueReusableCell(withIdentifier: "SubCell", for: indexPath)
                cell.textLabel?.text = category?.friendlyName
                return cell
            } else {
                feature = tagInfo as? PresetFeature
            }
        }
        if (feature?.nsiSuggestion ?? false) && feature?.nsiLogo == nil && feature?.logoURL != nil {
#if false
            // use built-in logo files
            if feature?.nsiLogo == nil {
                feature?.nsiLogo = feature?.iconUnscaled()
                DispatchQueue.global(qos: .default).async(execute: { [self] in
                    var name = feature?.featureID.replacingOccurrences(of: "/", with: "_") ?? ""
                    name = "presets/brandIcons/" + name
                    let path = Bundle.main.path(forResource: name, ofType: "jpg") ?? Bundle.main.path(forResource: name, ofType: "png") ?? Bundle.main.path(forResource: name, ofType: "gif") ?? Bundle.main.path(forResource: name, ofType: "bmp") ?? nil
                    let _image = UIImage(contentsOfFile: path ?? "")
                    if let _image = _image {
                        DispatchQueue.main.async(execute: { [self] in
                            feature?.nsiLogo = _image
                            for cell in tableView.visibleCells {
                                guard let cell = cell as? FeaturePickerCell else {
                                    continue
                                }
                                if cell.featureID == feature?.featureID {
                                    cell._image._image = _image
                                }
                            }
                        })
                    }
                })
            }
#else
            feature?.nsiLogo = feature?.iconUnscaled()
            let logo = logoCache?.object(withKey: (feature?.featureID ?? ""), fallbackURL: {
                var returnUrl = NSURL()
#if true
                let name: String = feature?.featureID.replacingOccurrences(of: "/", with: "_") ?? ""
                let url: String = "http://gomaposm.com/brandIcons/" + name
                if let retURL = URL(string: url) {
                    returnUrl = retURL as NSURL
                }
#else
                if let retURL = URL(string: feature?.logoURL) {
                    returnUrl = retURL as NSURL
                }
#endif
                return returnUrl as URL
            }, objectForData: { data in
				if let image = UIImage(data: data) {
					return ImageScaledToSize(image, 60.0)
                } else {
					return UIImage()
                }
            }, completion: { image in
                if let image = image as? UIImage {
                    DispatchQueue.main.async(execute: {
                        feature?.nsiLogo = image
                        for cell in tableView.visibleCells {
                            guard let cell = cell as? FeaturePickerCell else {
                                continue
                            }
                            if cell.featureID == feature?.featureID {
                                cell._image.image = image
                            }
                        }
                    })
                }
            }) as? UIImage
            if logo != nil {
                feature?.nsiLogo = logo
            }
#endif
        }
        let brand: String = "☆ "
        let tabController = tabBarController as? POITabBarController
        let geometry: String = currentSelectionGeometry() ?? ""
        let currentFeature = PresetsDatabase.shared.matchObjectTagsToFeature(
            tabController?.keyValueDict,
            geometry: geometry,
            includeNSI: true)
        let cell = tableView.dequeueReusableCell(withIdentifier: "FinalCell", for: indexPath) as! FeaturePickerCell
        cell.title.text = (feature?.nsiSuggestion ?? false) ? (brand + (feature?.friendlyName() ?? "")) : feature?.friendlyName()
        cell._image.image = (feature?.nsiLogo != nil) && (feature?.nsiLogo != feature?.iconUnscaled())
            ? feature?.nsiLogo
            : feature?.iconUnscaled()?.withRenderingMode(.alwaysTemplate)
        if #available(iOS 13.0, *) {
            cell._image.tintColor = UIColor.label
        } else {
            cell._image.tintColor = UIColor.black
        }
        cell._image.contentMode = .scaleAspectFit
        cell.setNeedsUpdateConstraints()
        cell.details.text = feature?.summary()
        cell.accessoryType = currentFeature == feature ? .checkmark : .none
        cell.featureID = feature?.featureID
        return cell
    }
    
    class func updateMostRecentArray(withSelection feature: PresetFeature?, geometry: String?) {
        mostRecentArray.filter { NSPredicate(block: { f, bindings in
            return !((f as? PresetFeature)?.featureID == feature?.featureID)
        }).evaluate(with: $0) }
        if let feature = feature {
            mostRecentArray.insert(feature, at: 0)
        }
        if mostRecentArray.count > MOST_RECENT_SAVED_MAXIMUM {
            mostRecentArray.removeLastObject()
        }
        
        let a = NSMutableArray.init(capacity: mostRecentArray.count)
        for f in mostRecentArray {
            if let f = (f as? PresetFeature) {
                a.add(f.featureID)
            }
        }
        
        let defaults = "mostRecentTypes.\(geometry ?? "")"
        UserDefaults.standard.set(a, forKey: defaults)
    }
    
    func updateTags(with feature: PresetFeature?) {
        let geometry = currentSelectionGeometry() ?? ""
        delegate?.typeViewController(self, didChangeFeatureTo: feature)
        POIFeaturePickerViewController.updateMostRecentArray(withSelection: feature, geometry: geometry)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if _searchArrayAll.count != 0 {
            let feature = indexPath.section == 0 && _isTopLevel ? _searchArrayRecent[indexPath.row] : _searchArrayAll[indexPath.row]
            updateTags(with: feature as? PresetFeature)
            navigationController?.popToRootViewController(animated: true)
            return
        }
        
        if _isTopLevel && indexPath.section == 0 {
            // most recents
            let feature = mostRecentArray[indexPath.row]
            updateTags(with: feature as? PresetFeature)
            navigationController?.popToRootViewController(animated: true)
        } else {
            // type list
            let entry = _featureList[indexPath.row]
            if entry is PresetCategory {
                let category = entry as? PresetCategory
                let sub = storyboard?.instantiateViewController(withIdentifier: "PoiTypeViewController") as? POIFeaturePickerViewController
                sub?.parentCategory = category
                sub?.delegate = delegate
                _searchBar.resignFirstResponder()
                if let sub = sub {
                    navigationController?.pushViewController(sub, animated: true)
                }
            } else {
                let feature = entry as? PresetFeature
                updateTags(with: feature)
                navigationController?.popToRootViewController(animated: true)
            }
        }
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.count == 0 {
            // no search
            _searchArrayAll = []
            _searchArrayRecent = []
        } else {
            // searching
            let geometry = currentSelectionGeometry() ?? ""
            let results = PresetsDatabase.shared.featuresInCategory(parentCategory, matching: searchText, geometry: geometry)
            _searchArrayAll = results as NSArray
            _searchArrayRecent = mostRecentArray.filtered(using: NSPredicate(block: { feature, bindings in
                return (feature as? PresetFeature)?.matchesSearchText(searchText, geometry: geometry) ?? false
            })) as NSArray
        }
        tableView.reloadData()
    }
    
    @IBAction func configure(_ sender: Any) {
        let alert = UIAlertController(title: NSLocalizedString("Show Recent Items", comment: ""), message: NSLocalizedString("Number of recent items to display", comment: ""), preferredStyle: .alert)
        alert.addTextField(configurationHandler: { textField in
            textField.keyboardType = .numberPad
            textField.text = String(format: "%ld", Int(mostRecentMaximum))
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { action in
            let textField = alert.textFields?[0]
            var count = Int(textField?.text ?? "") ?? 0
            if count < 0 {
                count = 0
            } else if count > 99 {
                count = 99
            }
            mostRecentMaximum = count
            UserDefaults.standard.set(mostRecentMaximum, forKey: "mostRecentTypesMaximum")
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        present(alert, animated: true)
    }
    
    @IBAction func back(_ sender: Any) {
        dismiss(animated: true)
    }
}
