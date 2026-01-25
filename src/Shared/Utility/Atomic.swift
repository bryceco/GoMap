//
//  Atomic.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/12/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

struct AtomicInt {
	private var count: Int
	private let lock = NSLock()

	init(_ count: Int) {
		self.count = count
	}

	mutating func increment(_ delta: Int = 1) {
		lock.lock(); defer { lock.unlock() }
		count += delta
	}

	mutating func decrement() {
		lock.lock(); defer { lock.unlock() }
		count -= 1
	}

	func value() -> Int {
		lock.lock(); defer { lock.unlock() }
		return count
	}
}
