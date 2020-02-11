//
//  LaneStepper.swift
//  Go Kaart!!
//
//  Created by Tanner Wuster on 1/27/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit

@objc protocol LaneStepperDelegate: class {
	func stepLanes()
}

@objc class LaneStepperViewController: UIViewController {
//label
	@objc @IBOutlet var Label: UILabel!

	@objc weak var delegate: LaneStepperDelegate?

	@objc @IBAction func Lane(_ sender: UIStepper) {
		Label.text = String(sender.value)
	}
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view.
	}
}
