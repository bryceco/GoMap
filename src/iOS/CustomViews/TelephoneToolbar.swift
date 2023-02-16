//
//  TelephoneToolbar.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/6/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class TelephoneToolbar: UIToolbar {
	weak var textField: UITextField!

	init(forTextField textfield: UITextField, frame: CGRect) {
		textField = textfield
		super.init(frame: CGRect(x: 0, y: 0, width: textField.frame.size.width, height: 44))
		items = [
			UIBarButtonItem(
				title: "+1",
				style: .plain,
				target: self,
				action: #selector(setCallingCodeText(_:))),
			UIBarButtonItem(
				title: NSLocalizedString("Space", comment: "Space key on the keyboard"),
				style: .plain,
				target: self,
				action: #selector(insertSpace(_:))),
			UIBarButtonItem(
				title: "-",
				style: .plain,
				target: self,
				action: #selector(insertDash(_:))),
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),
			UIBarButtonItem(barButtonSystemItem: .done,
			                target: self,
			                action: #selector(done(_:)))
		]
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc func done(_ sender: Any?) {
		textField.resignFirstResponder()
	}

	@objc func setCallingCodeText(_ sender: Any?) {
		if let text = textField.text,
		   !text.hasPrefix("+")
		{
			let code = AppDelegate.shared.mapView.currentRegion.callingCode() ?? ""
			textField.text = "+" + code + " " + text
		}
	}

	@objc func insertSpace(_ sender: Any?) {
		textField.insertText(" ")
	}

	@objc func insertDash(_ sender: Any?) {
		textField.insertText("-")
	}
}
