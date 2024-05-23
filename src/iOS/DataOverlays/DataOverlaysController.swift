//
//  UserDataController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/19/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

class UserDataTableCell: UITableViewCell {
	@IBOutlet var title: UILabel!
	@IBOutlet var onOff: UISwitch!
}

class DataOverlaysController: UITableViewController {
	enum Section: Int {
		case geojsonSection = 0
		case predefinedSection = 1
	}

	var overlayList: [TileServer] = []
	var overlaySelections: [String] = []

	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.rightBarButtonItem = editButtonItem
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		let mapView = AppDelegate.shared.mapView!
		let latLon = mapView.screenCenterLatLon()
		overlayList = mapView.tileServerList.allServices(at: latLon, overlay: true)
		overlaySelections = UserPrefs.shared.object(forKey: .tileOverlaySelections) as? [String] ?? []
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		if AppDelegate.shared.mapView.displayDataOverlayLayer {
			AppDelegate.shared.mapView.dataOverlayLayer.setNeedsLayout()
		}
	}

	// MARK: Table view delegate

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 2
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		switch Section(rawValue: section) {
		case .geojsonSection:
			return "GeoJSON"
		case .predefinedSection:
			return "Predefined"
		default:
			return nil
		}
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		switch Section(rawValue: section) {
		case .geojsonSection:
			return geoJsonList.count + 1
		case .predefinedSection:
			return overlayList.count
		default:
			return 0
		}
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		switch Section(rawValue: indexPath.section) {
		case .geojsonSection:
			if indexPath.row < geoJsonList.count {
				let cell = tableView.dequeueReusableCell(withIdentifier: "UserDataTableCell", for: indexPath)
					as! UserDataTableCell
				let entry = geoJsonList[indexPath.row]
				cell.title?.text = entry.url.lastPathComponent
				cell.onOff.isOn = entry.visible
				return cell
			} else {
				let cell = tableView.dequeueReusableCell(withIdentifier: "ImportCell", for: indexPath)
				return cell
			}
		case .predefinedSection:
			let server = overlayList[indexPath.row]
			let cell = tableView.dequeueReusableCell(withIdentifier: "UserDataTableCell", for: indexPath)
				as! UserDataTableCell
			cell.title?.text = server.name
			cell.onOff.isOn = overlaySelections.contains(server.name)

			return cell
		default:
			return UITableViewCell(frame: .zero)
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)

		if Section(rawValue: indexPath.section) == .geojsonSection,
		   indexPath.row == geoJsonList.count
		{
			if #available(iOS 14.0, *) {
				doImport()
			} else {
				// Fallback on earlier versions
			}
		}
	}

	@IBAction func didToggleSwitch(_ sender: Any) {
		guard let cell: UserDataTableCell = (sender as? UIView)?.superviewOfType(),
		      let indexPath = tableView.indexPath(for: cell)
		else { return }
		switch Section(rawValue: indexPath.section) {
		case .geojsonSection:
			geoJsonList.toggleVisible(indexPath.row)
		case .predefinedSection:
			let server = overlayList[indexPath.row]
			if cell.onOff.isOn {
				overlaySelections.append(server.name)
			} else {
				overlaySelections.removeAll(where: { $0 == server.name })
			}
			UserPrefs.shared.set(object: overlaySelections, forKey: .tileOverlaySelections)
			AppDelegate.shared.mapView.updateTileOverlayLayers()
		default:
			fatalError()
		}
	}

	// MARK: Edit rows

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if Section(rawValue: indexPath.section) == .geojsonSection,
		   indexPath.row < geoJsonList.count
		{
			return true
		}
		return false
	}

	override func tableView(
		_ tableView: UITableView,
		commit editingStyle: UITableViewCell.EditingStyle,
		forRowAt indexPath: IndexPath)
	{
		if editingStyle == .delete {
			// Delete the row from the data source
			guard let cell = tableView.cellForRow(at: indexPath) as? UserDataTableCell,
			      let indexPath = tableView.indexPath(for: cell),
			      Section(rawValue: indexPath.section) == .geojsonSection
			else {
				return
			}
			geoJsonList.remove(indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .automatic)
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
		geoJsonList.move(from: fromIndexPath.row,
		                 to: toIndexPath.row)
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		if indexPath.row < geoJsonList.count {
			return true
		}
		return false
	}
}

// MARK: Import

extension DataOverlaysController: UIDocumentPickerDelegate {
	@available(iOS 14.0, *)
	func doImport() {
		guard let utType = UTType("public.geojson") else { return }
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: [utType], asCopy: true)
		picker.delegate = self
		picker.allowsMultipleSelection = true
		present(picker, animated: true)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController,
	                    didPickDocumentsAt urls: [URL])
	{
		for url in urls {
			do {
				try geoJsonList.add(url: url)
			} catch {
				print("\(error)")
			}
		}
		tableView.reloadData()
	}
}
