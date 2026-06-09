//
//  TagKey.swift
//  Go Map!!
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

/// OSM tag key helpers shared by the POI editor.
enum TagKey {
	private static let exactNameLikeKeys: Set<String> = ["name", "alt_name", "old_name"]

	/// Keys that carry human-readable names and should use the same keyboard traits as `name`.
	static func isNameLike(_ key: String) -> Bool {
		guard !key.isEmpty else { return false }
		if exactNameLikeKeys.contains(key) {
			return true
		}
		return key.hasPrefix("name:")
	}

	static func autocapitalizationType(matchingNamePresetIn presets: [PresetDisplayKey])
		-> UITextAutocapitalizationType
	{
		presets.first(where: { $0.tagKey == "name" })?.autocapitalizationType ?? .words
	}

	static func autocorrectType(matchingNamePresetIn presets: [PresetDisplayKey]) -> UITextAutocorrectionType {
		presets.first(where: { $0.tagKey == "name" })?.autocorrectType ?? .no
	}

	static func applyNameLikeTraits(to textField: UITextField, presets: [PresetDisplayKey]) {
		textField.autocapitalizationType = autocapitalizationType(matchingNamePresetIn: presets)
		textField.autocorrectionType = autocorrectType(matchingNamePresetIn: presets)
		textField.spellCheckingType = textField.autocorrectionType == .no ? .no : .default
	}

	static func applyNameLikeTraits(to textView: UITextView, presets: [PresetDisplayKey]) {
		textView.autocapitalizationType = autocapitalizationType(matchingNamePresetIn: presets)
		textView.autocorrectionType = autocorrectType(matchingNamePresetIn: presets)
		textView.spellCheckingType = textView.autocorrectionType == .no ? .no : .default
	}

	/// Configure a free-form key/value value field (All Tags, Common Tags extras).
	static func configureKeyValueField(_ textField: UITextField, key: String, presets: [PresetDisplayKey]) {
		textField.autocorrectionType = .no
		textField.autocapitalizationType = .none
		textField.spellCheckingType = .no
		if isNameLike(key) {
			applyNameLikeTraits(to: textField, presets: presets)
		}
	}

	/// Configure a preset-driven value field, overriding `.none` for name-like keys.
	static func configurePresetValueField(_ textField: UITextField,
	                                      key: String,
	                                      preset: PresetDisplayKey,
	                                      presets: [PresetDisplayKey])
	{
		textField.autocapitalizationType = preset.autocapitalizationType
		textField.autocorrectionType = preset.autocorrectType
		textField.spellCheckingType = preset.autocorrectType == .no ? .no : .default
		if isNameLike(key), preset.autocapitalizationType == .none {
			applyNameLikeTraits(to: textField, presets: presets)
		}
	}

	/// Apply name-like traits when editing, if schema did not already specify capitalization.
	static func applyNameLikeOverrideIfNeeded(to textField: UITextField,
	                                            key: String,
	                                            preset: PresetDisplayKey?,
	                                            presets: [PresetDisplayKey])
	{
		guard isNameLike(key) else { return }
		if preset == nil || preset?.autocapitalizationType == .none {
			applyNameLikeTraits(to: textField, presets: presets)
		}
	}
}
