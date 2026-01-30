//
//  PresetField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/22/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

enum PresetType: String, Codable {
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

final class PresetField: CustomDebugStringConvertible {
	let identifier: String
	let jsonDict: [String: Any]

	init?(identifier: String, json: [String: Any]) {
		guard json["type"] is String else {
			return nil
		}
		self.identifier = identifier
		jsonDict = json
		guard self.usage != "changeset" else {
			// we might be able to ignore other values as well, maybe "manual"
			return nil
		}
#if DEBUG
		// validate that we don't encounter any types that aren't supported
		_ = self.type
#endif
	}

	var key: String? { jsonDict["key"] as! String? }
	var keys: [String]? { jsonDict["keys"] as! [String]? }
	var type: PresetType { PresetType(rawValue: jsonDict["type"] as! String)! }
	var defaultValue: String? { jsonDict["default"] as! String? }
	var options: [String]? { jsonDict["options"] as! [String]? }
	var autoSuggestions: Bool { (jsonDict["autoSuggestions"] as! Bool?) ?? true }
	var replacement: String? { jsonDict["replacement"] as! String? }
	var reference: [String: String]? { jsonDict["reference"] as! [String: String]? }
	var icons: [String: String]? { jsonDict["icons"] as! [String: String]? }
	var universal: Bool { (jsonDict["universal"] as! Bool?) ?? false }
	var caseSensitive: Bool { ((jsonDict["caseSensitive"] as! Int?) ?? 0) != 0 }

	// preconditions
	var geometry: [String]? { jsonDict["geometry"] as! [String]? }
	var prerequisiteTag: [String: String]? { jsonDict["prerequisiteTag"] as! [String: String]? }
	var locationSet: LocationSet? { LocationSet(withJson: jsonDict["locationSet"]) }
	var usage: String? { jsonDict["usage"] as! String? }

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

	var localizedOptions: [String: PresetTranslations.Option]? { // rename to options
		return PresetTranslations.shared.options(for: crossRef(for: "stringsCrossReference"))
	}

	var types: [String: String]? { // rename to options
		return PresetTranslations.shared.types(for: crossRef(for: "stringsCrossReference"))
	}

	func crossRef(for property: String) -> PresetField {
		var field = self
		while
			let value = field.jsonDict[property],
			let value = value as? String,
			value.hasPrefix("{"),
			value.hasSuffix("}"),
			let newField = PresetsDatabase.shared.presetFields[String(value.dropFirst().dropLast())],
			newField !== self
		{
			field = newField
		}
		return field
	}

	// Some field values can have a redirect to a different field using a {other_field} notation
	func redirected<T>(property: String) -> T? {
		let value = property == "strings"
			? jsonDict["stringsCrossReference"] ?? jsonDict["strings"]
			: jsonDict[property]
		if let value = value as? String,
		   value.hasPrefix("{"),
		   value.hasSuffix("}")
		{
			let redirect = String(value.dropFirst().dropLast())
			guard
				let newField = PresetsDatabase.shared.presetFields[redirect]
			else {
				print("bad preset redirect: \(redirect)")
				return nil
			}
			if newField === self {
				// The field has a redirect to itself, which is silly.
				// But if it's a stringsCrossReference redirect then just return the
				// value for strings (or just ignore the redirect which will give nil):
				return jsonDict[property] as? T
			}
			if let newValue: T = newField.redirected(property: property) {
				return newValue
			} else {
				return nil
			}
		}
		return value as? T
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
