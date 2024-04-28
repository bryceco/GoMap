//
//  GpxConfigureViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/6/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import UIKit

class GpxConfigureViewController: UIViewController, UIPickerViewDelegate, UIPickerViewDataSource {
	@IBOutlet var pickerView: UIPickerView!
	var expirationValue = 0
	var completion: ((_ pick: Int) -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()
		pickerView.delegate = self
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		pickerView.selectRow(expirationValue, inComponent: 0, animated: false)
	}

	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		if row == 0 {
			return NSLocalizedString("Never", comment: "Never delete old GPX tracks")
		}
		if row == 1 {
			return NSLocalizedString("1 Day", comment: "1 day singular")
		}
		return String.localizedStringWithFormat(NSLocalizedString("%ld Days", comment: ""), row)
	}

	func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		expirationValue = row
	}

	// returns the number of 'columns' to display.
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}

	// returns the # of rows in each component..
	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return 100
	}

	@IBAction func cancel(_ sender: Any) {
		dismiss(animated: true)
	}

	@IBAction func done(_ sender: Any) {
		completion?(expirationValue)
		dismiss(animated: true)
	}
}
