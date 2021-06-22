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
	@IBOutlet var birdsEyeSwitch: UISwitch!
	@IBOutlet var rotationSwitch: UISwitch!
	@IBOutlet var notesSwitch: UISwitch!
	@IBOutlet var gpsTraceSwitch: UISwitch!
	@IBOutlet var unnamedRoadSwitch: UISwitch!
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
		alert.addAction(UIAlertAction(
			title: NSLocalizedString("Left side", comment: "Left-hand side of screen"),
			style: .default,
			handler: { _ in
				AppDelegate.shared.mapView.mainViewController.buttonLayout = BUTTON_LAYOUT._ADD_ON_LEFT
				self.setButtonLayoutTitle()
			}))
		alert.addAction(UIAlertAction(
			title: NSLocalizedString("Right side", comment: "Right-hand side of screen"),
			style: .default,
			handler: { _ in
				AppDelegate.shared.mapView.mainViewController.buttonLayout = BUTTON_LAYOUT._ADD_ON_RIGHT
				self.setButtonLayoutTitle()
			}))
		present(alert, animated: true)
	}

	func applyChanges() {
		let mapView = AppDelegate.shared.mapView!

		let maxRow = tableView.numberOfRows(inSection: BACKGROUND_SECTION)
		for row in 0..<maxRow {
			let indexPath = IndexPath(row: row, section: BACKGROUND_SECTION)
			if let cell = tableView.cellForRow(at: indexPath) {
				if cell.accessoryType == .checkmark {
					mapView.viewState = MapViewState(rawValue: cell.tag) ?? MapViewState.EDITORAERIAL
					mapView.setAerialTileServer(mapView.tileServerList.currentServer)
					break
				}
			}
		}

		var mask: Int = 0
		mask |= notesSwitch.isOn ? Int(MapViewOverlays.NOTES.rawValue) : 0
		mask |= gpsTraceSwitch.isOn ? Int(MapViewOverlays.GPSTRACE.rawValue) : 0
		mask |= unnamedRoadSwitch.isOn ? Int(MapViewOverlays.NONAME.rawValue) : 0
		mapView.viewOverlayMask = MapViewOverlays(rawValue: MapViewOverlays.RawValue(mask))

		mapView.enableBirdsEye = birdsEyeSwitch.isOn
		mapView.enableRotation = rotationSwitch.isOn
		mapView.enableUnnamedRoadHalo = unnamedRoadSwitch.isOn
		mapView.enableGpxLogging = gpxLoggingSwitch.isOn
		mapView.enableTurnRestriction = turnRestrictionSwitch.isOn

		mapView.editorLayer.setNeedsLayout()
	}

	@IBAction func gpsSwitchChanged(_ sender: Any) {
		// need this to take effect immediately in case they exit the app without dismissing this controller, and they want GPS enabled in background
		let mapView = AppDelegate.shared.mapView
		mapView?.enableGpxLogging = gpxLoggingSwitch.isOn
	}

	@IBAction func toggleObjectFilters(_ sender: UISwitch) {
		AppDelegate.shared.mapView.editorLayer.objectFilters.enableObjectFilters = sender.isOn
	}

	func setButtonLayoutTitle() {
		let title = AppDelegate.shared.mapView.mainViewController.buttonLayout == BUTTON_LAYOUT
			._ADD_ON_LEFT ? NSLocalizedString(
				"Left",
				comment: "") : NSLocalizedString("Right", comment: "")
		addButtonPosition.setTitle(title, for: .normal)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		let mapView = AppDelegate.shared.mapView

		// becoming visible the first time
		navigationController?.isNavigationBarHidden = false

		if let viewOverlayMask = mapView?.viewOverlayMask {
			// Fix here
			let bitwiseOperation = (viewOverlayMask.rawValue & MapViewOverlays.NOTES.rawValue)
			notesSwitch.isOn = bitwiseOperation != 0
		}
		gpsTraceSwitch.isOn = !(mapView?.gpsTraceLayer.isHidden)!

		birdsEyeSwitch.isOn = mapView?.enableBirdsEye ?? false
		rotationSwitch.isOn = mapView?.enableRotation ?? false
		unnamedRoadSwitch.isOn = mapView?.enableUnnamedRoadHalo ?? false
		gpxLoggingSwitch.isOn = mapView?.enableGpxLogging ?? false
		turnRestrictionSwitch.isOn = mapView?.enableTurnRestriction ?? false
		objectFiltersSwitch.isOn = mapView?.editorLayer.objectFilters.enableObjectFilters ?? false

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
				let servers = AppDelegate.shared.mapView.tileServerList
				custom.button.setTitle(servers.currentServer.name, for: .normal)
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
