//
//  AutocompleteTextField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

class AutocompleteTextField: UITextField, UITableViewDataSource, UITableViewDelegate {
	// this needs to be shared, because sometimes we'll create a new autocomplete text field when the keyboard is already showing,
	// so it never gets a chance to retrieve the size:
	private static var s_keyboardFrame = CGRect.zero
	private static let GradientHeight: CGFloat = 20.0

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

		addTarget(self, action: #selector(editingChanged), for: .editingChanged)
		addTarget(self, action: #selector(editingEnded), for: .editingDidEnd)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		assertionFailure() // not supported
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
		guard let cell = superviewOfType(UITableViewCell.self),
		      let tableView = cell.superviewOfType(UITableView.self)
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
				guard
					let cell = superviewOfType(UITableViewCell.self),
					let tableView = cell.superviewOfType(UITableView.self),
					let indexPath = tableView.indexPath(for: cell)
				else { return }
				// scroll cell to top
				tableView.scrollToRow(at: indexPath, at: .top, animated: false)

				if #available(iOS 15, *),
				   ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26
				{
					// iOS 15 ..< iOS 26, handles scrolling differently and disabling it causes visual glitches
					tableView.isScrollEnabled = true
				} else {
					tableView.isScrollEnabled = false
				}

				// cell doesn't always scroll to the same place, so give it a moment before we add the completion table
				DispatchQueue.main.async(execute: {
					// add completion table to tableview
					let backgroundColor: UIColor
					if #available(iOS 13.0, *) {
						backgroundColor = UIColor.systemBackground
					} else {
						backgroundColor = UIColor(white: 0.88, alpha: 1.0)
					}

					let rect = self.frameForCompletionTableView()
					let view = UITableView(frame: rect, style: .plain)
					view.backgroundColor = backgroundColor
					view.separatorColor = UIColor(white: 0.7, alpha: 1.0)
					view.dataSource = self
					view.delegate = self
					tableView.addSubview(view)
					self.completionTableView = view

					let layer = CAGradientLayer()
					layer.colors = [
						UIColor(white: 0.0, alpha: 0.6).cgColor,
						UIColor(white: 0.0, alpha: 0.0).cgColor
					]
					var rcGradient = rect
					rcGradient.size.height = AutocompleteTextField.GradientHeight
					layer.frame = rcGradient
					tableView.layer.addSublayer(layer)
					self.gradientLayer = layer
				})
			}
			completionTableView?.reloadData()
		} else {
			completionTableView?.removeFromSuperview()
			completionTableView = nil

			gradientLayer?.removeFromSuperlayer()
			gradientLayer = nil

			if let cell = superviewOfType(UITableViewCell.self),
			   let tableView = cell.superviewOfType(UITableView.self)
			{
				if let cellIndexPath = tableView.indexPath(for: cell) {
					tableView.scrollToRow(at: cellIndexPath, at: .middle, animated: true)
				}
				tableView.isScrollEnabled = true
			}
		}
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		guard indexPath.row < filteredCompletions.count else { return }

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
		// shouldn't need this check but we got an out-of-range crash report
		if indexPath.row < filteredCompletions.count {
			cell.textLabel?.text = filteredCompletions[indexPath.row]
		} else {
			cell.textLabel?.text = ""
		}
		return cell
	}

	func updateAutocomplete() {
		updateAutocomplete(for: text ?? "")
	}

	@objc private func editingChanged() {
		updateAutocomplete()
	}

	@objc private func editingEnded() {
		clearFilteredCompletionsInternal()
	}

	override func paste(_ sender: Any?) {
		// Check whether they are pasting a set of tags
		if let pb = UIPasteboard.general.string,
		   let tags = OsmTags.tagsForString(pb)
		{
			// try to find an ancestor that we can notify
			var view: UIView? = self
			while view != nil {
				if let cell = view as? KeyValueTableCell {
					cell.keyValueCellOwner?.pasteTags(tags)
					return
				}
				view = view?.superview
			}
		}

		// Do a regular paste
		super.paste(sender)
	}
}
