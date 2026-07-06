//
//  DiscardedTags.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/6/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

// Represents a single entry in discarded.json.
// The value is either `true` (discard regardless of tag value)
// or a dictionary of specific values to discard (e.g. {"yes": true}).
private enum DiscardedEntry: Decodable {
	case always
	case specific(Set<String>)

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if (try? container.decode(Bool.self)) != nil {
			self = .always
		} else {
			let dict = try container.decode([String: Bool].self)
			self = .specific(Set(dict.keys))
		}
	}
}

class DiscardedTags {
	private let entries: [String: DiscardedEntry]

	required init(from data: Data) throws {
		entries = try JSONDecoder().decode([String: DiscardedEntry].self, from: data)
	}

	func contains(key: String, value: String) -> Bool {
		switch entries[key] {
		case .always:
			return true
		case let .specific(values):
			return values.contains(value)
		case nil:
			return false
		}
	}
}
