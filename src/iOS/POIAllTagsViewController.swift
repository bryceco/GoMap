//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  POICustomTagsViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

class TextPairTableCell: UITableViewCell {
    @IBOutlet var text1: AutocompleteTextField!
    @IBOutlet var text2: AutocompleteTextField!
    @IBOutlet var infoButton: UIButton!
    
    override func willTransition(to state: UITableViewCell.StateMask) {
        super.willTransition(to: state)
        
        // don't allow editing text while deleting
        if (state.rawValue != 0) && ((UITableViewCell.StateMask.showingEditControl.rawValue != 0) || (UITableViewCell.StateMask.showingDeleteConfirmation.rawValue != 0)) {
            text1.resignFirstResponder()
            text2.resignFirstResponder()
        }
    }
}

class POIAllTagsViewController: UITableViewController {
    var tags: [AnyHashable]?
    var relations: [AnyHashable]?
    var members: [AnyHashable]?
    @IBOutlet var _saveButton: UIBarButtonItem!
    var childViewPresented = false
    var featureID: String?
    var currentTextField: UITextField?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let editButton = editButtonItem
        editButton.target = self
        editButton.action = #selector(toggleTableRowEditing(_:))
        navigationItem.rightBarButtonItems = [navigationItem.rightBarButtonItem, editButton].compactMap { $0 }
        
        let tabController = tabBarController as? POITabBarController
        
        if tabController?.selection?.isNode() != nil {
            title = NSLocalizedString("Node Tags", comment: "")
        } else if tabController?.selection?.isWay() != nil {
            title = NSLocalizedString("Way Tags", comment: "")
        } else if tabController?.selection?.isRelation() != nil {
            var type = tabController?.keyValueDict["type"]
            if (type?.count ?? 0) != 0 {
                type = type?.replacingOccurrences(of: "_", with: " ")
                type = type?.capitalized
                title = "\(type ?? "") Tags"
            } else {
                title = NSLocalizedString("Relation Tags", comment: "")
            }
        } else {
            title = NSLocalizedString("All Tags", comment: "")
        }
    }
    
    deinit {
    }
    
    // return -1 if unchanged, else row to set focus
    func updateWithRecomendations(forFeature forceReload: Bool) -> Int {
        let tabController = tabBarController as? POITabBarController
        let geometry = tabController?.selection?.geometryName() ?? GEOMETRY_NODE
        let dict = keyValueDictionary()
        let newFeature = PresetsDatabase.shared.matchObjectTagsToFeature(
            dict,
            geometry: geometry,
            includeNSI: true)
        
        if !forceReload && (newFeature?.featureID == featureID) {
            return -1
        }
        featureID = newFeature?.featureID
        
        // remove all entries without key & value
        tags?.filter { NSPredicate(block: { kv, bindings in
            return (kv?[0].count ?? 0) != 0 && (kv?[1].count ?? 0) != 0
        }).evaluate(with: $0) }
        
        let nextRow = tags?.count ?? 0
        
        // add new cell ready to be edited
        tags?.append(["", ""])
        
        // add placeholder keys
        if let newFeature = newFeature {
            let presets = PresetsForFeature(withFeature: newFeature, objectTags: dict, geometry: geometry, update: nil)
            var newKeys: [AnyHashable] = []
            for section in 0..<presets.sectionCount() {
                for row in 0..<presets.tagsInSection(section) {
                    let preset = presets.presetAtSection(section, row: row)
                    if preset is PresetGroup {
                        let group = preset as? PresetGroup
                        if let presetKeys = group?.presetKeys {
                            for presetKey in presetKeys {
                                guard let presetKey = presetKey as? PresetKey else {
                                    continue
                                }
                                if presetKey.tagKey.count == 0 {
                                    continue
                                }
                                newKeys.append(presetKey.tagKey)
                            }
                        }
                    } else {
                        let presetKey = preset as? PresetKey
                        if presetKey?.tagKey.count == 0 {
                            continue
                        }
                        if let tagKey = presetKey?.tagKey {
                            newKeys.append(tagKey)
                        }
                    }
                }
            }
            newKeys.filter { NSPredicate(block: { [self] key, bindings in
                for kv in tags ?? [] {
                    guard let kv = kv as? [String] else {
                        continue
                    }
                    if kv[0] == key {
                        return false
                    }
                }
                return true
            }).evaluate(with: $0) }
            newKeys = (newKeys as NSArray).sortedArray(options: [], usingComparator: { p1, p2 in
                return p1.compare(p2 ?? "") ?? ComparisonResult.orderedSame
            }) as? [AnyHashable] ?? newKeys
            for key in newKeys {
                guard let key = key as? String else {
                    continue
                }
                tags?.append([key, ""])
            }
        }
        
        tableView.reloadData()
        
        return nextRow
    }
    
    func loadState() {
        let tabController = tabBarController as? POITabBarController
        
        // fetch values from tab controller
        tags = [AnyHashable](repeating: 0, count: tabController?.keyValueDict.count ?? 0)
        relations = tabController?.relationList
        members = tabController?.selection?.isRelation() ? (tabController?.selection as? OsmRelation)?.members : nil
        
        tabController?.keyValueDict.enumerateKeysAndObjects({ [self] tag, value, stop in
            tags?.append([tag, value])
        })
        
        tags = (tags as NSArray?)?.sortedArray(comparator: { obj1, obj2 in
            let tag1 = obj1?[0] as? String
            let tag2 = obj2?[0] as? String
            let tiger1 = tag1?.hasPrefix("tiger:") ?? false || tag1?.hasPrefix("gnis:") ?? false
            let tiger2 = tag2?.hasPrefix("tiger:") ?? false || tag2?.hasPrefix("gnis:") ?? false
            if tiger1 == tiger2 {
                return tag1?.compare(tag2 ?? "") ?? ComparisonResult.orderedSame
            } else {
                return tiger1 - tiger2
            }
        }) as? [AnyHashable] ?? tags
        
        updateWithRecomendations(forFeature: true)
        
        _saveButton.isEnabled = tabController?.isTagDictChanged() ?? false
        if #available(iOS 13.0, *) {
            tabBarController?.isModalInPresentation = _saveButton.isEnabled
        }
    }
    
    func saveState() {
        let tabController = tabBarController as? POITabBarController
        tabController?.keyValueDict = keyValueDictionary()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if childViewPresented {
            childViewPresented = false
        } else {
            loadState()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        saveState()
        super.viewWillDisappear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let tabController = tabBarController as? POITabBarController
        if tabController?.selection == nil {
            let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? TextPairTableCell
            if cell?.text1.text.length == 0 && cell?.text2.text?.count == 0 {
                cell?.text1.becomeFirstResponder()
            }
        }
    }
    
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if #available(macCatalyst 13,*) {
            // On Mac Catalyst set the focus to something other than a text field (which brings up the keyboard)
            // The Cancel button would be ideal but it isn't clear how to implement that, so select the Add button instead
            if false {
                let indexPath = IndexPath(row: tags?.count ?? 0, section: 0)
                let cell = tableView.cellForRow(at: indexPath) as? AddNewCell
                if cell?.button {
                    return [cell?.button].compactMap { $0 }
                }
            }
        }
        return []
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        let tabController = tabBarController as? POITabBarController
        if ((tabController?.selection?.isRelation()) != nil) {
            return 3
        } else if (relations?.count ?? 0) > 0 {
            return 2
        } else {
            return 1
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return NSLocalizedString("Tags", comment: "")
        } else if section == 1 {
            return NSLocalizedString("Relations", comment: "")
        } else {
            return NSLocalizedString("Members", comment: "")
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 2 {
            return NSLocalizedString("You can navigate to a relation member only if it is already downloaded.\nThese members are marked with '>'.", comment: "")
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            // tags
            return tags?.count ?? 0
        } else if section == 1 {
            // relations
            return relations?.count ?? 0
        } else {
            if EDIT_RELATIONS {
                return (members?.count ?? 0) + 1
            } else {
                return members?.count ?? 0
            }
        }
    }
    
    // MARK: Accessory buttons
    
    func getAssociatedColor(for cell: TextPairTableCell?) -> UIView? {
        if (cell?.text1.text == "colour") || (cell?.text1.text == "color") || cell?.text1.text?.hasSuffix(":colour") ?? false || cell?.text1.text?.hasSuffix(":color") ?? false {
            let color = Colors.cssColorForColorName(cell?.text2.text)
            if let color = color {
                var size = cell?.text2.bounds.size.height ?? 0.0
                size = CGFloat(round(Double(size * 0.5)))
                let square = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
                square.backgroundColor = color
                square.layer.borderColor = UIColor.black.cgColor
                square.layer.borderWidth = 1.0
                let view = UIView(frame: CGRect(x: 0, y: 0, width: size + 6, height: size))
                view.backgroundColor = UIColor.clear
                view.addSubview(square)
                return view
            }
        }
        return nil
    }
    
    @IBAction func openWebsite(_ sender: Any) {
        var pair = sender as? TextPairTableCell
        while pair != nil && !(pair is UITableViewCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        
        var string: String? = nil
        if (pair?.text1.text == "wikipedia") || pair?.text1.text?.hasSuffix(":wikipedia") ?? false {
            let a = pair?.text2.text?.components(separatedBy: ":")
            let lang = a?[0].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
            let page = a?[1].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
            string = "https://\(lang ?? "").wikipedia.org/wiki/\(page ?? "")"
        } else if (pair?.text1.text == "wikidata") || pair?.text1.text?.hasSuffix(":wikidata") ?? false {
            let page = pair?.text2.text?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
            string = "https://www.wikidata.org/wiki/\(page ?? "")"
        } else if pair?.text2.text?.hasPrefix("http://") ?? false || pair?.text2.text?.hasPrefix("https://") ?? false {
            string = pair?.text2.text
        }
        if let string = string {
            let url = URL(string: string)
            if let url = url {
                let viewController = SFSafariViewController(url: url)
                present(viewController, animated: true)
            } else {
                let alert = UIAlertController(
                    title: NSLocalizedString("Invalid URL", comment: ""),
                    message: nil,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                present(alert, animated: true)
            }
        }
    }
    
    func getWebsiteButton(for cell: TextPairTableCell?) -> UIView? {
        if (cell?.text1.text == "wikipedia") || (cell?.text1.text == "wikidata") || cell?.text1.text.hasSuffix(":wikipedia") ?? false || cell?.text1.text.hasSuffix(":wikidata") ?? false || cell?.text2.text?.hasPrefix("http://") ?? false || cell?.text2.text.hasPrefix("https://") ?? false {
            let button = UIButton(type: .system)
            button.layer.borderWidth = 2.0
            button.layer.borderColor = UIColor.systemBlue.cgColor
            button.layer.cornerRadius = 15.0
            button.setTitle("🔗", for: .normal)
            
            button.addTarget(self, action: #selector(openWebsite(_:)), for: .touchUpInside)
            return button
        }
        return nil
    }
    
    @IBAction func setSurveyDate(_ sender: Any) {
        var pair = sender as? TextPairTableCell
        while pair != nil && !(pair is UITableViewCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        dateFormatter.timeZone = NSTimeZone.local
        let text = dateFormatter.string(from: now)
        pair?.text2.text = text
        textFieldChanged(pair?.text2)
        textFieldEditingDidEnd(pair?.text2)
    }
    
    func getSurveyDateButton(for cell: TextPairTableCell?) -> UIView? {
        let synonyms = [
            "check_date",
            "survey_date",
            "survey:date",
            "survey",
            "lastcheck",
            "last_checked",
            "updated"
        ]
        if synonyms.contains(cell?.text1.text ?? "") {
            let button = UIButton(type: .contactAdd)
            button.addTarget(self, action: #selector(setSurveyDate(_:)), for: .touchUpInside)
            return button
        }
        return nil
    }
    
    @IBAction func setDirection(_ sender: Any) {
        var pair = sender as? TextPairTableCell
        while pair != nil && !(pair is UITableViewCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        let directionViewController = DirectionViewController(
            key: pair?.text1.text ?? "",
            value: pair?.text2.text,
            setValue: { [self] newValue in
                pair?.text2.text = newValue
                textFieldChanged(pair?.text2)
                textFieldEditingDidEnd(pair?.text2)
            })
        childViewPresented = true
        
        present(directionViewController, animated: true)
    }
    
    func getDirectionButton(for cell: TextPairTableCell?) -> UIView? {
        let synonyms = [
            "direction",
            "camera:direction"
        ]
        if synonyms.contains(cell?.text1.text ?? "") {
            let button = UIButton(type: .contactAdd)
            button.addTarget(self, action: #selector(setDirection(_:)), for: .touchUpInside)
            return button
        }
        return nil
    }
    
    @IBAction func setHeight(_ sender: Any) {
        var pair = sender as? TextPairTableCell
        while pair != nil && !(pair is UITableViewCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        
        if HeightViewController.unableToInstantiate(withUserWarning: self) {
            return
        }
        
        let vc = HeightViewController.instantiate()
        vc?.callback = { [self] newValue in
            pair?.text2.text = newValue
            textFieldChanged(pair?.text2)
            textFieldEditingDidEnd(pair?.text2)
        }
        if let vc = vc {
            present(vc, animated: true)
        }
        childViewPresented = true
    }
    
    func getHeightButton(for cell: TextPairTableCell?) -> UIView? {
        if cell?.text1.text == "height" {
            let button = UIButton(type: .contactAdd)
            button.addTarget(self, action: #selector(setHeight(_:)), for: .touchUpInside)
            return button
        }
        return nil
    }
    
    func updateAssociatedContent(for cell: TextPairTableCell?) {
        let associatedView = getAssociatedColor(for: cell) ?? getWebsiteButton(for: cell) ?? getSurveyDateButton(for: cell) ?? getDirectionButton(for: cell) ?? getHeightButton(for: cell)
        
        cell?.text2.rightView = associatedView
        cell?.text2.rightViewMode = associatedView != nil ? .always : .never
    }
    
    @IBAction func infoButtonPressed(_ button: UIButton?) {
        var cell = button?.superview as? TextPairTableCell
        while cell != nil && !(cell is UITableViewCell) {
            cell = cell?.superview as? TextPairTableCell
        }
        
        // show OSM wiki page
        let key = cell?.text1.text
        let value = cell?.text2.text
        if (key?.count ?? 0) == 0 {
            return
        }
        let presetLanguages = PresetLanguages()
        let languageCode = presetLanguages.preferredLanguageCode
        
        let progress = UIActivityIndicatorView(style: .gray)
        progress.frame = cell?.infoButton.bounds ?? CGRect.zero
        cell?.infoButton.addSubview(progress)
        cell?.infoButton.isEnabled = false
        cell?.infoButton.titleLabel?.layer.opacity = 0.0
        progress.startAnimating()
        WikiPage.shared().bestWikiPage(forKey: key, value: value, language: languageCode()) { [self] url in
            progress.removeFromSuperview()
            cell?.infoButton.isEnabled = true
            cell?.infoButton.titleLabel?.layer.opacity = 1.0
            if url != nil && view.window != nil {
                var viewController: SFSafariViewController? = nil
                if let url = url {
                    viewController = SFSafariViewController(url: url)
                }
                childViewPresented = true
                if let viewController = viewController {
                    present(viewController, animated: true)
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            
            // Tags
            let cell = tableView.dequeueReusableCell(withIdentifier: "TagCell", for: indexPath) as? TextPairTableCell
            let kv = tags?[indexPath.row] as? [AnyHashable]
            // assign text contents of fields
            cell?.text1.isEnabled = true
            cell?.text2.isEnabled = true
            cell?.text1.text = kv?[0]
            cell?.text2.text = kv?[1]
            
            updateAssociatedContent(for: cell)
            
            weak var weakCell = cell
            cell?.text1.didSelectAutocomplete = {
                weakCell?.text2.becomeFirstResponder()
            }
            cell?.text2.didSelectAutocomplete = {
                weakCell?.text2.resignFirstResponder()
            }
            
            return cell!
        } else if indexPath.section == 1 {
            
            // Relations
            if indexPath.row == (relations?.count ?? 0) {
                let cell = tableView.dequeueReusableCell(withIdentifier: "AddCell", for: indexPath)
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "RelationCell", for: indexPath) as? TextPairTableCell
            cell?.text1.isEnabled = false
            cell?.text2.isEnabled = false
            let relation = relations?[indexPath.row] as? OsmRelation
            if let ident = relation?.ident {
                cell?.text1.text = "\(ident)"
            }
            cell?.text2.text = relation?.friendlyDescription()
            
            return cell!
        } else {
            
            // Members
            let member = members?[indexPath.row] as? OsmMember
            let isResolved = member?.ref is OsmBaseObject
            let cell = (isResolved
                            ? tableView.dequeueReusableCell(withIdentifier: "RelationCell", for: indexPath)
                            : tableView.dequeueReusableCell(withIdentifier: "MemberCell", for: indexPath)) as? TextPairTableCell
            if EDIT_RELATIONS {
                cell?.text1.isEnabled = true
                cell?.text2.isEnabled = true
            } else {
                cell?.text1.isEnabled = false
                cell?.text2.isEnabled = false
            }
            if member is OsmMember {
                let ref = member?.ref
                var memberName: String? = nil
                if let type = member?.type, let ref1 = member?.ref {
                    memberName = (ref is OsmBaseObject) ? ref?.friendlyDescriptionWithDetails : "\(type) \(ref1)"
                }
                cell?.text1.text = member?.role
                cell?.text2.text = memberName
            } else {
                let values = member as? [AnyHashable]
                cell?.text1.text = values?[0]
                cell?.text2.text = values?[1]
            }
            
            return cell
        }
    }
    
    func keyValueDictionary() -> [String : String] {
        var dict = [String : String](minimumCapacity: (tags?.count ?? 0))
        for kv in tags ?? [] {
            guard let kv = kv as? [AnyHashable] else {
                continue
            }
            
            // strip whitespace around text
            var key = kv[0] as? String
            var val = kv[1] as? String
            
            key = key?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            val = val?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if (key?.count ?? 0) != 0 && (val?.count ?? 0) != 0 {
                dict[key] = val
            }
        }
        return dict
    }
    
    // MARK: Tab key
    
    override var keyCommands: [UIKeyCommand]? {
        let forward = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabNext(_:)))
        let backward = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(tabPrevious(_:)))
        return [forward, backward]
    }
    
    // MARK: TextField delegate
    
    @IBAction func textFieldReturn(_ sender: Any) {
        var cell = sender as? TextPairTableCell
        while cell != nil && !(cell is UITableViewCell) {
            cell = cell?.superview as? TextPairTableCell
        }
        
        sender.resignFirstResponder()
        updateWithRecomendations(forFeature: true)
    }
    
    @IBAction func textFieldEditingDidBegin(_ textField: AutocompleteTextField?) {
        currentTextField = textField
        
        var pair = textField?.superview as? TextPairTableCell
        while pair != nil && !(pair is UITableViewCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        var indexPath: IndexPath? = nil
        if let pair = pair {
            indexPath = tableView.indexPath(for: pair)
        }
        
        if indexPath?.section == 0 {
            
            let isValue = textField == pair?.text2
            var kv = tags?[indexPath?.row ?? 0] as? [AnyHashable]
            
            if isValue {
                // get list of values for current key
                let key = kv?[0] as? String
                if PresetsDatabase.shared.eligible(forAutocomplete: key) {
                    let set = PresetsDatabase.shared.allTagValues(forKey: key)
                    let appDelegate = AppDelegate.shared
                    var values = appDelegate?.mapView?.editorLayer.mapData.tagValues(forKey: key)
                    values?.formUnion(Set(Array(set)))
                    let list = Array(values)
                    textField?.autocompleteStrings = list
                }
            } else {
                // get list of keys
                let set = PresetsDatabase.shared.allTagKeys()
                let list = Array(set)
                textField?.autocompleteStrings = list
            }
        }
    }
    
    func convertWikiUrlToReference(withKey key: String?, value url: String?) -> String? {
        if key?.hasPrefix("wikipedia") ?? false {
            // if the value is for wikipedia then convert the URL to the correct format
            // format is https://en.wikipedia.org/wiki/Nova_Scotia
            let scanner = Scanner(string: url ?? "")
            var languageCode: String?
            var pageName: String?
            if (scanner.scanString("https://", into: nil) || scanner.scanString("http://", into: nil)) && scanner.scanUpTo(".", into: AutoreleasingUnsafeMutablePointer<NSString?>(mutating: &languageCode)) && (scanner.scanString(".m", into: nil) || true) && scanner.scanString(".wikipedia.org/wiki/", into: nil) && scanner.scanUpTo("/", into: AutoreleasingUnsafeMutablePointer<NSString?>(mutating: &pageName)) && scanner.isAtEnd && (languageCode?.count ?? 0) == 2 && (pageName?.count ?? 0) > 0 {
                return "\(languageCode ?? ""):\(pageName ?? "")"
            }
        } else if key?.hasPrefix("wikidata") ?? false {
            // https://www.wikidata.org/wiki/Q90000000
            let scanner = Scanner(string: url ?? "")
            var pageName: String?
            if (scanner.scanString("https://", into: nil) || scanner.scanString("http://", into: nil)) && (scanner.scanString("www.wikidata.org/wiki/", into: nil) || scanner.scanString("m.wikidata.org/wiki/", into: nil)) && scanner.scanUpTo("/", into: AutoreleasingUnsafeMutablePointer<NSString?>(mutating: &pageName)) && scanner.isAtEnd && (pageName?.count ?? 0) > 0 {
                return pageName
            }
        }
        return nil
    }
    
    func textFieldEditingDidEnd(_ textField: UITextField?) {
        var pair = textField?.superview as? TextPairTableCell
        while pair != nil && !(pair is UITableViewCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        
        var indexPath: IndexPath? = nil
        if let pair = pair {
            indexPath = tableView.indexPath(for: pair)
        }
        if indexPath?.section == 0 {
            var kv = tags?[indexPath?.row ?? 0] as? [String]
            
            updateAssociatedContent(for: pair)
            
            if (kv?[0].count ?? 0) != 0 && (kv?[1].count ?? 0) != 0 {
                
                // do wikipedia conversion
                let newValue = convertWikiUrlToReference(withKey: kv?[0], value: kv?[1])
                if let newValue = newValue {
                    kv?[1] = newValue
                    pair?.text2.text = newValue
                }
                
                // move the edited row up
                for i in 0..<(indexPath?.row ?? 0) {
                    let a = tags?[i] as? [String]
                    if (a?[0].count ?? 0) == 0 || (a?[1].count ?? 0) == 0 {
                        tags?.remove(at: indexPath?.row ?? 0)
                        if let kv = kv {
                            tags?.insert(kv, at: i)
                        }
                        if let indexPath = indexPath {
                            tableView.moveRow(at: indexPath, to: IndexPath(row: i, section: 0))
                        }
                        break
                    }
                }
                
                // if we created a row that defines a key that duplicates a row witht the same key elsewhere then delete the other row
                for i in 0..<(tags?.count ?? 0) {
                    let a = tags?[i] as? [String]
                    if a != kv && (a?[0] == kv?[0]) {
                        tags?.remove(at: i)
                        tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .none)
                    }
                }
                
                // update recommended tags
                let nextRow = updateWithRecomendations(forFeature: false)
                if nextRow >= 0 {
                    // a new feature was defined
                    let newPath = IndexPath(row: nextRow, section: 0)
                    tableView.scrollToRow(at: newPath, at: .middle, animated: false)
                    
                    // move focus to next empty cell
                    let nextCell = tableView.cellForRow(at: newPath) as? TextPairTableCell
                    nextCell?.text1.becomeFirstResponder()
                }
            } else if (kv?[0].count ?? 0) != 0 || (kv?[1].count ?? 0) != 0 {
                
                // ensure there's a blank line either elsewhere, or create one below us
                var haveBlank = false
                for a in tags ?? [] {
                    guard let a = a as? [String] else {
                        continue
                    }
                    haveBlank = a != kv && a[0].count == 0 && a[1].count == 0
                    if haveBlank {
                        break
                    }
                }
                if !haveBlank {
                    let newPath = IndexPath(row: (indexPath?.row ?? 0) + 1, section: indexPath?.section ?? 0)
                    tags?.insert(["", ""], at: newPath.row)
                    tableView.insertRows(at: [newPath], with: .none)
                }
            }
        }
    }
    
    @IBAction func textFieldChanged(_ textField: UITextField?) {
        var cell = textField?.superview as? UITableViewCell
        while cell != nil && !(cell is UITableViewCell) {
            cell = cell?.superview as? UITableViewCell
        }
        var indexPath: IndexPath? = nil
        if let cell = cell {
            indexPath = tableView.indexPath(for: cell)
        }
        
        let tabController = tabBarController as? POITabBarController
        
        if indexPath?.section == 0 {
            // edited tags
            let pair = cell as? TextPairTableCell
            var kv = tags?[indexPath?.row ?? 0] as? [AnyHashable]
            let isValue = textField == pair?.text2
            
            if isValue {
                // new value
                kv?[1] = textField?.text
            } else {
                // new key name
                kv?[0] = textField?.text
            }
            
            var dict = keyValueDictionary()
            _saveButton.isEnabled = tabController?.isTagDictChanged(dict) ?? false
            if #available(iOS 13.0, *) {
                tabBarController?.isModalInPresentation = _saveButton.isEnabled
            }
        }
    }
    
    func tab(toNext forward: Bool) {
        var pair = currentTextField?.superview as? TextPairTableCell
        while pair != nil && !(pair is TextPairTableCell) {
            pair = pair?.superview as? TextPairTableCell
        }
        if pair == nil {
            return
        }
        
        var indexPath: IndexPath? = nil
        if let pair = pair {
            indexPath = tableView.indexPath(for: pair)
        }
        var field: UITextField? = nil
        if forward {
            if currentTextField == pair?.text1 {
                field = pair?.text2
            } else {
                let max = tableView(tableView, numberOfRowsInSection: indexPath?.section ?? 0)
                let row = ((indexPath?.row ?? 0) + 1) % max
                indexPath = IndexPath(row: row, section: indexPath?.section ?? 0)
                if let indexPath = indexPath {
                    pair = tableView.cellForRow(at: indexPath) as? TextPairTableCell
                }
                field = pair?.text1
            }
        } else {
            if currentTextField == pair?.text2 {
                field = pair?.text1
            } else {
                let max = tableView(tableView, numberOfRowsInSection: indexPath?.section ?? 0)
                let row = ((indexPath?.row ?? 0) - 1 + max) % max
                indexPath = IndexPath(row: row, section: indexPath?.section ?? 0)
                if let indexPath = indexPath {
                    pair = tableView.cellForRow(at: indexPath) as? TextPairTableCell
                }
                field = pair?.text2
            }
        }
        field?.becomeFirstResponder()
        currentTextField = field
    }
    
    @objc func tabPrevious(_ sender: Any?) {
        tab(toNext: false)
    }
    
    @objc func tabNext(_ sender: Any?) {
        tab(toNext: true)
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.frame.size.width, height: 44))
        toolbar.items = [
            UIBarButtonItem(title: NSLocalizedString("Previous", comment: ""), style: .plain, target: self, action: #selector(tabPrevious(_:))),
            UIBarButtonItem(title: NSLocalizedString("Next", comment: ""), style: .plain, target: self, action: #selector(tabNext(_:)))
        ]
        textField.inputAccessoryView = toolbar
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let MAX_LENGTH = 255
        let oldLength = textField.text?.count ?? 0
        let replacementLength = string.count
        let rangeLength = range.length
        let newLength = oldLength - rangeLength + replacementLength
        let returnKey = (string as NSString).range(of: "\n").location != NSNotFound
        return newLength <= MAX_LENGTH || returnKey
    }
    
    // MARK: - Table view delegate
    
    @IBAction func toggleTableRowEditing(_ sender: Any) {
        let tabController = tabBarController as? POITabBarController
        
        let editing = !tableView.isEditing
        navigationItem.leftBarButtonItem?.isEnabled = !editing
        navigationItem.rightBarButtonItem?.isEnabled = !editing && tabController?.isTagDictChanged()
        tableView.setEditing(editing, animated: true)
        let button = sender as? UIBarButtonItem
        button?.title = editing ? NSLocalizedString("Done", comment: "") : NSLocalizedString("Edit", comment: "")
        button?.style = editing ? .done : .plain
    }
    
    // Don't allow deleting the "Add Tag" row
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 0 {
            return indexPath.row < (tags?.count ?? 0)
        } else if indexPath.section == 1 {
            // don't allow editing relations here
            return false
        } else {
            if EDIT_RELATIONS {
                return indexPath.row < (members?.count ?? 0)
            } else {
                return false
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            let tabController = tabBarController as? POITabBarController
            if indexPath.section == 0 {
                let kv = tags?[indexPath.row] as? [AnyHashable]
                let tag = kv?[0] as? String
                tabController?.removeValueFromKeyValueDict(withKey: tag)
                //			[tabController.keyValueDict removeObjectForKey:tag];
                tags?.remove(at: indexPath.row)
            } else if indexPath.section == 1 {
                relations?.remove(at: indexPath.row)
            } else {
                members?.remove(at: indexPath.row)
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            _saveButton.isEnabled = tabController?.isTagDictChanged() ?? false
            if #available(iOS 13.0, *) {
                tabBarController?.isModalInPresentation = _saveButton.isEnabled
            }
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }
    }
    
    @IBAction func cancel(_ sender: Any) {
        view.endEditing(true)
        
        dismiss(animated: true)
    }
    
    @IBAction func done(_ sender: Any) {
        dismiss(animated: true)
        saveState()
        
        let tabController = tabBarController as? POITabBarController
        tabController?.commitChanges()
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        // don't allow switching to relation if current selection is modified
        let tabController = tabBarController as? POITabBarController
        var dict = keyValueDictionary()
        if tabController?.isTagDictChanged(dict) {
            let alert = UIAlertController(
                title: NSLocalizedString("Object modified", comment: ""),
                message: NSLocalizedString("You must save or discard changes to the current object before editing its associated relation", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
            present(alert, animated: true)
            return false
        }
        
        // switch to relation or relation member
        let cell = sender as? UITableViewCell
        var indexPath: IndexPath? = nil
        if let cell = cell {
            indexPath = tableView.indexPath(for: cell)
        }
        var object: OsmBaseObject? = nil
        if indexPath?.section == 1 {
            // change the selected object in the editor to the relation
            object = relations?[indexPath?.row ?? 0] as? OsmBaseObject
        } else if indexPath?.section == 2 {
            let member = members?[indexPath?.row ?? 0] as? OsmMember
            object = member?.ref
            if !(object is OsmBaseObject) {
                return false
            }
        } else {
            return false
        }
        let mapView = AppDelegate.shared?.mapView
        mapView?.editorLayer.selectedNode = object?.isNode()
        mapView?.editorLayer.selectedWay = object?.isWay()
        mapView?.editorLayer.selectedRelation = object?.isRelation()
        
        var newPoint = mapView?.pushpinView.arrowPoint ?? .zero
        let clLatLon = mapView?.longitudeLatitude(forScreenPoint: newPoint, birdsEye: true)
        var latLon = OSMPoint(x: (clLatLon?.longitude ?? 0.0), y: (clLatLon?.latitude ?? 0.0))
        if let point = object?.pointOnObject(for: latLon) {
            latLon = point
        }
        newPoint = mapView?.screenPoint(forLatitude: latLon.y, longitude: latLon.x, birdsEye: true) ?? .zero
        if !(mapView?.bounds.contains(newPoint) ?? false) {
            // new object is far away
            mapView?.placePushpinForSelection()
        } else {
            mapView?.placePushpin(at: newPoint, object: object)
        }
        
        // dismiss ourself and switch to the relation
        let topController = mapView?.mainViewController
        mapView?.refreshPushpinText() // update pushpin description to the relation
        dismiss(animated: true) {
            topController?.performSegue(withIdentifier: "poiSegue", sender: nil)
        }
        return false
    }
}

let EDIT_RELATIONS = 0
