//
//  MostRecentlyUsed.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/22.
//  Copyright © 2022 Bryce Cogswell. All rights reserved.
//

import Foundation

// Track the N most recently used items
class MostRecentlyUsed<T: Equatable> {
	private(set) var items: [T]
	let maxCount: Int
	let userPrefsKey: UserPrefs.Pref
	let autoLoadSave: Bool

	var count: Int { return items.count }

	init(maxCount: Int,
	     userPrefsKey: UserPrefs.Pref,
	     autoLoadSave: Bool = true)
	{
		self.maxCount = maxCount
		self.userPrefsKey = userPrefsKey
		self.autoLoadSave = autoLoadSave
		if autoLoadSave {
			items = UserPrefs.shared.object(forKey: userPrefsKey) as? [T] ?? []
		} else {
			items = []
		}
	}

	func load(withMapping: (String) -> T?) {
		let strings = UserPrefs.shared.object(forKey: userPrefsKey) as? [String] ?? []
		items = strings.compactMap(withMapping)
	}

	func save(withMapping: (T) -> String) {
		let strings = items.map(withMapping)
		UserPrefs.shared.set(object: strings, forKey: userPrefsKey)
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
			UserPrefs.shared.set(object: items, forKey: userPrefsKey)
		}
	}
}
