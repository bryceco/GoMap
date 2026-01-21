//
//  PresetValueTextField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/1/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import SafariServices
import UIKit

protocol PresetValueTextFieldOwner: AnyObject {
	var allPresetKeys: [PresetDisplayKey] { get }
	var viewController: UIViewController? { get }
	var keyValueDict: [String: String] { get }
	func valueChanged(for textField: PresetValueTextField, ended: Bool)
}

class PresetValueTextField: AutocompleteTextField, PanoramaxDelegate {
	weak var owner: PresetValueTextFieldOwner!
	var defaultInputAccessoryView: UIView?

	var key: String {
		didSet {
			if key != oldValue {
				updateAssociatedContent()
			}
		}
	}

	var presetKey: PresetDisplayKey? {
		didSet {
			if let preset = presetKey {
				key = preset.tagKey
			}
		}
	}

	// UITextField will modify the value without telling us, so we can't trust oldValue here
	private var oldText: String?
	override var text: String? {
		didSet {
			if text != oldText {
				oldText = text
				self.updateAssociatedContent()
			}
		}
	}

	override init(frame: CGRect) {
		key = ""
		super.init(frame: frame)
		setEventNotifications()
	}

	required init?(coder: NSCoder) {
		key = ""
		super.init(coder: coder)
		setEventNotifications()
	}

	private func notifyValueChange(ended: Bool) {
		owner?.valueChanged(for: self, ended: ended)
	}

	private func updateTextAttributesForKey(_ key: String) {
		// set text formatting options for text field
		inputAccessoryView = defaultInputAccessoryView
		keyboardType = .default
		autocorrectionType = .no
		autocapitalizationType = .none
		returnKeyType = .done
		smartDashesType = .no
		smartQuotesType = .no

		if let preset = presetKey ?? owner.allPresetKeys.first(where: { key == $0.tagKey }) {
			autocapitalizationType = preset.autocapitalizationType
			autocorrectionType = preset.autocorrectType
			keyboardType = preset.keyboardType

			if preset.keyboardType == .phonePad {
				inputAccessoryView = TelephoneToolbar(forTextField: self, frame: frame)
			}
		} else {
			switch key {
			case "note", "comment", "description", "fixme", "inscription", "source":
				autocapitalizationType = .sentences
			case "phone", "contact:phone", "fax", "contact:fax":
				keyboardType = .phonePad
				inputAccessoryView = TelephoneToolbar(forTextField: self, frame: frame)
			case "maxspeed":
				keyboardType = .numbersAndPunctuation
			default:
				if OsmTags.isKey(key, variantOf: "website") {
					keyboardType = .URL
				}
			}
		}
		spellCheckingType = autocorrectionType == .no ? .no : .default
	}

	// MARK: UITextField delegate

	private func setEventNotifications() {
		addTarget(self, action: #selector(textFieldEditingDidBegin(_:)), for: .editingDidBegin)
		addTarget(self, action: #selector(textFieldEditingChanged(_:)), for: .editingChanged)
		addTarget(self, action: #selector(textFieldEditingDidEnd(_:)), for: .editingDidEnd)
		addTarget(self, action: #selector(textFieldEditingDidEndOnExit(_:)), for: .editingDidEndOnExit)
	}

	@objc func textFieldEditingDidBegin(_ textField: AutocompleteTextField) {
		updateTextAttributesForKey(key)

		textColor = nil

		if key != "",
		   PresetsDatabase.shared.eligibleForAutocomplete(key)
		{
			var set: Set<String> = PresetsDatabase.shared.allTagValuesForKey(key)
			let appDelegate = AppDelegate.shared
			let values = appDelegate.mapView.mapData.tagValues(forKey: key)
			set = set.union(values)
			let list: [String] = Array(set)
			autocompleteStrings = list
		}
	}

	@objc func textFieldEditingChanged(_ textField: AutocompleteTextField) {
		notifyValueChange(ended: false)
	}

	@objc func textFieldEditingDidEndOnExit(_ textField: UITextField) {
		textField.resignFirstResponder()
	}

	@objc func textFieldEditingDidEnd(_ textField: UITextField) {
		DbgAssert(textField === self)
		var value = text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		if key != "", value != "" {
			// if the field has a units toggle then apply the proper unit string
			if let unitToggle = textField.rightView as? UnitToggleButton {
				if OsmTags.alphabeticPortionOf(text: value) == nil,
				   let number = OsmTags.numericPortionOf(text: value)
				{
					// user didn't supply units, so get them from toggle
					if let newUnits = unitToggle.stringForSelection() {
						value = number + " " + newUnits
					}
				} else {
					// update toggle if user provided explicit units
					unitToggle.setSelection(forString: value)
				}
			}

			if let yesNo = textField.rightView as? TristateYesNoButton {
				yesNo.setSelection(forString: value)
			}

			// do automatic value updates for special keys
			// add https:// prefix to website=
			if let newValue = OsmTags.convertWikiUrlToReference(withKey: key, value: value)
				?? OsmTags.convertWebsiteValueToHttps(withKey: key, value: value)
				?? OsmTags.fixUpOpeningHours(withKey: key, value: value)
			{
				value = newValue
			}
		}
		text = value
		updateAssociatedContent()
		notifyValueChange(ended: true)
	}

	// MARK: Accessory buttons

	private func updateAssociatedContent() {
		// Swift doesn't like too many ??'s so we break it into pieces 🤷‍♂️
		let associatedView1 = getSurveyDateButton()
			?? getAssociatedColor()
			?? getOpeningHoursButton()
			?? getWebsiteButton()
			?? getDirectionButton()
		let associatedView2 = getHeightButton()
			?? getYesNoButton(keyValueDict: owner?.keyValueDict ?? [:])
			?? getUnitsButton()
			?? getPhotographButton()

		rightView = associatedView1 ?? associatedView2
		rightViewMode = rightView != nil ? .always : .never
		if #available(iOS 13.0, *) {
			// great
		} else {
			rightView?.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
		}
	}

	// MARK: Color preview

	private func getAssociatedColor() -> UIView? {
		if OsmTags.isKey(key, variantOf: "colour") || OsmTags.isKey(key, variantOf: "color"),
		   let value = text,
		   let color = Colors.cssColorForColorName(value.lowercased())
		{
			var size = bounds.size.height
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
		return nil
	}

	// MARK: Open website button

	@IBAction func openWebsite(_ sender: UIView?) {
		guard let value = text,
		      let viewController = owner.viewController
		else { return }
		let string: String
		if OsmTags.isKey(key, variantOf: "wikipedia") {
			let a = value.components(separatedBy: ":")
			guard a.count >= 2,
			      let lang = a[0].addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
			else { return }
			let page = a.dropFirst()
				.map({ $0.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? "" })
				.joined(separator: ":")
			string = "https://\(lang).wikipedia.org/wiki/\(page)"
		} else if OsmTags.isKey(key, variantOf: "wikidata") {
			guard let page = value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)
			else { return }
			string = "https://www.wikidata.org/wiki/\(page)"
		} else if value.hasPrefix("http://") || value.hasPrefix("https://") {
			// percent-encode non-ASCII characters
			string = value.addingPercentEncodingForNonASCII()
		} else {
			return
		}

		if let url = URL(string: string) {
			let safariVC = SFSafariViewController(url: url)
			viewController.present(safariVC, animated: true)
		} else {
			let alert = UIAlertController(
				title: NSLocalizedString("Invalid URL", comment: ""),
				message: nil,
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			viewController.present(alert, animated: true)
		}
	}

	private func getWebsiteButton() -> UIView? {
		guard key != "",
		      let value = text,
		      value != ""
		else { return nil }
		if OsmTags.isKey(key, variantOf: "website") ||
			OsmTags.isKey(key, variantOf: "wikipedia") ||
			OsmTags.isKey(key, variantOf: "wikidata") ||
			value.hasPrefix("http://") ||
			value.hasPrefix("https://")
		{
			let button = UIButton(type: .custom)
#if targetEnvironment(macCatalyst)
// button doesn't get styling because it doesn't fit
#else
			button.layer.borderWidth = 2.0
			button.layer.borderColor = UIColor.systemBlue.cgColor
			button.layer.cornerRadius = 15.0
#endif
			button.setTitle("🔗", for: .normal)

			button.addTarget(self, action: #selector(openWebsite(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	// MARK: Survey date button

	@IBAction func setSurveyDate(_ sender: UIView?) {
		let now = Date()
		let dateFormatter = ISO8601DateFormatter()
		dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
		dateFormatter.timeZone = NSTimeZone.local
		text = dateFormatter.string(from: now)
		notifyValueChange(ended: false)
		notifyValueChange(ended: true)
	}

	private func getSurveyDateButton() -> UIView? {
		if OsmTags.isKeySurveyDate(key) {
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setSurveyDate(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	// MARK: Set direction button

	@IBAction func setDirection(_ sender: Any) {
		let directionViewController = DirectionViewController(
			key: key,
			value: text,
			setValue: { [weak self] newValue in
				self?.text = newValue
				self?.notifyValueChange(ended: false)
				self?.notifyValueChange(ended: true)
			})
		resignFirstResponder()
		guard let viewController = owner.viewController else { return }
		viewController.present(directionViewController, animated: true)
	}

	private func getDirectionButton() -> UIView? {
		let synonyms = [
			"direction",
			"camera:direction"
		]
		if synonyms.contains(key) {
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(setDirection(_:)), for: .touchUpInside)
			return button
		}
		return nil
	}

	// MARK: Set height button

	@IBAction func setHeight(_ sender: UIView?) {
		guard let viewController = owner.viewController else { return }
		if HeightViewController.unableToInstantiate(withUserWarning: viewController) {
			return
		}

		let vc = HeightViewController.instantiate()
		vc.callback = { [weak self] newValue in
			self?.text = newValue
			self?.notifyValueChange(ended: false)
			self?.notifyValueChange(ended: true)
		}
		resignFirstResponder()
		viewController.present(vc, animated: true)
	}

	private func getHeightButton() -> UIView? {
		guard key == "height",
		      !ProcessInfo.processInfo.isMacCatalystApp
		else {
			return nil
		}
		let button = UIButton(type: .contactAdd)
		button.addTarget(self, action: #selector(setHeight(_:)), for: .touchUpInside)
		return button
	}

	// MARK: Yes/No tristate button

	// Yes/No tristate is different from other accessories because it doesn't
	// display the text when it is selected. Because other parts of the code
	// expect the text to be present we instead hide the text.
	private func getYesNoButton(keyValueDict: [String: String]) -> UIView? {
		guard let presetKey = presetKey,
		      presetKey.isYesNo()
		else {
			textColor = nil
			return nil
		}
		let button = TristateYesNoButton()
		if let values = presetKey.presetValues,
		   let value = values.first?.tagValue
		{
			// it's a defaultCheck button, which sets a specific tag value instead of "yes"
			button.setTagValueFor(yes: value)
		}
		var value = presetKey.tagValueForPrettyName(text ?? "")
		let isCulvert = presetKey.tagKey == "tunnel" && keyValueDict["waterway"] != nil && value == "culvert"
		if isCulvert {
			// Special hack for tunnel=culvert when used with waterways:
			value = "yes"
		}
		button.setSelection(forString: value)
		if let string = button.stringForSelection() {
			// the string is "yes"/"no"
			text = isCulvert ? "culvert" : string
			textColor = .clear
		} else {
			// display the string iff we don't recognize it (or it's nil)
			textColor = nil
			text = presetKey.prettyNameForTagValue(value)
		}
		button.onSelect = { newValue in
			var newValue = newValue
			if presetKey.tagKey == "tunnel", keyValueDict["waterway"] != nil {
				// Special hack for tunnel=culvert when used with waterways:
				// See https://github.com/openstreetmap/iD/blob/1ee45ee1f03f0fe4d452012c65ac6ff7649e229f/modules/ui/fields/radio.js#L307
				if newValue == "yes" {
					newValue = "culvert"
				} else {
					newValue = nil // "no" isn't allowed
				}
			}
			self.textColor = button.selectedSegmentIndex == 1 ? nil : .clear
			self.text = newValue
			self.resignFirstResponder()
			self.notifyValueChange(ended: true)
		}
		return button
	}

	// MARK: MPH/KPH-style toggle button

	private func getUnitsButton() -> UIView? {
		guard let presetKey = presetKey,
		      let units = OsmTags.unitsFor(key: presetKey.tagKey),
		      units.count == 2
		else { return nil }

		let button = UnitToggleButton(values: units)
		button.onSelect = { newValue in
			// update units on existing value
			if let number = OsmTags.numericPortionOf(text: self.text) {
				let v = newValue == nil ? String(number) : number + " " + newValue!
				self.text = v
				self.notifyValueChange(ended: true)
			}

			// Update user preferences for units
			var dict = UserPrefs.shared.preferredUnitsForKeys.value ?? [:]
			dict[presetKey.tagKey] = newValue
			UserPrefs.shared.preferredUnitsForKeys.value = dict
		}

		button.setSelection(forString: ((text?.count ?? 0) > 0 ? text : nil)
			?? UserPrefs.shared.preferredUnitsForKeys.value?[presetKey.tagKey]
			?? "")
		return button
	}

	// MARK: Opening Hours button

	private func getOpeningHoursButton() -> UIView? {
#if !targetEnvironment(macCatalyst)
#if arch(arm64) || arch(x86_64) // old architectures don't support SwiftUI
		if #available(iOS 14.0, *) {
			guard OsmTags.isKey(key, variantOf: "opening_hours") else {
				return nil
			}
			let button = UIButton(type: .contactAdd)
			button.addTarget(self, action: #selector(openingHours(_:)), for: .touchUpInside)
			return button
		}
#endif
#endif
		return nil
	}

	@available(iOS 14.0, *)
	@objc func openingHours(_ sender: Any?) {
		resignFirstResponder()
		let vc = OpeningHoursRecognizerController.with(onAccept: { newValue in
			self.text = newValue
			self.owner.viewController?.navigationController?.popViewController(animated: true)
			self.notifyValueChange(ended: false)
			self.notifyValueChange(ended: true)
		}, onCancel: {
			self.owner.viewController?.navigationController?.popViewController(animated: true)
		}, onRecognize: { _ in
		})
		owner.viewController?.navigationController?.pushViewController(vc, animated: true)
	}

	// MARK: Photograph button (image, panoramax, etc)

	var panoramaxKey: String?
	private func getPhotographButton() -> UIView? {
#if targetEnvironment(macCatalyst)
		return nil // camera not available
#else
		if #available(iOS 13.0, *),
		   OsmTags.isKey(key, variantOf: "panoramax")
		{
			let button = UIButton(type: .custom)
			button.setImage(UIImage(systemName: "camera"), for: .normal)
			button.addTarget(self, action: #selector(openPanoramaxViewController(_:)), for: .touchUpInside)
			return button
		}
		return nil
#endif
	}

	func panoramaxUpdate(photoID: String) {
		// Because the table cells can reload while taking the photo we
		// need to locate the correct cell again:
		guard let tableView: UITableView = superviewOfType() else {
			return
		}
		guard let cell = tableView.visibleCells.compactMap({
			let c: PresetValueTextField? = $0.subviewOfType(where: {
				$0.key == self.panoramaxKey
			})
			return c
		}).first
		else {
			return
		}
		// update text
		cell.text = photoID
		cell.notifyValueChange(ended: false)
		cell.notifyValueChange(ended: true)
	}

	@available(iOS 13.0, *)
	@objc func openPanoramaxViewController(_ sender: Any?) {
		resignFirstResponder()

		// save our key value so we can locate the correct cell when we come back
		panoramaxKey = key

		let vc = PanoramaxViewController.create()
		vc.panoramax = PanoramaxServer(serverURL: URL(string: "https://panoramax.openstreetmap.fr")!)
		vc.photoID = text ?? ""
		vc.delegate = self
		owner.viewController?.present(vc, animated: true)
	}
}
