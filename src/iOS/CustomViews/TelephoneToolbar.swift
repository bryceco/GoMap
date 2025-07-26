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
	let codes = AppDelegate.shared.mapView.currentRegion.callingCodes

	init(forTextField textfield: UITextField, frame: CGRect) {
		textField = textfield
		super.init(frame: CGRect(x: 0, y: 0, width: textField.frame.size.width, height: 44))
		let space = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
		space.width = 10.0
		items = [
			Self.makeButton(
				title: "+\(codes.first ?? "1")",
				target: self,
				action: #selector(setCallingCodeText(_:))),
			space,
			Self.makeButton(
				title: NSLocalizedString("Space", comment: "Space key on the keyboard"),
				target: self,
				action: #selector(insertSpace(_:))),
			space,
			Self.makeButton(
				title: "\u{2014}",
				target: self,
				action: #selector(insertDash(_:))),
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
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
			let code = codes.first ?? "1"
			textField.text = "+" + code + " " + text
		}
	}

	@objc func insertSpace(_ sender: Any?) {
		textField.insertText(" ")
	}

	@objc func insertDash(_ sender: Any?) {
		textField.insertText("-")
	}

	private class func makeButton(title: String,
	                              target: AnyObject,
	                              action: Selector) -> UIBarButtonItem
	{
		let button = UIButton(type: .custom)
		button.setTitle(title, for: .normal)
		button.setTitleColor(UIColor.systemBlue, for: .normal)
		button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
		button.layer.borderWidth = 1
		button.layer.cornerRadius = 10
		button.layer.borderColor = UIColor.systemBlue.cgColor
		button.addTarget(target, action: action, for: .touchUpInside)
		return UIBarButtonItem(customView: button)
	}
}
