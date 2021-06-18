//
//  POIAttributesViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

fileprivate
enum ROW : Int {
    case identifier = 0
    case user
    case uid
    case modified
    case version
    case changeset
}

fileprivate
enum SectionType : Int {
    case metadata
    case nodeLatlon
    case wayExtra
    case wayNodes
    
    func getRawValue() -> Int {
        switch self {
        case .metadata:
            return 0
        case .nodeLatlon:
            return 1
        case .wayExtra:
            return 1
        case .wayNodes:
            return 2
        }
    }
}

class AttributeCustomCell: UITableViewCell {
	@IBOutlet var title: UILabel!
	@IBOutlet var value: UITextField!
}

class POIAttributesViewController: UITableViewController {
    @IBOutlet var _saveButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let appDelegate = AppDelegate.shared
        let object = appDelegate.mapView.editorLayer.selectedPrimary
        title = object?.isNode != nil
            ? NSLocalizedString("Node Attributes", comment: "")
            : object?.isWay != nil
            ? NSLocalizedString("Way Attributes", comment: "")
            : object?.isRelation != nil
            ? NSLocalizedString("Relation Attributes", comment: "")
            : NSLocalizedString("Attributes", comment: "node/way/relation attributes")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let tabController = tabBarController as? POITabBarController
        _saveButton.isEnabled = tabController?.isTagDictChanged() ?? false
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary
        return object?.isNode != nil ? 2 : object?.isWay != nil ? 3 : 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary else { return 0 }
        
        if section == SectionType.metadata.getRawValue() {
            return 6
        }
		if object.isNode() != nil {
            if section == SectionType.nodeLatlon.getRawValue() {
                return 1 // longitude/latitude
            }
        } else if let way = object.isWay() {
			if section == SectionType.wayExtra.getRawValue() {
                return 1
            } else if section == SectionType.wayNodes.getRawValue() {
                return way.nodes.count // all nodes
            }
        }
        return 0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let appDelegate = AppDelegate.shared
		let object = appDelegate.mapView!.editorLayer.selectedPrimary!
        
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! AttributeCustomCell
		cell.accessoryType = .none
        
        if indexPath.section == SectionType.metadata.getRawValue() {
            
            switch indexPath.row {
            case ROW.identifier.rawValue:
                cell.title.text = NSLocalizedString("Identifier", comment: "OSM node/way/relation identifier")
				cell.value.text = "\(object.ident)"
                cell.accessoryType = object.ident > 0 ? .disclosureIndicator : .none
            case ROW.user.rawValue:
                cell.title.text = NSLocalizedString("User", comment: "OSM user name")
                cell.value.text = object.user
                cell.accessoryType = object.user.count > 0 ? .disclosureIndicator : .none
            case ROW.uid.rawValue:
                cell.title.text = NSLocalizedString("UID", comment: "OSM numeric user ID")
                cell.value.text = "\(object.uid)"
            case ROW.modified.rawValue:
                cell.title.text = NSLocalizedString("Modified", comment: "last modified date")
				let dateForTimestamp = object.dateForTimestamp()
				cell.value.text = DateFormatter.localizedString(from: dateForTimestamp, dateStyle: .medium, timeStyle: .short)
            case ROW.version.rawValue:
                cell.title.text = NSLocalizedString("Version", comment: "OSM object versioh")
                cell.value.text = "\(object.version)"
                cell.accessoryType = object.ident > 0 ? .disclosureIndicator : .none
            case ROW.changeset.rawValue:
                cell.title.text = NSLocalizedString("Changeset", comment: "OSM changeset identifier")
                cell.value.text = "\(object.changeset)"
                cell.accessoryType = object.ident > 0 ? .disclosureIndicator : .none
			default:
                assert(false)
            }
        } else if let node = object.isNode() {
            if indexPath.section == SectionType.nodeLatlon.getRawValue() {
				cell.title.text = NSLocalizedString("Lat/Lon", comment: "coordinates")
				cell.value.text = "\(node.latLon.latitude),\(node.latLon.longitude)"
            }
        } else if let way = object.isWay() {
            if indexPath.section == SectionType.wayExtra.getRawValue() {
                let len = way.lengthInMeters()
                let nodes = way.nodes.count
                cell.title.text = NSLocalizedString("Length", comment: "")
                cell.value.text = len >= 10
                    ? String.localizedStringWithFormat(NSLocalizedString("%.0f meters, %ld nodes", comment: "way length if > 10m"), len, nodes)
                    : String.localizedStringWithFormat(NSLocalizedString("%.1f meters, %ld nodes", comment: "way length if < 10m"), len, nodes)
                cell.accessoryType = .none
            } else if indexPath.section == SectionType.wayNodes.getRawValue() {
                let node = way.nodes[indexPath.row]
                cell.title.text = NSLocalizedString("Node", comment: "")
                var name = node.friendlyDescription()
                if !name.hasPrefix("(") {
					name = "\(name) (\(node.ident))"
                } else {
					name = "\(node.ident)"
                }
                cell.value.text = name
            }
        } else {
            // shouldn't be here
            assert(false)
        }
        // do extra work so keyboard won't display if they select a value
        let value = cell.value
        value?.inputView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if let cell = tableView.cellForRow(at: indexPath),
		   cell.accessoryType == .none
		{
			return nil
        }
        return indexPath
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary
        if object == nil {
            return
        }
        
        var urlString: String? = nil
        
        if indexPath.row == ROW.identifier.rawValue {
            let type = object?.isNode != nil ? "node" : object?.isWay != nil ? "way" : object?.isRelation != nil ? "relation" : "?"
            if let ident = object?.ident {
                urlString = "https://www.openstreetmap.org/browse/\(type)/\(ident)"
            }
        } else if indexPath.row == ROW.user.rawValue {
            if let user = object?.user {
                urlString = "https://www.openstreetmap.org/user/\(user)"
            }
        } else if indexPath.row == ROW.version.rawValue {
            let type = object?.isNode != nil ? "node" : object?.isWay != nil ? "way" : object?.isRelation != nil ? "relation" : "?"
            if let ident = object?.ident {
                urlString = "https://www.openstreetmap.org/browse/\(type)/\(ident)/history"
            }
        } else if indexPath.row == ROW.changeset.rawValue {
            urlString = String(format: "https://www.openstreetmap.org/browse/changeset/%ld", Int(object?.changeset ?? 0))
        }
        
        if let urlString = urlString {
            let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)
            let url = URL(string: encodedUrlString ?? "")
            
            var safariViewController: SFSafariViewController? = nil
            if let url = url {
                safariViewController = SFSafariViewController(url: url)
            }
            if let safariViewController = safariViewController {
                present(safariViewController, animated: true)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        // Allow the user to copy the latitude/longitude
        return indexPath.section != SectionType.metadata.getRawValue()
    }
    
    override func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        if indexPath.section != SectionType.metadata.getRawValue() && action == #selector(copy(_:)) {
            // Allow users to copy latitude/longitude.
            return true
        }
        
        return false
    }
    
    override func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        let cell = tableView.cellForRow(at: indexPath)
        if !(cell is AttributeCustomCell) {
            // For cells other than `AttributeCustomCell`, we don't know how to get the value.
            return
        }
        
        let customCell = cell as? AttributeCustomCell
        
        if indexPath.section != SectionType.metadata.getRawValue() && action == #selector(copy(_:)) {
            UIPasteboard.general.string = customCell?.value.text
        }
    }
    
    @IBAction func cancel(_ sender: Any) {
        dismiss(animated: true)
    }
    
    @IBAction func done(_ sender: Any) {
        dismiss(animated: true)
        
        let tabController = tabBarController as? POITabBarController
        tabController?.commitChanges()
    }
}
