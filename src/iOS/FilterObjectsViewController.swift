//
//  FilterObjectsViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/20/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

import UIKit

class FilterObjectsViewController: UITableViewController, UITextFieldDelegate {
    @IBOutlet weak var levelsText: UITextField!
    @IBOutlet weak var switchLevel: UISwitch!
    @IBOutlet weak var switchPoints: UISwitch!
    @IBOutlet weak var switchTrafficRoads: UISwitch!
    @IBOutlet weak var switchServiceRoads: UISwitch!
    @IBOutlet weak var switchPaths: UISwitch!
    @IBOutlet weak var switchBuildings: UISwitch!
    @IBOutlet weak var switchLanduse: UISwitch!
    @IBOutlet weak var switchBoundaries: UISwitch!
    @IBOutlet weak var switchWater: UISwitch!
    @IBOutlet weak var switchRail: UISwitch!
    @IBOutlet weak var switchPower: UISwitch!
    @IBOutlet weak var switchPastFuture: UISwitch!
    @IBOutlet weak var switchOthers: UISwitch!

    // return a list of arrays, each array containing either a single integer or a first-last pair of integers
	@objc
	class func levels(for text: String?) -> [[NSNumber]] {
		guard let text = text else { return [] }
		var list: [[NSNumber]] = []
		let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines

        if scanner.isAtEnd {
			return list // empty list
        }

        while true {
            var first = Int()
            var last = Int()
            if !scanner.scanInt(&first) {
                return []
			}
            if scanner.scanString("..", into: nil) {
                if !scanner.scanInt(&last) {
                    return []
                }
				list.append([NSNumber(value: first),NSNumber(value:last)])
			} else {
				list.append([NSNumber(value: first)])
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

        let editor = AppDelegate.shared.mapView.editorLayer!

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

        let editor = AppDelegate.shared.mapView.editorLayer!

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

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newString = (textField.text as NSString?)?.replacingCharacters(in: range, with: string)
        setColorForText(newString)
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        setColorForText(textField.text)
    }
}
