//
//  FilterObjectsViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/20/18.
//  Copyright © 2018 Bryce Cogswell. All rights reserved.
//

import UIKit

class FilterObjectsViewController: UITableViewController, UITextFieldDelegate {
	@IBOutlet var levelsText: UITextField!
	@IBOutlet var switchLevel: UISwitch!
	@IBOutlet var switchPoints: UISwitch!
	@IBOutlet var switchTrafficRoads: UISwitch!
	@IBOutlet var switchServiceRoads: UISwitch!
	@IBOutlet var switchPaths: UISwitch!
	@IBOutlet var switchBuildings: UISwitch!
	@IBOutlet var switchLanduse: UISwitch!
	@IBOutlet var switchBoundaries: UISwitch!
	@IBOutlet var switchWater: UISwitch!
	@IBOutlet var switchRail: UISwitch!
	@IBOutlet var switchPower: UISwitch!
	@IBOutlet var switchPastFuture: UISwitch!
	@IBOutlet var switchOthers: UISwitch!

	// Parse a level-filter string like "-1,0,2.5..5,7..8" into [[Double]].
	// Each element is either [value] (single level) or [lo, hi] (inclusive range).
	// Returns nil for nil input or invalid string, and [] for empty string.
	class func levels(for text: String?) -> [[Double]]? {
		guard let text else { return nil }
		var list: [[Double]] = []
		for part in text.split(separator: ",") {
			let trimmed = part.trimmingCharacters(in: .whitespaces)
			guard !trimmed.isEmpty else { return nil }
			let bounds = trimmed.components(separatedBy: "..")
			switch bounds.count {
			case 1:
				guard let val = Double(trimmed) else { return nil }
				list.append([val])
			case 2:
				guard let lo = Double(bounds[0].trimmingCharacters(in: .whitespaces)),
				      let hi = Double(bounds[1].trimmingCharacters(in: .whitespaces))
				else { return nil }
				list.append([lo, hi])
			default:
				return nil // e.g. "2...3"
			}
		}
		return list
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let filters = AppDelegate.shared.mapView.objectFilters

		levelsText.text = filters.showLevelRange
		switchLevel.isOn = filters.showLevel
		switchPoints.isOn = filters.showPoints
		switchTrafficRoads.isOn = filters.showTrafficRoads
		switchServiceRoads.isOn = filters.showServiceRoads
		switchPaths.isOn = filters.showPaths
		switchBuildings.isOn = filters.showBuildings
		switchLanduse.isOn = filters.showLanduse
		switchBoundaries.isOn = filters.showBoundaries
		switchWater.isOn = filters.showWater
		switchRail.isOn = filters.showRail
		switchPower.isOn = filters.showPower
		switchPastFuture.isOn = filters.showPastFuture
		switchOthers.isOn = filters.showOthers
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		let filters = AppDelegate.shared.mapView.objectFilters

		filters.showLevelRange = levelsText.text!
		filters.showLevel = switchLevel.isOn
		filters.showPoints = switchPoints.isOn
		filters.showTrafficRoads = switchTrafficRoads.isOn
		filters.showServiceRoads = switchServiceRoads.isOn
		filters.showPaths = switchPaths.isOn
		filters.showBuildings = switchBuildings.isOn
		filters.showLanduse = switchLanduse.isOn
		filters.showBoundaries = switchBoundaries.isOn
		filters.showWater = switchWater.isOn
		filters.showRail = switchRail.isOn
		filters.showPower = switchPower.isOn
		filters.showPastFuture = switchPastFuture.isOn
		filters.showOthers = switchOthers.isOn
	}

	// show filter text in red if the level range is invalid
	func setColorForText(_ text: String?) {
		let a = FilterObjectsViewController.levels(for: text) ?? []
		if a.count == 0 {
			levelsText.textColor = UIColor.red
		} else {
			levelsText.textColor = UIColor.black
		}
	}

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
	               replacementString string: String) -> Bool
	{
		let newString = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
		setColorForText(newString)
		return true
	}

	func textFieldDidEndEditing(_ textField: UITextField) {
		setColorForText(textField.text)
	}
}
