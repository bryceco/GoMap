//
//  CreditsViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

class CreditsViewController: UIViewController {
	@IBOutlet var textView: UITextView!

	override func viewDidLoad() {
		super.viewDidLoad()

		textView.isEditable = false
		textView.layer.cornerRadius = 10.0
	}
}
