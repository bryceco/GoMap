//
//  AutocompleteTextField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

class AutocompleteTextField: UITextField, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {
	// this needs to be shared, because sometimes we'll create a new autocomplete text field when the keyboard is already showing,
	// so it never gets a chance to retrieve the size:
	private static var s_keyboardFrame = CGRect.zero
	private static let GradientHeight: CGFloat = 20.0

	weak var realDelegate: UITextFieldDelegate?
	var completionTableView: UITableView?
	var origCellOffset: CGFloat = 0.0
	var filteredCompletions: [String] = []
	var gradientLayer: CAGradientLayer?
	var didSelectAutocomplete: (() -> Void)?

	required init?(coder: NSCoder) {
		super.init(coder: coder)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillShow(_:)),
			name: UIResponder.keyboardWillShowNotification,
			object: nil)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(keyboardWillChange(_:)),
			name: UIResponder.keyboardWillChangeFrameNotification,
			object: nil)

		super.delegate = self
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
		delegate = nil
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		assertionFailure() // not supported
	}

	override weak var delegate: UITextFieldDelegate? {
		get { realDelegate }
		set { realDelegate = newValue }
	}

	func clearFilteredCompletionsInternal() {
		filteredCompletions = []
		updateCompletionTableView()
	}

	private var allStrings: [String] = []

	var autocompleteStrings: [String] {
		get {
			return allStrings
		}
		set(strings) {
			allStrings = strings
		}
	}

	func updateAutocomplete(for text: String) {
		let text = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
		// filter completion list by current text
		if text.count != 0 {
			filteredCompletions = allStrings.filter({ $0.range(of: text, options: .caseInsensitive) != nil })
		} else {
			filteredCompletions = allStrings
		}
		// sort by prefix, then alphabetically
		filteredCompletions = filteredCompletions.sorted(by: { s1, s2 in
			let p1 = s1.hasPrefix(text)
			let p2 = s2.hasPrefix(text)
			if p1 == p2 {
				// both have, or don't have, a matching prefix, so use alphabetical
				return s1.caseInsensitiveCompare(s2) == .orderedAscending
			} else {
				// matching prefix first
				return p1
			}
		})
		updateCompletionTableView()
	}

	func keyboardFrame(from notification: Notification) -> CGRect {
		let userInfo = notification.userInfo
		let rect = (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
		return rect
	}

	@objc func keyboardWillShow(_ nsNotification: Notification) {
		AutocompleteTextField.s_keyboardFrame = keyboardFrame(from: nsNotification)

		if isEditing, filteredCompletions.count != 0 {
			updateAutocomplete()
		}
	}

	// keyboard size can change if switching languages inside keyboard, etc.
	@objc func keyboardWillChange(_ nsNotification: Notification) {
		AutocompleteTextField.s_keyboardFrame = keyboardFrame(from: nsNotification)

		if completionTableView != nil {
			let rect = frameForCompletionTableView()
			completionTableView?.frame = rect

			var rcGradient = rect
			rcGradient.size.height = AutocompleteTextField.GradientHeight

			CATransaction.begin()
			CATransaction.setAnimationDuration(0.0)
			gradientLayer?.frame = rcGradient
			CATransaction.commit()
		}
		if isEditing, filteredCompletions.count != 0 {
			updateAutocomplete()
		}
	}

	func frameForCompletionTableView() -> CGRect {
		guard let cell: UITableViewCell = superviewOfType(),
		      let tableView: UITableView = cell.superviewOfType()
		else {
			return .zero
		}

		let cellRC = cell.convert(cell.bounds, to: tableView)
		var rect = CGRect.zero
		rect.origin.x = 0
		rect.origin.y = cellRC.origin.y + cellRC.size.height
		rect.size.width = tableView.frame.size.width
		if AutocompleteTextField.s_keyboardFrame.size.height > 0 {
			let keyboardPos = tableView
				.convert(AutocompleteTextField.s_keyboardFrame, from: nil) // keyboard is in screen coordinates
			rect.size.height = keyboardPos.origin.y - rect.origin.y
		} else {
			// no on-screen keyboard (external keyboard or Mac Catalyst)
			rect.size.height = tableView.frame.size.height - cellRC.size.height
		}
		return rect
	}

	func updateCompletionTableView() {
		if filteredCompletions.count != 0 {
			if completionTableView == nil {
				let cell: UITableViewCell = superviewOfType()!
				let tableView: UITableView = cell.superviewOfType()!

				// scroll cell to top
				let indexPath = tableView.indexPath(for: cell)!
				tableView.scrollToRow(at: indexPath, at: .top, animated: false)

				if #available(iOS 15.0, *) {
					// iOS handles scrolling differently and disabling it causes visual glitches
				} else {
					tableView.isScrollEnabled = false
				}

				// cell doesn't always scroll to the same place, so give it a moment before we add the completion table
				DispatchQueue.main.async(execute: {
					// add completion table to tableview
					let rect = self.frameForCompletionTableView()
					self.completionTableView = UITableView(frame: rect, style: .plain)

					var backgroundColor = UIColor(white: 0.88, alpha: 1.0)
					if #available(iOS 13.0, *) {
						backgroundColor = UIColor.systemBackground
					}
					self.completionTableView?.backgroundColor = backgroundColor
					self.completionTableView?.separatorColor = UIColor(white: 0.7, alpha: 1.0)
					self.completionTableView?.dataSource = self
					self.completionTableView?.delegate = self
					if let view = self.completionTableView {
						tableView.addSubview(view)
					}

					self.gradientLayer = CAGradientLayer()
					self.gradientLayer?.colors = [
						UIColor(white: 0.0, alpha: 0.6).cgColor,
						UIColor(white: 0.0, alpha: 0.0).cgColor
					].compactMap { $0 }
					var rcGradient = rect
					rcGradient.size.height = AutocompleteTextField.GradientHeight
					self.gradientLayer?.frame = rcGradient
					if let layer = self.gradientLayer {
						tableView.layer.addSublayer(layer)
					}
				})
			}
			completionTableView?.reloadData()
		} else {
			completionTableView?.removeFromSuperview()
			completionTableView = nil

			gradientLayer?.removeFromSuperlayer()
			gradientLayer = nil

			if let cell: UITableViewCell = superviewOfType(),
			   let tableView: UITableView = cell.superviewOfType()
			{
				if let cellIndexPath = tableView.indexPath(for: cell) {
					tableView.scrollToRow(at: cellIndexPath, at: .middle, animated: true)
				}
				tableView.isScrollEnabled = true
			}
		}
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		text = filteredCompletions[indexPath.row]

		sendActions(for: .editingChanged)

		didSelectAutocomplete?()

		// hide completion table view
		filteredCompletions = []
		updateCompletionTableView()
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return filteredCompletions.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cellIdentifier = "Cell"
		let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier)
			?? UITableViewCell(style: .default, reuseIdentifier: cellIdentifier)

		cell.textLabel?.font = UIFont.preferredFont(forTextStyle: .body)
		cell.textLabel?.text = filteredCompletions[indexPath.row]
		return cell
	}

	func updateAutocomplete() {
		updateAutocomplete(for: text!)
	}

	// MARK: delegate

	// Forward any delegate messages to the real delegate
	func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		return realDelegate?.textFieldShouldBeginEditing?(textField) ?? true
	}

	func textFieldDidBeginEditing(_ textField: UITextField) {
		realDelegate?.textFieldDidBeginEditing?(textField)
	}

	func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
		return realDelegate?.textFieldShouldEndEditing?(textField) ?? true
	}

	func textFieldDidEndEditing(_ textField: UITextField) {
		clearFilteredCompletionsInternal()

		realDelegate?.textFieldDidEndEditing?(textField)
	}

	func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
		clearFilteredCompletionsInternal()

		if realDelegate?.textFieldDidEndEditing?(textField, reason: reason) == nil {
			realDelegate?.textFieldDidEndEditing?(textField)
		}
	}

	func textField(_ textField: UITextField,
	               shouldChangeCharactersIn range: NSRange,
	               replacementString string: String) -> Bool
	{
		let shouldChange: Bool
		if let delegate = realDelegate as? POIAllTagsViewController {
			// FIXME: forwarding to this view controller doesn't work following
			// the normal code path (Swift bug?), so hack it:
			shouldChange = delegate.textField(textField,
			                                  shouldChangeCharactersIn: range,
			                                  replacementString: string)
		} else {
			shouldChange = realDelegate?.textField?(textField,
			                                        shouldChangeCharactersIn: range,
			                                        replacementString: string) ?? true
		}

		if shouldChange {
			let newString = (text! as NSString).replacingCharacters(in: range, with: string) as String
			updateAutocomplete(for: newString)
		}
		return shouldChange
	}

	func textFieldDidChangeSelection(_ textField: UITextField) {
		if #available(iOS 13.0, *) {
			if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldDidChangeSelection(_:))) ?? false {
				realDelegate?.textFieldDidChangeSelection?(textField)
			}
		}
	}

	func textFieldShouldClear(_ textField: UITextField) -> Bool {
		let result = Bool((realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldShouldClear(_:))) ?? false
				? realDelegate?.textFieldShouldClear?(textField)
				: true) ?? false)
		if result {
			updateAutocomplete(for: "")
		}
		return result
	}

	func textFieldShouldReturn(_ textField: UITextField) -> Bool {
		if realDelegate?.responds(to: #selector(UITextFieldDelegate.textFieldShouldReturn(_:))) ?? false {
			return realDelegate?.textFieldShouldReturn?(textField) ?? false
		}
		return true
	}

// The delegate value (which will return realDelegate) is tested to determine whether
// the EditMenu functions are implemented, so these won't be called typically,
// instead they'll be called in realDelegate.
#if targetEnvironment(macCatalyst)
// Various errors on MacCatalyst for these
#else
	@available(iOS 16.0, *)
	func textField(_ textField: UITextField, editMenuForCharactersIn range: NSRange,
	               suggestedActions: [UIMenuElement]) -> UIMenu?
	{
		return realDelegate?.textField?(textField, editMenuForCharactersIn: range, suggestedActions: suggestedActions)
			?? UIMenu(children: suggestedActions)
	}

	@available(iOS 16.0, *)
	func textField(_ textField: UITextField, willPresentEditMenuWith animator: UIEditMenuInteractionAnimating) {
		realDelegate?.textField?(textField, willPresentEditMenuWith: animator)
	}

	@available(iOS 16.0, *)
	func textField(_ textField: UITextField, willDismissEditMenuWith animator: UIEditMenuInteractionAnimating) {
		realDelegate?.textField?(textField, willDismissEditMenuWith: animator)
	}
#endif
}
