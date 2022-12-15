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
	private(set) var list: [T]
	let maxCount: Int
	let userDefaultsKey: String

	init(maxCount: Int, userDefaultsKey: String) {
		self.maxCount = maxCount
		self.userDefaultsKey = userDefaultsKey
		list = UserDefaults.standard.object(forKey: userDefaultsKey) as? [T] ?? []
	}

	func updateWith(_ item: T) {
		// update recently used list
		list.removeAll(where: { $0 == item })
		list.insert(item, at: 0)
		if list.count > maxCount {
			list.removeLast()
		}
		UserDefaults.standard.set(list, forKey: userDefaultsKey)
	}
}
