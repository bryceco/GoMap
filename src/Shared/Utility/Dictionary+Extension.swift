//
//  Dictionary+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/23/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

extension Dictionary {
	// a version of mapValues that also lets the transform inspect the key
	func mapValuesWithKeys<T>(_ transform: (_ key: Key, _ value: Value) throws -> T) rethrows -> [Key: T] {
		var result = [Key: T]()
		result.reserveCapacity(count)
		for (key, val) in self {
			result[key] = try transform(key, val)
		}
		return result
	}

	func compactMapValuesWithKeys<T>(_ transform: (_ key: Key, _ value: Value) throws -> T?) rethrows -> [Key: T] {
		var result = [Key: T]()
		result.reserveCapacity(count)
		for (key, val) in self {
			if let t = try transform(key, val) {
				result[key] = t
			}
		}
		return result
	}
}
