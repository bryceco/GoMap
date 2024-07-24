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

		let regex = "2012-20[0-9][0-9]"
		if let range = textView.text.range(of: regex, options: [.regularExpression]) {
			let newYear = Calendar(identifier: .gregorian).component(.year, from: Date())
			let newRange = "2012-\(newYear)"
			textView.text = textView.text.replacingCharacters(in: range, with: newRange)
		}
		textView.isEditable = false
		textView.layer.cornerRadius = 10.0
	}
}
