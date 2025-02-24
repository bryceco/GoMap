//
//  POIAttributesViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

private
enum ROW: Int {
	case identifier = 0
	case user
	case uid
	case modified
	case version
	case changeset
}

private
enum SectionType: Int {
	case metadata
	case extraInfo
	case wayNodes
}

class AttributeCustomCell: UITableViewCell {
	@IBOutlet var title: UILabel!
	@IBOutlet var value: UITextField!
}

class POIAttributesViewController: UITableViewController {
	@IBOutlet var saveButton: UIBarButtonItem!

	override func viewDidLoad() {
		super.viewDidLoad()

		let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary
		title = object is OsmNode ? NSLocalizedString("Node Attributes", comment: "")
			: object is OsmWay ? NSLocalizedString("Way Attributes", comment: "")
			: object is OsmRelation ? NSLocalizedString("Relation Attributes", comment: "")
			: NSLocalizedString("Attributes", comment: "node/way/relation attributes")
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		let tabController = tabBarController as? POITabBarController
		saveButton.isEnabled = tabController?.isTagDictChanged() ?? false
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		guard let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary else {
			return 0
		}
		switch object {
		case is OsmNode:
			return 2
		case is OsmWay:
			return 3
		case is OsmRelation:
			return 1
		default:
			return 0
		}
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		guard let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary else { return 0 }

		switch SectionType(rawValue: section) {
		case .metadata:
			return 6
		case .extraInfo:
			switch object {
			case is OsmNode:
				return 1 // longitude/latitude
			case let way as OsmWay:
				return way.isClosed() ? 2 : 1
			case is OsmRelation:
				return 0
			default:
				return 0
			}
		case .wayNodes:
			if let way = object as? OsmWay {
				return way.nodes.count
			}
			return 0
		default:
			return 0
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! AttributeCustomCell
		cell.accessoryType = .none

		guard let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary,
		      let section = SectionType(rawValue: indexPath.section)
		else {
			// should never happen (but it has)
			cell.title.text = nil
			cell.value.text = nil
			return cell
		}

		switch section {
		case .metadata:
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
				cell.value.text = DateFormatter.localizedString(
					from: dateForTimestamp,
					dateStyle: .medium,
					timeStyle: .short)
			case ROW.version.rawValue:
				cell.title.text = NSLocalizedString("Version", comment: "OSM object versioh")
				cell.value.text = "\(object.version)"
				cell.accessoryType = object.ident > 0 ? .disclosureIndicator : .none
			case ROW.changeset.rawValue:
				cell.title.text = NSLocalizedString("Changeset", comment: "OSM changeset identifier")
				cell.value.text = "\(object.changeset)"
				cell.accessoryType = object.ident > 0 ? .disclosureIndicator : .none
			default:
				assertionFailure()
			}
		case .extraInfo:
			switch object {
			case let node as OsmNode:
				cell.title.text = NSLocalizedString("Lat/Lon", comment: "coordinates")
				cell.value.text = "\(node.latLon.lat),\(node.latLon.lon)"
			case let way as OsmWay:
				switch indexPath.row {
				case 0:
					// length
					let len = way.lengthInMeters()
					let nodes = way.nodes.count
					cell.title.text = NSLocalizedString("Length", comment: "")
					cell.value.text = len >= 10
						? String.localizedStringWithFormat(
							NSLocalizedString("%ld meters, %ld nodes", comment: "way length if > 10m"),
							Int(len),
							nodes)
						: String.localizedStringWithFormat(
							NSLocalizedString("%.1f meters, %ld nodes", comment: "way length if < 10m"),
							len,
							nodes)
					cell.accessoryType = .none
				case 1:
					// area (only if closed way)
					let area = way.areaInSquareMeters()
					cell.title.text = NSLocalizedString("Area", comment: "Area of an object in m^2")
					cell.value.text = String.localizedStringWithFormat(
						NSLocalizedString("%.0f m^2", comment: "area in m^2"), area)
				case 2:
					// building
					cell.title.text = NSLocalizedString("Building", comment: "The object is a building")
					cell.value.text = object.tags["building"]
					cell.accessoryType = .disclosureIndicator
				default:
					break
				}
			case is OsmRelation:
				break
			default:
				assertionFailure()
			}
		case .wayNodes:
			let way = object as! OsmWay
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
		guard let object = AppDelegate.shared.mapView.editorLayer.selectedPrimary,
		      let section = SectionType(rawValue: indexPath.section)
		else {
			return
		}

		let urlString: String
		switch section {
		case .metadata:
			guard let row = ROW(rawValue: indexPath.row) else {
				return
			}
			switch row {
			case .identifier:
				let type = object.osmType.string
				let ident = object.ident
				urlString = "\(OSM_SERVER.serverURL)\(type)/\(ident)"
			case .user:
				urlString = "\(OSM_SERVER.serverURL)user/\(object.user)"
			case .version:
				let type = object.osmType.string
				let ident = object.ident
				urlString = "\(OSM_SERVER.serverURL)\(type)/\(ident)/history"
			case .changeset:
				urlString = "\(OSM_SERVER.serverURL)changeset/\(object.changeset)"
			case .uid, .modified:
				return
			}
		default:
			return
		}

		if let encodedUrlString = urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed),
		   let url = URL(string: encodedUrlString)
		{
			let safariViewController = SFSafariViewController(url: url)
			present(safariViewController, animated: true)
		}
	}

	override func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
		// Allow the user to copy the latitude/longitude
		return indexPath.section != SectionType.metadata.rawValue
	}

	override func tableView(
		_ tableView: UITableView,
		canPerformAction action: Selector,
		forRowAt indexPath: IndexPath,
		withSender sender: Any?) -> Bool
	{
		if indexPath.section != SectionType.metadata.rawValue,
		   action == #selector(copy(_:))
		{
			// Allow users to copy latitude/longitude.
			return true
		}
		return false
	}

	override func tableView(
		_ tableView: UITableView,
		performAction action: Selector,
		forRowAt indexPath: IndexPath,
		withSender sender: Any?)
	{
		guard let cell = tableView.cellForRow(at: indexPath),
		      let customCell = cell as? AttributeCustomCell
		else {
			// For cells other than `AttributeCustomCell`, we don't know how to get the value.
			return
		}

		if indexPath.section != SectionType.metadata.rawValue,
		   action == #selector(copy(_:))
		{
			UIPasteboard.general.string = customCell.value.text
		}
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	@IBAction func done(_ sender: Any) {
		dismiss(animated: true)

		if let tabController = tabBarController as? POITabBarController {
			tabController.commitChanges()
		}
	}
}
