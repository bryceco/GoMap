//
//  TelephoneToolbar.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/6/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class TelephoneToolbar: KeyboardToolbar {
	init(forTextField textfield: UITextField, frame: CGRect) {
		let countryCode = AppDelegate.shared.mainView.currentRegion.callingCodes.first ?? "1"
		super.init(items: [
			.title("+\(countryCode)") { [weak textfield] _ in
				guard let text = textfield?.text, !text.hasPrefix("+") else { return }
				textfield?.text = "+\(countryCode) \(text)"
			},
			.title(NSLocalizedString("Space", comment: "Space key on the keyboard")) { [weak textfield] _ in
				textfield?.insertText(" ")
			},
			.title("\u{2012}") { [weak textfield] _ in
				textfield?.insertText("-")
			},
			.flexibleSpace,
			.done { [weak textfield] _ in
				textfield?.resignFirstResponder()
			}
		])
	}
}
