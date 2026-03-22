//
//  ClearCacheViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/15/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

private enum Row: Int {
	case osmData = 0
	case basemap = 1
	case otherCaches = 2
}

protocol DiskCacheSizeProtocol {
	func getDiskCacheSize() async -> (size: Int, count: Int)
	@MainActor func purgeTileCache()
}

class ClearCacheViewController: TableViewControllerMac {
	@IBOutlet var automaticCacheManagement: UISwitch!

	// MARK: - Table view data source

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44

		automaticCacheManagement.isOn = AppDelegate.shared.mainView.settings.enableAutomaticCacheManagement

		for row in 0..<3 {
			let indexPath = IndexPath(row: row, section: 1)
			let cell = tableView.cellForRow(at: indexPath)! as! ClearCacheCell

			update(cell: cell, for: Row(rawValue: row)!)
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		AppDelegate.shared.mainView.settings.enableAutomaticCacheManagement = automaticCacheManagement.isOn
	}

	// MARK: - Table view delegate

	private func update(cell: ClearCacheCell, for row: Row) {
		let mapView = AppDelegate.shared.mapView!
		let mainView = AppDelegate.shared.mainView!
		let mapData = mapView.mapData

		let title: String
		let details: String
		switch row {
		case .osmData:
			title = NSLocalizedString("OSM Data", comment: "")
			details = NSLocalizedString(
				"Downloaded nodes, ways and relations, and any edits you have made.",
				comment: "")
		case .basemap:
			title = NSLocalizedString("Map Tiles", comment: "")
			details = NSLocalizedString(
				"All map tiles for the currently selected base map (Mapnik, Americana, etc).",
				comment: "")
		case .otherCaches:
			title = NSLocalizedString("Caches", comment: "cached data")
			details = NSLocalizedString(
				"All cached data including aerial imagery tiles, TagInfo and Wiki data, etc.",
				comment: "")
		}
		cell.titleLabel.text = title
		cell.detailLabel.text = details
		cell.sizesLabel.text = ""
		cell.clearButton.onTap = { _ in self.deleteData(at: row) }
		cell.clearButton.setTitle("", for: .normal)

		if row == .osmData {
			let objectCount = mapData.nodeCount() + mapData.wayCount() + mapData.relationCount()
			cell.sizesLabel.text = String.localizedStringWithFormat(
				NSLocalizedString("%ld objects", comment: "Number of tiles/objects in cache"),
				objectCount)
		} else {
			cell.sizesLabel.text = NSLocalizedString("computing size...", comment: "")
			Task {
				let size: Int
				let count: Int
				switch row {
				case .basemap:
					(size, count) = await mainView.mapLayersView.basemapLayer.getDiskCacheSize()
				case .otherCaches:
					(size, count) = sizeOfCachesDirectory() ?? (0, 0)
				default:
					fatalError()
				}
				await MainActor.run {
					cell.sizesLabel.text = String.localizedStringWithFormat(
						NSLocalizedString("%.2f MB, %ld files", comment: ""),
						Double(size) / (1024 * 1024),
						count)

					print(ByteCountFormatter())
				}
			}
		}
	}

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		return nil
	}

	private func deleteData(at row: Row) {
		let appDelegate = AppDelegate.shared

		switch row {
		case .osmData:
			let alert = UIAlertController(
				title: NSLocalizedString("Warning", comment: ""),
				message: NSLocalizedString(
					"You have made changes that have not yet been uploaded to the server. Clearing the cache will cause those changes to be lost.",
					comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel,
			                              handler: { _ in
			                              	self.navigationController?.popViewController(animated: true)
			                              }))
			func refreshAfterPurge() {
				appDelegate.mapView.placePushpinForSelection()
				appDelegate.mainView.mapLayersView.mapMarkersView.reset()
				appDelegate.mainView.updateMapMarkers()
			}
			if appDelegate.mapView.mapData.changesetAsXml() != nil
				|| isUnderDebugger()
			{
				alert.addAction(UIAlertAction(
					title: NSLocalizedString("Purge", comment: "Discard editing changes when resetting OSM data cache"),
					style: .destructive,
					handler: { _ in
						appDelegate.mapView.purgeCachedData(.hard)
						refreshAfterPurge()
						self.navigationController?.popViewController(animated: true)
					}))
			}
			// These actions are available only for debugging purposes
			if isUnderDebugger() {
				// Soft purge is used to simulate a low-memory condition
				alert.addAction(UIAlertAction(
					title: "Debug: Low memory",
					style: .destructive,
					handler: { _ in
						appDelegate.mapView.purgeCachedData(.soft)
						refreshAfterPurge()
						self.navigationController?.popViewController(animated: true)
					}))
				// Discard stale is used to simulate automatic cache management
				alert.addAction(UIAlertAction(
					title: "Debug: Automatic cache management",
					style: .destructive,
					handler: { _ in
						_ = appDelegate.mapView.mapData.discardStaleData(maxObjects: 1000, maxAge: 5 * 60)
						refreshAfterPurge()
						self.navigationController?.popViewController(animated: true)
					}))
			}
			if alert.actions.count > 1 {
				present(alert, animated: true)
				return
			}
			appDelegate.mapView.purgeCachedData(.hard)
			refreshAfterPurge()
		case .basemap:
			appDelegate.mainView.mapLayersView.basemapLayer.purgeTileCache()
			URLCache.shared.removeAllCachedResponses()
		case .otherCaches:
			clearCachesDirectory()
			URLCache.shared.removeAllCachedResponses()
		}
		dismiss(animated: true)
	}
}

class ClearCacheCell: UITableViewCell {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var detailLabel: UILabel!
	@IBOutlet var sizesLabel: UILabel!
	@IBOutlet var clearButton: ButtonClosure!
}

private func sizeOfCachesDirectory() -> (size: Int, count: Int)? {
	let fileManager = FileManager.default
	guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
	      let enumerator = fileManager.enumerator(at: cachesURL,
	                                              includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
	                                              options: [.skipsHiddenFiles])
	else {
		return nil
	}
	var fileCount = 0
	var totalSize = 0
	for case let fileURL as URL in enumerator {
		if let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
		   let fileSize = resourceValues.totalFileAllocatedSize
		{
			totalSize += fileSize
			fileCount += 1
		}
	}
	return (size: totalSize, count: fileCount)
}

private func clearCachesDirectory() {
	let fileManager = FileManager.default
	guard
		let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
		let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
	else {
		return
	}
	for itemURL in contents {
		try? fileManager.removeItem(at: itemURL)
	}
}
