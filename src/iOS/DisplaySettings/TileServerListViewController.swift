//
//  TileServerListViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class TileServerListViewController: UITableViewController {
	var serverList: TileServerList!
	var imageryForRegion: [TileServer] = []

	weak var displayViewController: DisplayViewController?

	private let SECTION_BUILTIN = 0
	private let SECTION_USER = 1
	private let SECTION_EXTERNAL = 2

	override func viewDidLoad() {
		let appDelegate = AppDelegate.shared
		serverList = appDelegate.mapView.tileServerList

		let latLon = appDelegate.mapView.screenCenterLatLon()
		imageryForRegion = serverList.allServices(at: latLon)

		super.viewDidLoad()

		tableView.estimatedRowHeight = 44.0
		tableView.rowHeight = UITableView.automaticDimension

		navigationItem.rightBarButtonItem = editButtonItem
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		if isMovingFromParent {
			AppDelegate.shared.mapView.setAerialTileServer(serverList.currentServer)
		}
	}

	// MARK: - Table view data source

	func tileServerList(forSection section: Int) -> [TileServer] {
		if section == SECTION_BUILTIN {
			return serverList.builtinServers()
		}
		if section == SECTION_USER {
			return serverList.userDefinedServices()
		}
		if section == SECTION_EXTERNAL {
			return imageryForRegion
		}
		return []
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == SECTION_BUILTIN {
			return NSLocalizedString("Standard imagery", comment: "")
		}
		if section == SECTION_USER {
			return NSLocalizedString("User-defined imagery", comment: "")
		}
		if section == SECTION_EXTERNAL {
			return NSLocalizedString("Additional imagery", comment: "")
		}
		return nil
	}

	override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
		if section == SECTION_EXTERNAL {
			let dateFormatter = DateFormatter()
			dateFormatter.dateStyle = .medium
			dateFormatter.timeStyle = .none
			if let lastDownloadDate = serverList.lastDownloadDate {
				let date = dateFormatter.string(from: lastDownloadDate)
				return String.localizedStringWithFormat(NSLocalizedString("Last updated %@", comment: ""), date)
			}
		}
		return nil
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 3
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		let a = tileServerList(forSection: section)
		let offSet = (section == SECTION_USER) ? 1 : 0
		return a.count + offSet
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.section == SECTION_USER && indexPath.row == serverList.userDefinedServices().count {
			let cell = tableView.dequeueReusableCell(withIdentifier: "addNewCell", for: indexPath)
			return cell
		}

		let list = tileServerList(forSection: indexPath.section)
		let cell = tableView.dequeueReusableCell(withIdentifier: "backgroundCell", for: indexPath)
		let tileServer = list[indexPath.row]

		// set selection
		var title = tileServer.name
		if tileServer.best {
			title = "☆" + title // star best imagery
		}
		if tileServer === serverList.currentServer {
			title = "\u{2714} " + title // add checkmark
		}

		// get details
		var urlDetail = tileServer.isMaxar() ? "" : tileServer.url
		if urlDetail.hasPrefix("https://") {
			urlDetail = String(urlDetail.dropFirst(8))
		} else if urlDetail.hasPrefix("http://") {
			urlDetail = String(urlDetail.dropFirst(7))
		}

		var dateDetail: String?
		if tileServer.startDate != nil && tileServer.endDate != nil && !(tileServer.startDate == tileServer.endDate) {
			if let startDate = tileServer.startDate,
			   let endDate = tileServer.endDate
			{
				dateDetail = String.localizedStringWithFormat(
					NSLocalizedString("vintage %@ - %@", comment: "Years aerial imagery was created"),
					startDate,
					endDate)
			}
		} else if tileServer.startDate != nil || tileServer.endDate != nil {
			if let startDate = tileServer.startDate ?? tileServer.endDate {
				dateDetail = String.localizedStringWithFormat(
					NSLocalizedString("vintage %@", comment: "Year aerial imagery was created"),
					startDate)
			}
		}
		let details = dateDetail ?? urlDetail

		cell.textLabel?.text = title
		cell.detailTextLabel?.text = details

		return cell
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == SECTION_USER, indexPath.row < (serverList?.userDefinedServices().count ?? 0) {
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
			serverList!.removeUserDefinedService(at: indexPath.row)
			tableView.deleteRows(at: [indexPath], with: .automatic)
		} else if editingStyle == .insert {
			// Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
		}
	}

	override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
		let service = serverList!.userDefinedServices()[fromIndexPath.row]
		serverList!.removeUserDefinedService(at: fromIndexPath.row)
		serverList!.addUserDefinedService(service, at: toIndexPath.row)
	}

	override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		if indexPath.section == SECTION_USER, indexPath.row < serverList!.userDefinedServices().count {
			return true
		}
		return false
	}

	// MARK: - Navigation

	override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
		// don't allow selection the Add button
		if indexPath.section == SECTION_USER, indexPath.row == (serverList?.userDefinedServices().count ?? 0) {
			return nil
		}
		return indexPath
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let appDelegate = AppDelegate.shared
		let mapView = appDelegate.mapView!

		let list = tileServerList(forSection: indexPath.section)
		guard let service = (indexPath.row < list.count ? list[indexPath.row] : nil) else {
			return
		}
		serverList.currentServer = service

		mapView.setAerialTileServer(serverList.currentServer)

		// if popping all the way up we need to tell Settings to save changes
		displayViewController?.applyChanges()
		dismiss(animated: true)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		guard let controller = segue.destination as? TileServerEditViewController,
		      let sender = sender as? UIView
		else { return }

		var editRow: IndexPath?
		if sender is UIButton {
			// add new
			editRow = IndexPath(row: serverList?.userDefinedServices().count ?? 0, section: SECTION_USER)
		} else {
			// edit existing service
			guard let cell: UITableViewCell = sender.superviewOfType(),
			      let indexPath = tableView.indexPath(for: cell)
			else {
				return
			}
			let list = tileServerList(forSection: indexPath.section)
			guard let service = (indexPath.row < list.count ? list[indexPath.row] : nil) else {
				return
			}
			if indexPath.section == SECTION_USER {
				editRow = indexPath
			}
			controller.name = service.name
			controller.url = service.isMaxar() ? "" : service.url
			if service.maxZoom > 0 {
				controller.zoom = service.maxZoom
			}
			controller.projection = service.wmsProjection
		}

		controller.completion = { service in
			guard let editRow = editRow else {
				return
			}
			if editRow.row == self.serverList.userDefinedServices().count {
				self.serverList.addUserDefinedService(service, at: self.serverList.userDefinedServices().count)
			} else {
				self.serverList.removeUserDefinedService(at: editRow.row)
				self.serverList.addUserDefinedService(service, at: editRow.row)
			}
			self.tableView.reloadData()
			self.tableView(self.tableView, didSelectRowAt: editRow)
		}
	}
}
