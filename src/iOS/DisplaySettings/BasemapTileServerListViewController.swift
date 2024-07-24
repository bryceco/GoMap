//
//  BasemapTileServerListViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/13/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

import UIKit

private let AmericanaServer: TileServer? = {
#if canImport(MapLibre)
	if #available(iOS 14.0, *) {
		return TileServer.americana
	} else {
		return nil
	}
#else
	return nil
#endif
}()

let BasemapServerList: [TileServer] = [
	TileServer.mapnik,
	TileServer.humanitarian,
	AmericanaServer
]
.compactMap { $0 }
.sorted(by: { a, b in a.best == b.best ? a.name.caseInsensitiveCompare(b.name).rawValue < 0 : a.best })

class BasemapTileServerListViewController: UITableViewController {
	weak var displayViewController: DisplayViewController?

	private let SECTION_BUILTIN = 0

	override func viewDidLoad() {
		super.viewDidLoad()
		tableView.estimatedRowHeight = 44.0
		tableView.rowHeight = UITableView.automaticDimension
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if isMovingFromParent {
			// save any changes if necessary
		}
	}

	// MARK: - Table view data source

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return NSLocalizedString("Standard imagery", comment: "")
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return BasemapServerList.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "backgroundCell", for: indexPath)
		let tileServer = BasemapServerList[indexPath.row]

		// set selection
		var title = tileServer.name
		if tileServer.best {
			title = "☆" + title // star best imagery
		}
		if tileServer == AppDelegate.shared.mapView.basemapServer {
			title = "\u{2714} " + title // add checkmark
		}

		// get details
		cell.textLabel?.text = title

		return cell
	}

	// MARK: - Navigation

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let server = BasemapServerList[indexPath.row]
		AppDelegate.shared.mapView.basemapServer = server

		// if popping all the way up we need to tell Settings to save changes
		displayViewController?.applyChanges()
		dismiss(animated: true)
	}
}
