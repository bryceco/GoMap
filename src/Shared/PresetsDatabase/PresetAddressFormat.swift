//
//  PresetAddressFormat.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/22/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

struct PresetAddressFormat: Decodable {
	let countryCodes: [String]?
	let addressKeys: [[String]]

	enum CodingKeys: String, CodingKey {
		case countryCodes
		case addressKeys = "format"
	}

	/// Street-level address keys appropriate for a short pushpin-style display.
	private static let streetLevelKeys: Set<String> = [
		"housename", "housenumber", "street", "place",
		"unit", "block_number", "floor", "conscriptionnumber"
	]

	/// Keys whose values are often mixed-script (e.g. "5A") and must not decide the label's base direction.
	private static let isolatedKeys: Set<String> = [
		"housenumber", "unit", "block_number", "floor", "conscriptionnumber"
	]

	/// Formats a short street-level address from the given tags,
	/// using this format's key ordering but only including street-level fields.
	/// Returns nil if no street-level address tags are present.
	func formattedStreetAddress(from tags: [String: String]) -> String? {
		var parts: [String] = []
		for row in addressKeys {
			for key in row {
				// Handle "street+place" alternative notation
				let alternatives = key.split(separator: "+").map(String.init)

				// Try each alternative, using the first street-level one that has a value
				for alt in alternatives {
					if Self.streetLevelKeys.contains(alt),
					   let value = tags["addr:\(alt)"],
					   !value.isEmpty
					{
						if Self.isolatedKeys.contains(alt) {
							// Add BIDI control characters: FSI & PDI
							// This says don't look at this text for determining layout direction
							parts.append("\u{2068}\(value)\u{2069}")
						} else {
							parts.append(value)
						}
						break
					}
				}
			}
		}
		return parts.isEmpty ? nil : parts.joined(separator: " ")
	}
}
