//
//  PresetField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/22/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

extension PresetField {
	enum FieldType: String, Codable {
		// Special case for the Type field, not part of id-tagging-schema.
		// This provides us a field we can use to select a different feature.
		case featureType

		// booleans
		case check
		case defaultCheck
		case onewayCheck

		// lists of presets
		case radio
		case structureRadio
		case manyCombo
		case multiCombo

		// multiple choice
		case combo
		case semiCombo
		case networkCombo
		case typeCombo
		case colour

		// custom
		case access
		case directionalCombo // "cycleway" is no longer used
		case address

		// free form text
		case text
		case number
		case email
		case identifier
		case maxweight_bridge
		case textarea
		case tel
		case url
		case roadheight
		case roadspeed
		case wikipedia
		case wikidata
		case date

		case localized
		case restrictions
	}

	enum PrerequisiteTag {
		case keyExists(key: String)
		case keyValue(key: String, value: String)
		case keyValueNot(key: String, valueNot: String)
		case keyValues(key: String, values: [String])
		case keyValuesNot(key: String, valuesNot: [String])
		case keyNot(key: String)

		func isSatisfied(by tags: [String: String]) -> Bool {
			switch self {
			case let .keyExists(key):
				return tags[key] != nil
			case let .keyValue(key, value):
				return tags[key] == value
			case let .keyValueNot(key, valueNot):
				return tags[key] != valueNot // absent key satisfies "≠ valueNot"
			case let .keyValues(key, values):
				guard let v = tags[key] else { return false }
				return values.contains(v)
			case let .keyValuesNot(key, valuesNot):
				guard let v = tags[key] else { return true } // absent key satisfies "∉ valuesNot"
				return !valuesNot.contains(v)
			case let .keyNot(key):
				return tags[key] == nil
			}
		}
	}
}

extension PresetField.PrerequisiteTag: Decodable {
	enum CodingKeys: String, CodingKey {
		case key, keyNot, value, valueNot, values, valuesNot
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if let key = try container.decodeIfPresent(String.self, forKey: .key) {
			if let value = try container.decodeIfPresent(String.self, forKey: .value) {
				self = .keyValue(key: key, value: value)
			} else if let valueNot = try container.decodeIfPresent(String.self, forKey: .valueNot) {
				self = .keyValueNot(key: key, valueNot: valueNot)
			} else if let values = try container.decodeIfPresent([String].self, forKey: .values) {
				self = .keyValues(key: key, values: values)
			} else if let valuesNot = try container.decodeIfPresent([String].self, forKey: .valuesNot) {
				self = .keyValuesNot(key: key, valuesNot: valuesNot)
			} else {
				self = .keyExists(key: key)
			}
		} else if let keyNot = try container.decodeIfPresent(String.self, forKey: .keyNot) {
			self = .keyNot(key: keyNot)
		} else {
			throw DecodingError.dataCorruptedError(forKey: .key,
			                                       in: container,
			                                       debugDescription: "bad preset prerequisiteTag")
		}
	}
}

// The raw JSON shape for a single entry in fields.json.
struct FieldJSON: Decodable {
	var type: String
	var usage: String?
	var key: String?
	var keys: [String]?
	var defaultValue: String?
	var options: [String]?
	var autoSuggestions: Bool?
	var replacement: String?
	var reference: [String: String]?
	var icons: [String: String]?
	var universal: Bool?
	var caseSensitive: Bool?
	var geometry: [String]?
	var prerequisiteTag: PresetField.PrerequisiteTag?
	var locationSet: LocationSet?
	var urlFormat: String?
	var pattern: String?
	// Cross-reference strings: either nil or a "{field_name}" redirect
	var label: String?
	var placeholder: String?
	var placeholders: String?
	var labels: String?
	var stringsCrossReference: String?
	var iconsCrossReference: String?

	enum CodingKeys: String, CodingKey {
		case type, usage, key, keys
		case defaultValue = "default"
		case options, autoSuggestions, replacement, reference, icons
		case universal, caseSensitive, geometry, prerequisiteTag, locationSet
		case urlFormat, pattern
		case label, placeholder, placeholders, labels
		case stringsCrossReference, iconsCrossReference
	}
}

final class PresetField: CustomDebugStringConvertible {
	let identifier: String

	// Eagerly evaluated stored properties
	let key: String?
	let keys: [String]?
	let type: FieldType
	let defaultValue: String?
	let options: [String]?
	let autoSuggestions: Bool
	let replacement: String?
	let reference: [String: String]?
	private let iconsRaw: [String: String]?
	let universal: Bool
	let caseSensitive: Bool

	// preconditions
	let geometry: [String]?
	let prerequisiteTag: PrerequisiteTag?
	let locationSet: LocationSet?

	// restrictions
	let urlFormat: String?
	let pattern: String?
	let usage: String?

	// Maps cross-reference property names to the field identifiers they point to.
	// Only populated when a JSON value uses the "{field_name}" redirect syntax.
	// Used by crossRef(for:) to resolve localizable properties and icons.
	private let fieldCrossRefs: [String: String]

	init(identifier: String, from json: FieldJSON) {
		guard let fieldType = FieldType(rawValue: json.type) else {
			fatalError("Unknown field type: '\(json.type)'")
		}

		self.identifier = identifier
		self.type = fieldType
		self.key = json.key
		self.keys = json.keys
		self.defaultValue = json.defaultValue
		self.options = json.options
		self.autoSuggestions = json.autoSuggestions ?? true
		self.replacement = json.replacement
		self.reference = json.reference
		self.iconsRaw = json.icons
		self.universal = json.universal ?? false
		self.caseSensitive = json.caseSensitive ?? false
		self.geometry = json.geometry
		self.prerequisiteTag = json.prerequisiteTag
		self.locationSet = json.locationSet
		self.urlFormat = json.urlFormat
		self.pattern = json.pattern
		self.usage = json.usage

		// Extract only the cross-reference values (those using "{field_name}" syntax).
		var refs = [String: String]()
		for (refKey, val) in [("label", json.label),
		                      ("placeholder", json.placeholder),
		                      ("placeholders", json.placeholders),
		                      ("labels", json.labels),
		                      ("stringsCrossReference", json.stringsCrossReference),
		                      ("iconsCrossReference", json.iconsCrossReference)]
		{
			if let val, val.hasPrefix("{"), val.hasSuffix("}") {
				refs[refKey] = String(val.dropFirst().dropLast())
			}
		}
		self.fieldCrossRefs = refs
	}

	var icons: [String: String]? { crossRef(for: "iconsCrossReference").iconsRaw }

	// localizable strings
	var localizedLabel: String? {
		return PresetTranslations.shared.label(for: crossRef(for: "label"))
	}

	var localizedPlaceholder: String? {
		return PresetTranslations.shared.placeholder(for: crossRef(for: "placeholder"))
	}

	var placeholders: [String: String]? {
		return PresetTranslations.shared.placeholders(for: crossRef(for: "placeholders"))
	}

	var labels: [String: String]? {
		return PresetTranslations.shared.labels(for: crossRef(for: "labels"))
	}

	var localizedOptions: [String: PresetTranslations.Option]? { // rename to options
		return PresetTranslations.shared.options(for: crossRef(for: "stringsCrossReference"))
	}

	var types: [String: String]? {
		return PresetTranslations.shared.types(for: crossRef(for: "stringsCrossReference"))
	}

	// Follows the "{field_name}" cross-reference chain for a given property name.
	// Returns the field whose identifier should be used for translation/icon lookups.
	func crossRef(for property: String) -> PresetField {
		var field = self
		while
			let refId = field.fieldCrossRefs[property],
			let newField = PresetsDatabase.shared.presetFields[refId],
			newField !== self
		{
			field = newField
		}
		return field
	}

	var allKeys: [String] {
		if let keys = keys {
			if let key = key {
				var all = keys
				all.append(key)
				return all
			} else {
				return keys
			}
		} else if let key = key {
			return [key]
		} else {
			return []
		}
	}

	var debugDescription: String {
		return key ?? keys!.joined(separator: ",")
	}
}
