//
//  TagKeyTests.swift
//  GoMapTests
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

@testable import Go_Map__
import XCTest

class TagKeyTests: XCTestCase {
	func testIsNameLikePositiveCases() {
		let positive = ["name", "name:en", "name:zh-Hans", "alt_name", "old_name"]
		for key in positive {
			XCTAssertTrue(TagKey.isNameLike(key), "expected name-like: \(key)")
		}
	}

	func testIsNameLikeNegativeCases() {
		let negative = ["namesake", "name_source", ""]
		for key in negative {
			XCTAssertFalse(TagKey.isNameLike(key), "expected not name-like: \"\(key)\"")
		}
	}
}
