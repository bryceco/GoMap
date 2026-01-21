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

	// return a list of arrays, each array containing either a single integer or a first-last pair of integers
	class func levels(for text: String?) -> [[Double]] {
		guard let text = text else { return [] }
		var list: [[Double]] = []
		let scanner = Scanner(string: text)
		scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines

		if scanner.isAtEnd {
			return list // empty list
		}

		while true {
			guard let first = scanner.scanDouble() else {
				return []
			}
			if scanner.scanString("..") != nil {
				guard let last = scanner.scanDouble() else {
					return []
				}
				list.append([first, last])
			} else {
				list.append([first])
			}
			if scanner.isAtEnd {
				return list
			}
			if scanner.scanString(",") != nil {
				return []
			}
		}
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
		let a = FilterObjectsViewController.levels(for: text)
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
