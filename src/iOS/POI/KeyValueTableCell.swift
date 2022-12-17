//
//  KeyValueTableCell.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/22.
//  Copyright © 2022 Bryce. All rights reserved.
//

import Foundation
import SafariServices
import UIKit

class TextPairTableCell: UITableViewCell {
	@IBOutlet var isSet: UIView!
	@IBOutlet var text1: AutocompleteTextField!
	@IBOutlet var text2: AutocompleteTextField!
	@IBOutlet var infoButton: UIButton!

	override func willTransition(to state: UITableViewCell.StateMask) {
		super.willTransition(to: state)

		// don't allow editing text while deleting
		if state.rawValue != 0,
		   (UITableViewCell.StateMask.showingEditControl.rawValue != 0) ||
		   (UITableViewCell.StateMask.showingDeleteConfirmation.rawValue != 0)
		{
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

class KeyValueTableCell: TextPairTableCell, UITextFieldDelegate {
	var owner: KeyValueTableCellOwner!
	var key: String { return text1?.text ?? "" }
	var value: String { return text2?.text ?? "" }

	override func awakeFromNib() {
		text1.autocorrectionType = .no
		text2.autocorrectionType = .no

		weak var weakSelf = self
		text1.didSelectAutocomplete = {
			weakSelf?.text2.becomeFirstResponder()
		}
		text2.didSelectAutocomplete = {
			weakSelf?.text2.becomeFirstResponder()
		}
	}

	@IBAction func textFieldReturn(_ sender: UIView) {
		sender.resignFirstResponder()
	}

	func setTextAttributesForKey(key: String, textField: UITextField) {
		// set text formatting options for text field
		if let preset = owner.allPresetKeys.first(where: { key == $0.tagKey }) {
			textField.autocapitalizationType = preset.autocapitalizationType
			textField.autocorrectionType = preset.autocorrectType
		} else {
			switch key {
			case "note", "comment", "description", "fixme":
				textField.autocapitalizationType = .sentences
				textField.autocorrectionType = .yes
			default:
				textField.autocapitalizationType = .none
				textField.autocorrectionType = .no
			}
		}
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
		                            warningVC: owner)
	}

	@IBAction func textFieldEditingDidBegin(_ textField: AutocompleteTextField) {
		owner.currentTextField = textField

		let isValue = textField == text2

		if isValue {
			// set up capitalization and autocorrect
			setTextAttributesForKey(key: text1?.text ?? "", textField: text2)

			// get list of values for current key
			if let key = text1?.text,
			   key != "",
			   PresetsDatabase.shared.eligibleForAutocomplete(key)
			{
				var set: Set<String> = PresetsDatabase.shared.allTagValuesForKey(key)
				let appDelegate = AppDelegate.shared
				let values = appDelegate.mapView.editorLayer.mapData.tagValues(forKey: key)
				set = set.union(values)
				let list: [String] = Array(set)
				textField.autocompleteStrings = list
			}
		} else {
			// get list of keys
			let set = PresetsDatabase.shared.allTagKeys()
			let list = Array(set)
			textField.autocompleteStrings = list
		}
	}

	@IBAction func textFieldEditingDidEnd(_ textField: UITextField) {
		textField.text = textField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""

		updateAssociatedContent()

		if key != "", value != "" {
			// do automatic value updates for special keys
			// for example add https:// prefix to website=
			if let newValue = OsmTags.convertWikiUrlToReference(withKey: key, value: value)
				?? OsmTags.convertWebsiteValueToHttps(withKey: key, value: value)
			{
				text2.text = newValue
			}
		}
		owner.keyValueChanged(for: self)
	}

	// MARK: Accessory buttons

	private func getAssociatedColor(for cell: TextPairTableCell) -> UIView? {
		if let key = cell.text1.text,
		   let value = cell.text2.text,
		   key == "colour" || key == "color" || key.hasSuffix(":colour") || key.hasSuffix(":color")
		{
			let color = Colors.cssColorForColorName(value)
			if let color = color {
				var size = cell.text2.bounds.size.height
				size = CGFloat(round(Double(size * 0.5)))
				let square = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
				square.backgroundColor = color
				square.layer.borderColor = UIColor.black.cgColor
				square.layer.borderWidth = 1.0
				let view = UIView(frame: CGRect(x: 0, y: 0, width: size + 6, height: size))
				view.backgroundColor = UIColor.clear
				view.addSubview(square)
				return view
			}
		}
		return nil
	}

	@IBAction func openWebsite(_ sender: UIView?) {
		guard let pair: TextPairTableCell = sender?.superviewOfType(),
		      let key = pair.text1.text,
		      let value = pair.text2.text
		else { return }
		let string: String
		if key == "wikipedia" || key.hasSuffix(":wikipedia") {
			let a = value.components(separatedBy: ":")
			guard a.count >= 2,
			      let lang = a[0].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed),
			      let page = a[1].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
			else { return }
			string = "https://\(lang).wikipedia.org/wiki/\(page)"
		} else if key == "wikidata" || key.hasSuffix(":wikidata") {
			guard let page = value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
			else { return }
			string = "https://www.wikidata.org/wiki/\(page)"
		} else if value.hasPrefix("http://") || value.hasPrefix("https://") {
			// percent-encode non-ASCII characters
			string = value.addingPercentEncodingForNonASCII()
		} else {
			return
		}

		let url = URL(string: string)
		if let url = url {
			let viewController = SFSafariViewController(url: url)
			owner.present(viewController, animated: true)
		} else {
			let alert = UIAlertController(
				title: NSLocalizedString("Invalid URL", comment: ""),
				message: nil,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			owner.present(alert, animated: true)
		}
	}

	private func getWebsiteButton(for cell: TextPairTableCell) -> UIView? {
		if let key = cell.text1.text,
		   let value = cell.text2.text,
		   key == "wikipedia"
		   || key == "wikidata"
		   || key.hasSuffix(":wikipedia")
		   || key.hasSuffix(":wikidata")
		   || value.hasPrefix("http://")
		   || value.hasPrefix("https://")
		{
			let button = UIButton(type: .system)
			button.layer.borderWidth = 2.0
			button.layer.borderColor = UIColor.systemBlue.cgColor
			button.layer.cornerRadius = 15.0
			button.setTitle("🔗", for: .normal)

			button.addTarget(self, action: #selector(openWebsite(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	@IBAction func setSurveyDate(_ sender: UIView?) {
		guard let pair: TextPairTableCell = sender?.superviewOfType() else { return }

		let now = Date()
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
		dateFormatter.timeZone = NSTimeZone.local
		let text = dateFormatter.string(from: now)
		pair.text2.text = text
		owner.keyValueChanged(for: self)
	}

	private func getSurveyDateButton(for cell: TextPairTableCell) -> UIView? {
		let synonyms = [
			"check_date",
			"survey_date",
			"survey:date",
			"survey",
			"lastcheck",
			"last_checked",
			"updated",
			"checked_exists:date"
		]
		if let text = cell.text1.text,
		   synonyms.contains(text)
		{
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setSurveyDate(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	@IBAction func setDirection(_ sender: Any) {
		guard let pair: TextPairTableCell = (sender as? UIView)?.superviewOfType() else { return }

		let directionViewController = DirectionViewController(
			key: pair.text1.text ?? "",
			value: pair.text2.text,
			setValue: { [self] newValue in
				pair.text2.text = newValue
				owner.keyValueChanged(for: self)
			})
		owner.childViewPresented = true
		owner.present(directionViewController, animated: true)
	}

	private func getDirectionButton(for cell: TextPairTableCell) -> UIView? {
		let synonyms = [
			"direction",
			"camera:direction"
		]
		if let text = cell.text1.text,
		   synonyms.contains(text)
		{
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setDirection(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	@IBAction func setHeight(_ sender: UIView?) {
		guard let pair: TextPairTableCell = sender?.superviewOfType() else { return }

		if HeightViewController.unableToInstantiate(withUserWarning: owner) {
			return
		}

		let vc = HeightViewController.instantiate()
		vc.callback = { newValue in
			pair.text2.text = newValue
			self.owner.keyValueChanged(for: self)
		}
		owner.present(vc, animated: true)
		owner.childViewPresented = true
	}

	private func getHeightButton(for cell: TextPairTableCell) -> UIView? {
		if cell.text1.text == "height" {
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setHeight(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	func updateAssociatedContent() {
		let associatedView = getAssociatedColor(for: self)
			?? getWebsiteButton(for: self)
			?? getSurveyDateButton(for: self)
			?? getDirectionButton(for: self)
			?? getHeightButton(for: self)

		text2.rightView = associatedView
		text2.rightViewMode = associatedView != nil ? .always : .never
	}

	@IBAction func infoButtonPressed(_ sender: Any?) {
		guard let pair: TextPairTableCell = (sender as? UIView)?.superviewOfType() else { return }

		// show OSM wiki page
		guard let key = pair.text1.text,
		      let value = pair.text2.text,
		      !key.isEmpty
		else { return }
		let languageCode = PresetLanguages().preferredLanguageCode()
		let progress = UIActivityIndicatorView(style: .gray)
		progress.frame = pair.infoButton.bounds
		pair.infoButton.addSubview(progress)
		pair.infoButton.isEnabled = false
		pair.infoButton.titleLabel?.layer.opacity = 0.0
		progress.startAnimating()
		WikiPage.shared.bestWikiPage(forKey: key,
		                             value: value,
		                             language: languageCode)
		{ [self] url in
			progress.removeFromSuperview()
			pair.infoButton.isEnabled = true
			pair.infoButton.titleLabel?.layer.opacity = 1.0
			if let url = url,
			   owner.view.window != nil
			{
				let viewController = SFSafariViewController(url: url)
				owner.childViewPresented = true
				owner.present(viewController, animated: true)
			}
		}
	}
}
