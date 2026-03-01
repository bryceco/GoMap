//
//  DeprecatedTags.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/28/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

class DeprecatedTags
{
	struct Entry: Decodable {
		let old: [String: String]
		let replace: [String: String]?
	}
	let entries: [Entry]

	required init(from data: Data) throws
	{
		let list = try JSONDecoder().decode([Entry].self, from: data)
		entries = list.filter { $0.old.count == 1 }
	}

	func contains(key: String, value: String) -> Bool {
		let result = entries.contains(where: {
			guard let oldValue = $0.old[key] else {
				return false
			}
			return oldValue == "*" || oldValue == value
		})
		return result
	}
}
