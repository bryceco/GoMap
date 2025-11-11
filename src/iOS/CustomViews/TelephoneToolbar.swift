//
//  TelephoneToolbar.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/6/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class TelephoneToolbar: UIControl {
	weak var textField: UITextField!
	let codes = AppDelegate.shared.mapView.currentRegion.callingCodes

	init(forTextField textfield: UITextField, frame: CGRect) {
		textField = textfield
		super.init(frame: CGRect(x: 0, y: 0, width: textField.frame.size.width, height: 44))

		let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
		let blurView = UIVisualEffectView(effect: blurEffect)
		addSubview(blurView)

		let space = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
		space.width = 10.0
		let toolbar = UIToolbar(frame: .zero)
		toolbar.items = [
			Self.makeButton(
				title: "+\(codes.first ?? "1")",
				action: { _ in
					if let text = self.textField.text,
					   !text.hasPrefix("+")
					{
						let code = self.codes.first ?? "1"
						self.textField.text = "+" + code + " " + text
					}
				}),
			space,
			Self.makeButton(
				title: NSLocalizedString("Space", comment: "Space key on the keyboard"),
				action: { _ in
					self.textField.insertText(" ")
				}),
			space,
			Self.makeButton(
				title: "\u{2014}",
				action: { _ in
					self.textField.insertText("-")
				}),
			UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
			UIBarButtonItem(barButtonSystemItem: .done,
			                target: self,
			                action: #selector(done(_:)))
		]
		blurView.contentView.addSubview(toolbar)

		for view in [blurView, toolbar] {
			view.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				view.topAnchor.constraint(equalTo: self.topAnchor),
				view.bottomAnchor.constraint(equalTo: self.bottomAnchor),
				view.leadingAnchor.constraint(equalTo: self.leadingAnchor),
				view.trailingAnchor.constraint(equalTo: self.trailingAnchor)
			])
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc func done(_ sender: Any?) {
		textField.resignFirstResponder()
	}

	private class func makeButton(title: String,
	                              action: @escaping (UIButton) -> Void) -> UIBarButtonItem
	{
		let button = ButtonClosure(type: .custom)
		button.setTitle(title, for: .normal)
		button.setTitleColor(UIColor.systemBlue, for: .normal)
		button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
		button.layer.borderWidth = 1
		button.layer.cornerRadius = 10
		button.layer.borderColor = UIColor.systemBlue.cgColor
		button.onTap = action
		return UIBarButtonItem(customView: button)
	}
}
