//
//  KeyValueTableCell.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/22.
//  Copyright © 2022 Bryce Cogswell. All rights reserved.
//

import Foundation
import SafariServices
import UIKit

class TextPairTableCell: UITableViewCell {
	@IBOutlet var isSet: UIView!
	@IBOutlet var text1: AutocompleteTextField!
	@IBOutlet var text2: PresetValueTextField!
	@IBOutlet var infoButton: UIButton!

	// don't allow editing text while deleting
	func shouldResignFirstResponder(forState state: UITableViewCell.StateMask) -> Bool {
		return state.contains(.showingEditControl)
			|| state.contains(.showingDeleteConfirmation)
	}

	override func willTransition(to state: UITableViewCell.StateMask) {
		super.willTransition(to: state)

		// don't allow editing text while deleting
		if shouldResignFirstResponder(forState: state) {
			text1.resignFirstResponder()
			text2.resignFirstResponder()
		}
	}
}

protocol KeyValueTableCellOwner: UITableViewController {
	var allPresetKeys: [PresetKey] { get }
	var childViewPresented: Bool { get set }
	var currentTextField: UITextField? { get set }
	func keyValueChanged(for kv: KeyValueTableCell)
}

class KeyValueTableCell: TextPairTableCell, PresetValueTextFieldOwner, UITextFieldDelegate, UITextViewDelegate {
	var textView: UITextView?
	weak var keyValueCellOwner: KeyValueTableCellOwner!
	var key: String { return text1.text ?? "" }
	var value: String { return textView?.text ?? text2.text! }

	override func awakeFromNib() {
		contentView.autoresizingMask = .flexibleHeight
		contentView.autoresizesSubviews = false

		text1.autocorrectionType = .no
		text2.autocorrectionType = .no

		weak var weakSelf = self
		text1.didSelectAutocomplete = {
			weakSelf?.text2.becomeFirstResponder()
		}
		text2.didSelectAutocomplete = {
			weakSelf?.text2.becomeFirstResponder()
		}
		text2.owner = self

		text1.addTarget(self, action: #selector(textFieldReturn(_:)), for: .editingDidEndOnExit)
		text1.addTarget(self, action: #selector(textFieldEditingDidBegin(_:)), for: .editingDidBegin)
		text1.addTarget(self, action: #selector(textFieldEditingDidEnd(_:)), for: .editingDidEnd)

		text2.addTarget(self, action: #selector(textFieldReturn(_:)), for: .editingDidEndOnExit)
		text2.addTarget(self, action: #selector(textFieldEditingDidBegin(_:)), for: .editingDidBegin)
		text2.addTarget(self, action: #selector(textFieldEditingDidEnd(_:)), for: .editingDidEnd)
	}

	override func prepareForReuse() {
		textView?.removeFromSuperview()
		textView = nil
		text2.isHidden = false
	}

	override func willTransition(to state: UITableViewCell.StateMask) {
		if shouldResignFirstResponder(forState: state) {
			textView?.resignFirstResponder()
			super.willTransition(to: state)
		}
	}

	// MARK: TextView (for large text blocks)

	func updateTextViewSize() {
		// This resizes the cell to be appropriate for the content
		UIView.setAnimationsEnabled(false)
		textView?.sizeToFit()
		keyValueCellOwner.tableView.beginUpdates()
		keyValueCellOwner.tableView.endUpdates()
		UIView.setAnimationsEnabled(true)
	}

	private func createTextView(for textField: UITextField) -> UITextView {
		let textView = UITextView()
		textView.translatesAutoresizingMaskIntoConstraints = false
		textView.isScrollEnabled = false
		textView.layer.borderColor = UIColor.lightGray.cgColor
		textView.layer.borderWidth = 0.5
		textView.layer.cornerRadius = 5.0
		textView.font = text1.font // Don't copy text2 here because it might have been resized smaller
		textView.autocapitalizationType = textField.autocapitalizationType
		textView.autocorrectionType = textField.autocorrectionType
		textView.keyboardType = textField.keyboardType
		textView.inputAccessoryView = textField.inputAccessoryView
		textView.returnKeyType = .done
		textView.delegate = self
		contentView.addSubview(textView)

		// Copy all constraints from textField to textView
		for c in contentView.constraints {
			let item1 = c.firstItem === textField ? textView : c.firstItem
			let item2 = c.secondItem === textField ? textView : c.secondItem
			if item1 === textView || item2 === textView {
				NSLayoutConstraint(item: item1 as Any, attribute: c.firstAttribute, relatedBy: c.relation,
				                   toItem: item2, attribute: c.secondAttribute, multiplier: c.multiplier,
				                   constant: c.constant).isActive = true
			}
		}
		// Add constraints to force cell to grow vertically when textView expands
		textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5.0).isActive = true
		textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5.0).isActive = true
		return textView
	}

	func useTextView() {
		if textView != nil {
			return
		}
		text2.isHidden = true
		let textView = createTextView(for: text2)
		self.textView = textView
		textView.text = text2.text
		textView.selectedRange = NSRange(location: textView.text.count, length: 0)
		updateTextViewSize()
		// need to do this last because it can cause table cells to reload, interfering with the code above
		textView.becomeFirstResponder()
	}

	func useTextField() {
		guard let textView = textView else {
			return
		}
		text2.text = textView.text
		text2.isHidden = false
		textView.removeFromSuperview()
		self.textView = nil
		updateTextViewSize()
	}

	// MARK: textField delegate functions

	func notifyKeyValueChange(ended: Bool) {
		if ended {
			keyValueCellOwner.keyValueChanged(for: self)
		}
	}

	@objc func textFieldReturn(_ sender: UIView) {
		sender.resignFirstResponder()
	}

	// This function is shared between All Tags and Common Tags
	static func shouldChangeTag(origText: String,
	                            charactersIn remove: NSRange,
	                            replacementString insert: String,
	                            warningVC: UIViewController?) -> Bool
	{
		let MAX_LENGTH = 255
		let newLength = origText.count - remove.length + insert.count
		let allowed = newLength <= MAX_LENGTH || insert == "\n"
		if !allowed,
		   insert.count > 1,
		   let vc = warningVC
		{
			let format = NSLocalizedString("Pasting %@ characters, maximum tag length is 255", comment: "")
			let message = String(format: format, NSNumber(value: insert.count))
			let alert = UIAlertController(title: NSLocalizedString("Error", comment: ""),
			                              message: message,
			                              preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
			                              style: .default,
			                              handler: nil))
			vc.present(alert, animated: true)
		}
		return allowed
	}

	@objc func textField(_ textField: UITextField,
	                     shouldChangeCharactersIn remove: NSRange,
	                     replacementString insert: String) -> Bool
	{
		guard let origText = textField.text else { return false }
		return Self.shouldChangeTag(origText: origText,
		                            charactersIn: remove,
		                            replacementString: insert,
		                            warningVC: keyValueCellOwner)
	}

	@objc func textFieldEditingDidBegin(_ textField: AutocompleteTextField) {
		keyValueCellOwner.currentTextField = textField

		if textField === text1 {
			// get list of keys
			let set = PresetsDatabase.shared.allTagKeys()
			let list = Array(set)
			textField.autocompleteStrings = list
		}
	}

	@objc func textFieldEditingDidEnd(_ textField: UITextField) {
		if textField === text1 {
			text2.key = text1.text ?? ""
		}
		notifyKeyValueChange(ended: true)
	}

	// MARK: textView delegate functions

	func textViewDidBeginEditing(_ textView: UITextView) {
		// set the current textField to the underlying textField
		keyValueCellOwner.currentTextField = text2
	}

	func textViewDidChange(_ textView: UITextView) {
		updateTextViewSize()
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		notifyKeyValueChange(ended: true)
		useTextField()
	}

	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			textView.resignFirstResponder()
			return false
		}
		return true
	}

	// MARK: Info button

	@IBAction func infoButtonPressed(_ sender: Any?) {
		// show OSM wiki page
		guard let key = text1.text else { return }
		let languageCode = PresetLanguages.preferredLanguageCode()
		let progress = UIActivityIndicatorView(style: .gray)
		progress.frame = infoButton.bounds
		infoButton.addSubview(progress)
		infoButton.isEnabled = false
		infoButton.titleLabel?.layer.opacity = 0.0
		progress.startAnimating()
		WikiPage.shared.bestWikiPage(forKey: key,
		                             value: value,
		                             language: languageCode)
		{ [self] url in
			progress.removeFromSuperview()
			infoButton.isEnabled = true
			infoButton.titleLabel?.layer.opacity = 1.0
			if let url = url,
			   keyValueCellOwner.view.window != nil
			{
				let viewController = SFSafariViewController(url: url)
				keyValueCellOwner.childViewPresented = true
				keyValueCellOwner.present(viewController, animated: true)
			}
		}
	}

	// MARK: PresetValueTextFieldOwner

	var allPresetKeys: [PresetKey] { return keyValueCellOwner.allPresetKeys }
	var childViewPresented: Bool {
		set { keyValueCellOwner.childViewPresented = newValue }
		get { keyValueCellOwner.childViewPresented }
	}

	var viewController: UIViewController { return keyValueCellOwner }
	func valueChanged(for textField: PresetValueTextField, ended: Bool) {
		notifyKeyValueChange(ended: ended)
	}
}
