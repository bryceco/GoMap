//
//  MostRecentlyUsed.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/22.
//  Copyright © 2022 Bryce. All rights reserved.
//

import Foundation

// Track the N most recently used items
class MostRecentlyUsed<T: Equatable> {
	private(set) var items: [T]
	let maxCount: Int
	let userDefaultsKey: String
	let autoLoadSave: Bool

	var count: Int { return items.count }

	init(maxCount: Int,
	     userDefaultsKey: String,
	     autoLoadSave: Bool = false)
	{
		self.maxCount = maxCount
		self.userDefaultsKey = userDefaultsKey
		self.autoLoadSave = autoLoadSave
		if autoLoadSave {
			items = UserDefaults.standard.object(forKey: userDefaultsKey) as? [T] ?? []
		} else {
			items = []
		}
	}

	func load(withMapping: (String) -> T?) {
		let strings = UserDefaults.standard.object(forKey: userDefaultsKey) as? [String] ?? []
		items = strings.compactMap(withMapping)
	}

	func save(withMapping: (T) -> String) {
		let strings = items.map(withMapping)
		UserDefaults.standard.set(strings, forKey: userDefaultsKey)
	}

	func remove(_ item: T) {
		items.removeAll(where: { $0 == item })
	}

	func updateWith(_ item: T) {
		items.removeAll(where: { $0 == item })
		items.insert(item, at: 0)
		while items.count > maxCount {
			items.removeLast()
		}
		if autoLoadSave {
			UserDefaults.standard.set(items, forKey: userDefaultsKey)
		}
	}
}
