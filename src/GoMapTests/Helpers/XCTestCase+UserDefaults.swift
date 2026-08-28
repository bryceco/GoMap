//
//  XCTestCase+UserDefaults.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/15/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import XCTest

extension XCTestCase {
	/// Creates `UserDefaults` that use the test case' name as the `suitename`.
	///
	/// - Returns: A `UserDefaults` instance that is dedicated for this test case.
	func createDedicatedUserDefaults() -> UserDefaults? {
		let testCaseName = String(describing: self)

		return UserDefaults(suiteName: testCaseName)
	}
}
