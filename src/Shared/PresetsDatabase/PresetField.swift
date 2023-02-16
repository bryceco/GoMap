//
//  PresetField.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/22/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

struct LocationSet {
	let include: [String]?
	let exclude: [String]?

	init?(withJson json: Any?) {
		guard let json = json as? [String: Any] else { return nil }
		include = json["include"] as? [String]
		exclude = json["exclude"] as? [String]
	}

	func contains(countryCode: String) -> Bool {
		if let includeList = include,
		   !includeList.map({ $0.lowercased() }).contains(countryCode)
		{
			return false
		}
		if let excludeList = exclude,
		   excludeList.map({ $0.lowercased() }).contains(countryCode)
		{
			return false
		}
		return true
	}
}

final class PresetField {
	let jsonDict: [String: Any]

	init?(withJson json: [String: Any]) {
		guard json["type"] is String else { return nil }
		jsonDict = json
	}

	var key: String? { jsonDict["key"] as! String? }
	var keys: [String]? { jsonDict["keys"] as! [String]? }
	var type: String { jsonDict["type"] as! String }
	var defaultValue: String? { jsonDict["default"] as! String? }
	var options: [String]? { jsonDict["options"] as! [String]? }
	var autoSuggestions: Bool { (jsonDict["autoSuggestions"] as! Bool?) ?? true }
	var replacement: String? { jsonDict["replacement"] as! String? }
	var reference: [String: String]? { jsonDict["reference"] as! [String: String]? }

	// preconditions
	var geometry: [String]? { jsonDict["geometry"] as! [String]? }
	var prerequisiteTag: [String: String]? { jsonDict["prerequisiteTag"] as! [String: String]? }
	var locationSet: LocationSet? { LocationSet(withJson: jsonDict["locationSet"]) }

	// localizable strings
	var placeholder: String? { redirected(property: "placeholder") as String? }
	var placeholders: [String: Any]? { jsonDict["placeholders"] as! [String: Any]? }
	var label: String? { redirected(property: "label") as String? }
	var strings: [String: String]? { redirected(property: "strings") as [String: String]? }
	var types: [String: String]? { jsonDict["types"] as! [String: String]? }

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
			if let newField = PresetsDatabase.shared.presetFields[redirect],
			   let newValue: T = newField.redirected(property: property)
			{
				return newValue
			}
		}
		return value as? T
	}
}
