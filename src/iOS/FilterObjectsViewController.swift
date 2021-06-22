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
			var first = Double()
			var last = Double()
			if !scanner.scanDouble(&first) {
				return []
			}
			if scanner.scanString("..", into: nil) {
				if !scanner.scanDouble(&last) {
					return []
				}
				list.append([first, last])
			} else {
				list.append([first])
			}
			if scanner.isAtEnd {
				return list
			}
			if !scanner.scanString(",", into: nil) {
				return []
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let editor = AppDelegate.shared.mapView.editorLayer.objectFilters

		levelsText.text = editor.showLevelRange
		switchLevel.isOn = editor.showLevel
		switchPoints.isOn = editor.showPoints
		switchTrafficRoads.isOn = editor.showTrafficRoads
		switchServiceRoads.isOn = editor.showServiceRoads
		switchPaths.isOn = editor.showPaths
		switchBuildings.isOn = editor.showBuildings
		switchLanduse.isOn = editor.showLanduse
		switchBoundaries.isOn = editor.showBoundaries
		switchWater.isOn = editor.showWater
		switchRail.isOn = editor.showRail
		switchPower.isOn = editor.showPower
		switchPastFuture.isOn = editor.showPastFuture
		switchOthers.isOn = editor.showOthers
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		let editor = AppDelegate.shared.mapView.editorLayer.objectFilters

		editor.showLevelRange = levelsText.text!
		editor.showLevel = switchLevel.isOn
		editor.showPoints = switchPoints.isOn
		editor.showTrafficRoads = switchTrafficRoads.isOn
		editor.showServiceRoads = switchServiceRoads.isOn
		editor.showPaths = switchPaths.isOn
		editor.showBuildings = switchBuildings.isOn
		editor.showLanduse = switchLanduse.isOn
		editor.showBoundaries = switchBoundaries.isOn
		editor.showWater = switchWater.isOn
		editor.showRail = switchRail.isOn
		editor.showPower = switchPower.isOn
		editor.showPastFuture = switchPastFuture.isOn
		editor.showOthers = switchOthers.isOn
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
