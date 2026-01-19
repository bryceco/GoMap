//
//  SecondViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import MessageUI

private let BACKGROUND_SECTION = 0
private let OVERLAY_SECTION = 2
private let CACHE_SECTION = 3

class DisplayViewController: UITableViewController {
	@IBOutlet var rotationSwitch: UISwitch!
	@IBOutlet var notesSwitch: UISwitch!
	@IBOutlet var questsSwitch: UISwitch!
	@IBOutlet var dataOverlaySwitch: UISwitch!
	@IBOutlet var gpxLoggingSwitch: UISwitch!
	@IBOutlet var turnRestrictionSwitch: UISwitch!
	@IBOutlet var objectFiltersSwitch: UISwitch!
	@IBOutlet var addButtonPosition: UIButton!

	@IBAction func chooseAddButtonPosition(_ sender: Any) {
		let alert = UIAlertController(
			title: NSLocalizedString("+ Button Position", comment: "Location of Add Node button on the screen"),
			message: NSLocalizedString(
				"The + button can be positioned on either the left or right side of the screen",
				comment: ""),
			preferredStyle: .alert)
		let left = UIAlertAction(
			title: NSLocalizedString("Left side", comment: "Left-hand side of screen"),
			style: .default,
			handler: { _ in
				AppDelegate.shared.mainView.settings.buttonLayout = .buttonsOnLeft
				self.setButtonLayoutTitle()
			})
		let right = UIAlertAction(
			title: NSLocalizedString("Right side", comment: "Right-hand side of screen"),
			style: .default,
			handler: { _ in
				AppDelegate.shared.mainView.settings.buttonLayout = .buttonsOnRight
				self.setButtonLayoutTitle()
			})
#if targetEnvironment(macCatalyst)
		// buttons appear right-to-left
		alert.addAction(right)
		alert.addAction(left)
#else
		// buttons appear left-to-right
		alert.addAction(left)
		alert.addAction(right)
#endif
		present(alert, animated: true)
	}

	func applyChanges() {
		let mainView = AppDelegate.shared.mainView!
		let mapView = mainView.mapView!

		let maxRow = tableView.numberOfRows(inSection: BACKGROUND_SECTION)
		for row in 0..<maxRow {
			let indexPath = IndexPath(row: row, section: BACKGROUND_SECTION)
			if let cell = tableView.cellForRow(at: indexPath) {
				if cell.accessoryType == .checkmark {
					mapView.viewState = MapViewState(rawValue: cell.tag) ?? MapViewState.EDITORAERIAL
					mainView.setAerialTileServer(AppState.shared.tileServerList.currentServer)
					break
				}
			}
		}

		mapView.viewOverlayMask = [
			notesSwitch.isOn ? .NOTES : [],
			questsSwitch.isOn ? .QUESTS : [],
			dataOverlaySwitch.isOn ? .DATAOVERLAY : []
		]

		mainView.settings.enableRotation = rotationSwitch.isOn
		mainView.settings.displayGpxTracks = gpxLoggingSwitch.isOn
		mainView.mapLayersView.displayDataOverlayLayers = dataOverlaySwitch.isOn
		mainView.settings.enableTurnRestriction = turnRestrictionSwitch.isOn

		mapView.editorLayer.setNeedsLayout()
	}

	@IBAction func gpsSwitchChanged(_ sender: Any) {
		// need this to take effect immediately in case they exit the app without dismissing this controller, and they want GPS enabled in background
		AppDelegate.shared.mainView.settings.displayGpxTracks = gpxLoggingSwitch.isOn
	}

	@IBAction func dataOverlaySwitchChanged(_ sender: Any) {
		// need this to take effect immediately in case they exit the app without dismissing this controller, and they want GPS enabled in background
		let mainView = AppDelegate.shared.mainView!
		mainView.mapLayersView.displayDataOverlayLayers = dataOverlaySwitch.isOn
	}

	@IBAction func toggleObjectFilters(_ sender: UISwitch) {
		AppDelegate.shared.mapView.editorLayer.objectFilters.enableObjectFilters = sender.isOn
	}

	func setButtonLayoutTitle() {
		let onLeft = AppDelegate.shared.mainView.settings.buttonLayout == MainViewButtonLayout.buttonsOnLeft
		let title = onLeft
			? NSLocalizedString("Left", comment: "")
			: NSLocalizedString("Right", comment: "")
		addButtonPosition.setTitle(title, for: .normal)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		guard
			let mainView = AppDelegate.shared.mainView,
			let mapView = mainView.mapView
		else { return }

		// becoming visible the first time
		navigationController?.isNavigationBarHidden = false

		notesSwitch.isOn = mapView.viewOverlayMask.contains(.NOTES)
		questsSwitch.isOn = mapView.viewOverlayMask.contains(.QUESTS)
		dataOverlaySwitch.isOn = mainView.mapLayersView.displayDataOverlayLayers

		gpxLoggingSwitch.isOn = AppDelegate.shared.mainView.settings.displayGpxTracks
		turnRestrictionSwitch.isOn = AppDelegate.shared.mainView.settings.enableTurnRestriction
		objectFiltersSwitch.isOn = mapView.editorLayer.objectFilters.enableObjectFilters
		rotationSwitch.isOn = AppDelegate.shared.mainView.settings.enableRotation

		setButtonLayoutTitle()
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell,
	                        forRowAt indexPath: IndexPath)
	{
		// place a checkmark next to currently selected display
		if indexPath.section == BACKGROUND_SECTION {
			let mapView = AppDelegate.shared.mapView
			if cell.tag == Int(mapView?.viewState.rawValue ?? -1) {
				cell.accessoryType = .checkmark
			} else {
				cell.accessoryType = .none
			}
		}

		// set the name of the aerial provider
		if indexPath.section == BACKGROUND_SECTION, indexPath.row == 2 {
			if let custom = cell as? CustomBackgroundCell {
				let servers = AppState.shared.tileServerList
				custom.button.setTitle(servers.currentServer.name, for: .normal)
				custom.button.sizeToFit()
			}
		}

		// set the name of the basemap provider
		if indexPath.section == BACKGROUND_SECTION, indexPath.row == 3 {
			if let custom = cell as? CustomBackgroundCell {
				let server = AppDelegate.shared.mainView.mapLayersView.basemapServer
				custom.button.setTitle(server.name, for: .normal)
				custom.button.sizeToFit()
			}
		}
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		applyChanges()
	}

	@IBAction func onDone(_ sender: Any?) {
		dismiss(animated: true)
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let cell = tableView.cellForRow(at: indexPath)

		if indexPath.section == BACKGROUND_SECTION {
			// change checkmark to follow selection
			let maxRow = self.tableView.numberOfRows(inSection: indexPath.section)
			for row in 0..<maxRow {
				let tmpPath = IndexPath(row: row, section: indexPath.section)
				let tmpCell = tableView.cellForRow(at: tmpPath)
				tmpCell?.accessoryType = .none
			}
			cell?.accessoryType = .checkmark
		} else if indexPath.section == OVERLAY_SECTION {
		} else if indexPath.section == CACHE_SECTION {}
		self.tableView.deselectRow(at: indexPath, animated: true)

		// automatically dismiss settings when a new background is selected
		if indexPath.section == BACKGROUND_SECTION {
			onDone(nil)
		}
	}

	override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
		if indexPath.section == BACKGROUND_SECTION {
			let cell = tableView.cellForRow(at: indexPath)
			cell?.accessoryType = .none
		}
	}
}

class CustomBackgroundCell: UITableViewCell {
	@IBOutlet var button: UIButton!
}
