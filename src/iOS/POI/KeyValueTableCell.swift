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
	var priorKeyValue = ""

	// don't allow editing text while deleting
	func shouldResignFirstResponder(forState state: UITableViewCell.StateMask) -> Bool {
		return state.contains(.showingEditControl)
			|| state.contains(.showingDeleteConfirmation)
	}

	override func resignFirstResponder() -> Bool {
		text1.resignFirstResponder()
		text2.resignFirstResponder()
		return super.resignFirstResponder()
	}

	override func willTransition(to state: UITableViewCell.StateMask) {
		// don't allow editing text while deleting
		if shouldResignFirstResponder(forState: state) {
			text1.resignFirstResponder()
			text2.resignFirstResponder()
		}

		super.willTransition(to: state)
	}
}

protocol KeyValueTableCellOwner: UITableViewController {
	var allPresetKeys: [PresetKey] { get }
	var childViewPresented: Bool { get set }
	var currentTextField: UITextField? { get set }
	func keyValueEditingChanged(for kv: KeyValueTableCell)
	func keyValueEditingEnded(for kv: KeyValueTableCell)
	func pasteTags(_: [String: String])
	var keyValueDict: [String: String] { get }
}

class KeyValueTableCell: TextPairTableCell, PresetValueTextFieldOwner, UITextFieldDelegate, UITextViewDelegate {
	var textView: UITextView?
	weak var keyValueCellOwner: KeyValueTableCellOwner?
	var key: String { return text1.text ?? "" }
	var value: String { return textView?.text ?? text2.text! }

	override func awakeFromNib() {
		contentView.autoresizingMask = .flexibleHeight
		contentView.autoresizesSubviews = false

		text1.autocorrectionType = .no
		text2.autocorrectionType = .no
		text1.autocapitalizationType = .none
		text2.autocapitalizationType = .none
		text1.spellCheckingType = .no
		text2.spellCheckingType = .no

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
		text1.addTarget(self, action: #selector(textFieldEditingChanged(_:)), for: .editingChanged)

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
		keyValueCellOwner?.tableView.performBatchUpdates({
			textView?.sizeToFit()
		})
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
		textView.autocapitalizationType = .sentences
		textView.autocorrectionType = .yes
		textView.keyboardType = .default
		textView.inputAccessoryView = (textField as? PresetValueTextField)?.defaultInputAccessoryView
			?? textField.inputAccessoryView
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

	func selectTextViewFor(key: String) {
		// set text formatting options for text field
		if let preset = keyValueCellOwner?.allPresetKeys.first(where: { key == $0.tagKey }) {
			if preset.type == "textarea" {
				useTextView()
			} else {
				useTextField()
			}
		} else {
			switch key {
			case "note", "comment", "description", "fixme", "inscription", "source":
				useTextView()
				textView?.autocapitalizationType = .sentences
				textView?.autocorrectionType = .default
				textView?.spellCheckingType = .default
			default:
				useTextField()
			}
		}
	}

	// MARK: textField delegate functions

	func notifyKeyValueChange(ended: Bool) {
		if ended {
			keyValueCellOwner?.keyValueEditingEnded(for: self)
		} else {
			keyValueCellOwner?.keyValueEditingChanged(for: self)
		}
	}

	@objc func textFieldReturn(_ sender: UIView) {
		sender.resignFirstResponder()
	}

	// This function is shared between All Tags and Common Tags
	static func shouldChangeTag(origText: String,
	                            charactersIn remove: NSRange,
	                            replacementString insert: String,
	                            warningVC: KeyValueTableCellOwner?) -> Bool
	{
		let MAX_LENGTH = 255
		let newLength = origText.count - remove.length + insert.count
		let allowed = newLength <= MAX_LENGTH || insert == "\n"
		if !allowed,
		   insert.count > 1,
		   let vc = warningVC
		{
			let message = String.localizedStringWithFormat(
				NSLocalizedString("Pasting %ld characters, maximum tag length is 255", comment: ""), insert.count)
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

	func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		if textField === text2 {
			// set up textView if necessary
			selectTextViewFor(key: text1?.text ?? "")

			// if we enabled the textView then we don't want to edit the textField
			if textView != nil {
				return false
			}
		}
		return true
	}

	@objc func textFieldEditingDidBegin(_ textField: AutocompleteTextField) {
		keyValueCellOwner?.currentTextField = textField

		if textField === text1 {
			// save original value in case user changes it
			priorKeyValue = text1.text ?? ""

			// get list of keys
			let set = PresetsDatabase.shared.allTagKeys()
			let list = Array(set)
			textField.autocompleteStrings = list
		}
	}

	@objc func textFieldEditingChanged(_ textField: UITextField) {
		notifyKeyValueChange(ended: false)
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
		keyValueCellOwner?.currentTextField = text2
	}

	func textViewDidChange(_ textView: UITextView) {
		// Update underlying text field. This does not trigger a change notification.
		text2.text = self.textView?.text
		// notify owner
		notifyKeyValueChange(ended: false)
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
		guard !key.isEmpty else { return }
		let mapView = AppDelegate.shared.mapView!
		let geometry = mapView.editorLayer.selectedPrimary?.geometry() ?? .POINT
		let feature = PresetsDatabase.shared.presetFeatureMatching(tags: [key: value],
		                                                           geometry: geometry,
		                                                           location: mapView.currentRegion,
		                                                           includeNSI: false)
		let featureName: String?
		if let feature = feature,
		   feature.tags.count > 0 // not degenerate like point, line, etc.
		{
			featureName = feature.name
		} else if let preset = keyValueCellOwner?.allPresetKeys.first(where: { $0.tagKey == key }) {
			featureName = preset.name
		} else {
			featureName = nil
		}

		let spinner = UIActivityIndicatorView(style: .medium)
		spinner.frame = infoButton.bounds
		infoButton.addSubview(spinner)
		infoButton.isEnabled = false
		infoButton.titleLabel?.alpha = 0
		spinner.startAnimating()

		func showPopup(title: String?, description: String?, wikiPageTitle: String?) {
			spinner.removeFromSuperview()
			infoButton.isEnabled = true
			infoButton.titleLabel?.alpha = 1

			if let description,
			   let owner = keyValueCellOwner,
			   owner.view.window != nil
			{
				let tag = "\(key)=\(value.isEmpty ? "*" : value)"
				let alert = UIAlertController(
					title: title ?? "",
					message: "\(tag)\n\n\(description)",
					preferredStyle: .alert)
				alert.addAction(.init(title: "Done", style: .cancel, handler: nil))
				alert.addAction(.init(title: "Read more on the Wiki", style: .default) { _ in
					if let wikiPageTitle {
						let url = WikiPage.shared.urlFor(pageTitle: wikiPageTitle)
						self.openSafariWith(url: url)
					} else {
						self.openSafari()
					}
				})
				owner.present(alert, animated: true)
			} else {
				openSafari()
			}
		}

		let languageCode = PresetLanguages.preferredLanguageCode()
		if let wikiData = WikiPage.shared.wikiDataFor(key: key,
		                                              value: value,
		                                              language: languageCode,
		                                              imageWidth: 24,
		                                              update: { wikiData in
		                                              	showPopup(
		                                              		title: featureName,
		                                              		description: wikiData?.description,
		                                              		wikiPageTitle: wikiData?.pageTitle)
		                                              })
		{
			showPopup(title: featureName,
			          description: wikiData.description,
			          wikiPageTitle: wikiData.pageTitle)
		}
	}

	private func openSafariWith(url: URL) {
		guard let keyValueCellOwner else { return }
		let vc = SFSafariViewController(url: url)
		keyValueCellOwner.childViewPresented = true
		keyValueCellOwner.present(vc, animated: true)
	}

	private func openSafari() {
		guard !key.isEmpty,
		      let owner = keyValueCellOwner,
		      owner.view.window != nil
		else { return }

		let languageCode = PresetLanguages.preferredLanguageCode()
		Task {
			guard let url = await WikiPage.shared.bestWikiPage(
				forKey: key,
				value: value,
				language: languageCode)
			else {
				return
			}
			await MainActor.run {
				self.openSafariWith(url: url)
			}
		}
	}

	// MARK: PresetValueTextFieldOwner

	var allPresetKeys: [PresetKey] { return keyValueCellOwner?.allPresetKeys ?? [] }
	var childViewPresented: Bool {
		set { keyValueCellOwner?.childViewPresented = newValue }
		get { keyValueCellOwner?.childViewPresented ?? false }
	}

	var viewController: UIViewController? { return keyValueCellOwner }
	func valueChanged(for textField: PresetValueTextField, ended: Bool) {
		notifyKeyValueChange(ended: ended)
	}

	var keyValueDict: [String: String] {
		return keyValueCellOwner?.keyValueDict ?? [:]
	}
}

class KeyValueTableSection {
	typealias KeyValue = (k: String, v: String)
	private var tags: [KeyValue] = []
	weak var tableView: UITableView?

	init(tableView: UITableView) {
		self.tableView = tableView
	}

	var count: Int { tags.count }

	var allTags: [KeyValue] { tags }

	subscript(index: Int) -> KeyValue {
		get { tags[index] }
		set { tags[index] = newValue }
	}

	func keyValueDictionary() -> [String: String] {
		var dict = [String: String]()
		for (k, v) in tags {
			// strip whitespace around text
			let key = k.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			let val = v.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
			if key.count != 0, val.count != 0 {
				dict[key] = val
			}
		}
		return dict
	}

	func setWithoutSorting(_ values: [KeyValue]) {
		tags = values
	}

	func set(_ values: [KeyValue]) {
		tags = values.sorted(by: { obj1, obj2 in
			let key1 = obj1.k
			let key2 = obj2.k
			let tiger1 = key1.hasPrefix("tiger:") || key1.hasPrefix("gnis:")
			let tiger2 = key2.hasPrefix("tiger:") || key2.hasPrefix("gnis:")
			if tiger1 == tiger2 {
				return key1 < key2
			} else {
				return (tiger1 ? 1 : 0) < (tiger2 ? 1 : 0)
			}
		})
		tags.append(("", ""))
	}

	func append(_ value: KeyValue) {
		tags.append(value)
	}

	func remove(at indexPath: IndexPath) {
		tags.remove(at: indexPath.row)
		tableView?.deleteRows(at: [indexPath], with: .fade)
	}

	func keyValueEditingEnded(for pair: KeyValueTableCell) -> KeyValue? {
		guard let tableView = tableView,
		      let indexPath = tableView.indexPath(for: pair)
		else { return nil }

		let kv = (k: pair.key, v: pair.value)
		tags[indexPath.row] = kv

		if pair.key != "", pair.value != "" {
			// move the edited row up
			var index = (0..<indexPath.row).first(where: {
				tags[$0].k == "" || tags[$0].v == ""
			}) ?? indexPath.row
			if index < indexPath.row {
				tags.remove(at: indexPath.row)
				tags.insert(kv, at: index)
				tableView.moveRow(at: indexPath, to: IndexPath(row: index, section: indexPath.section))
			}

			// if we created a row that defines a key that duplicates a row with
			// the same key elsewhere then delete the other row
			while let i = tags.indices.first(where: { $0 != index && tags[$0].k == kv.k }) {
				tags.remove(at: i)
				tableView.deleteRows(at: [IndexPath(row: i, section: indexPath.section)], with: .none)
				if i < index {
					index -= 1
				}
			}

			tableView.scrollToRow(at: IndexPath(row: index, section: indexPath.section), at: .middle, animated: true)

		} else if kv.k.count != 0 || kv.v.count != 0 {
			// ensure there's a blank line either elsewhere, or create one below us
			let haveBlank = tags.first(where: { $0.k.count == 0 && $0.v.count == 0 }) != nil
			if !haveBlank {
				let newPath = IndexPath(row: indexPath.row + 1, section: indexPath.section)
				tags.insert(("", ""), at: newPath.row)
				tableView.insertRows(at: [newPath], with: .none)
			}
		}
		return kv
	}
}
