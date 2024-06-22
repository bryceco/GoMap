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
}

protocol DiskCacheSizeProtocol {
	func getDiskCacheSize() -> (size: Int, count: Int)
}

class ClearCacheViewController: UITableViewController {
	@IBOutlet var automaticCacheManagement: UISwitch!

	// MARK: - Table view data source

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 44

		let appDelegate = AppDelegate.shared

		automaticCacheManagement.isOn = appDelegate.mapView.enableAutomaticCacheManagement
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		let appDelegate = AppDelegate.shared
		appDelegate.mapView.enableAutomaticCacheManagement = automaticCacheManagement.isOn
	}

	// MARK: - Table view delegate

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell,
	                        forRowAt indexPath: IndexPath)
	{
		guard let cell = cell as? ClearCacheCell else { return }
		if indexPath.section != 1 {
			return
		}

		let mapView = AppDelegate.shared.mapView!
		let mapData = mapView.editorLayer.mapData

		let title: String?
		let object: [DiskCacheSizeProtocol]
		switch indexPath.row {
		case Row.osmData.rawValue:
			title = NSLocalizedString("Clear OSM Data", comment: "Delete cached data")
			object = []
		case Row.basemap.rawValue:
			title = NSLocalizedString("Clear Basemap Tiles", comment: "Delete cached data")
			switch mapView.basemapLayer {
			case let .tileLayer(layer):
				object = [layer]
			case let .tileView(view):
				object = [view]
			default:
				object = []
			}
		default:
			fatalError()
		}
		cell.titleLabel.text = title
		cell.detailLabel.text = ""

		if indexPath.row == Row.osmData.rawValue {
			let objectCount = mapData.nodeCount() + mapData.wayCount() + mapData.relationCount()
			cell.detailLabel.text = String.localizedStringWithFormat(
				NSLocalizedString("%ld objects", comment: "Number of tiles/objects in cache"),
				objectCount)
		} else {
			cell.detailLabel.text = NSLocalizedString("computing size...", comment: "")
			DispatchQueue.global(qos: .default).async(execute: {
				var size = 0
				var count = 0
				for obj in object {
					let (tSize, tCount) = obj.getDiskCacheSize()
					size += tSize
					count += tCount
				}
				DispatchQueue.main.async(execute: {
					cell.detailLabel.text = String.localizedStringWithFormat(
						NSLocalizedString("%.2f MB, %ld files", comment: ""),
						Double(size) / (1024 * 1024),
						count)
				})
			})
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let appDelegate = AppDelegate.shared

		guard indexPath.section == 1,
		      let row = Row(rawValue: indexPath.row)
		else {
			return
		}

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
				appDelegate.mapView.mapMarkerDatabase.removeAll()
				appDelegate.mapView.updateMapMarkersFromServer(withDelay: 0.0, including: [])
			}
			if appDelegate.mapView.editorLayer.mapData.changesetAsXml() != nil {
				alert.addAction(UIAlertAction(
					title: NSLocalizedString("Purge", comment: "Discard editing changes when resetting OSM data cache"),
					style: .default,
					handler: { _ in
						appDelegate.mapView.editorLayer.purgeCachedData(.hard)
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
						appDelegate.mapView.editorLayer.purgeCachedData(.soft)
						refreshAfterPurge()
						self.navigationController?.popViewController(animated: true)
					}))
				// Discard stale is used to simulate automatic cache management
				alert.addAction(UIAlertAction(
					title: "Debug: Automatic cache management",
					style: .destructive,
					handler: { _ in
						_ = appDelegate.mapView.editorLayer.mapData.discardStaleData(maxObjects: 1000, maxAge: 5 * 60)
						refreshAfterPurge()
						self.navigationController?.popViewController(animated: true)
					}))
				// Regular purge
				alert.addAction(UIAlertAction(
					title: "Debug: Purge Hard ignoring modifications",
					style: .destructive,
					handler: { _ in
						appDelegate.mapView.editorLayer.purgeCachedData(.hard)
						refreshAfterPurge()
						self.navigationController?.popViewController(animated: true)
					}))
			}
			if alert.actions.count > 1 {
				present(alert, animated: true)
				return
			}
			appDelegate.mapView.editorLayer.purgeCachedData(.hard)
			refreshAfterPurge()
		case .basemap:
			switch appDelegate.mapView.basemapLayer {
			case let .tileLayer(layer):
				layer.purgeTileCache()
			case let .tileView(view):
				view.purgeTileCache()
			default:
				break
			}
		}
		dismiss(animated: true)
	}
}

class ClearCacheCell: UITableViewCell {
	@IBOutlet var titleLabel: UILabel!
	@IBOutlet var detailLabel: UILabel!
}
