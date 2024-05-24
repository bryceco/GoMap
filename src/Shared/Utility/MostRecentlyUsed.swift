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
	let userPrefsKey: Pref<[T]>

	var count: Int { return items.count }

	init(maxCount: Int,
	     userPrefsKey: Pref<[T]>)
	{
		self.maxCount = maxCount
		self.userPrefsKey = userPrefsKey
		items = userPrefsKey.value ?? []
	}

	/*
	 func load(withMapping: (String) -> T?) {
	 	let strings = userPrefsKey.value as! [String]? ?? []
	 	items = strings.compactMap(withMapping)
	 }

	 func save(withMapping: (T) -> String) {
	 	let strings = items.map(withMapping)
	 	userPrefsKey.value = strings
	 }
	 */

	func remove(_ item: T) {
		items.removeAll(where: { $0 == item })
		userPrefsKey.value = items
	}

	func updateWith(_ item: T) {
		items.removeAll(where: { $0 == item })
		items.insert(item, at: 0)
		while items.count > maxCount {
			items.removeLast()
		}
		userPrefsKey.value = items
	}
}
