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

	func testConfigureKeyValueFieldAppliesNameTraits() {
		let field = UITextField()
		let namePreset = PresetDisplayKey(name: "Name",
		                                    type: .text,
		                                    tagKey: "name",
		                                    defaultValue: nil,
		                                    placeholder: nil,
		                                    keyboard: .default,
		                                    capitalize: .words,
		                                    autocorrect: .no,
		                                    presetValues: nil)
		TagKey.configureKeyValueField(field, key: "name:de", presets: [namePreset])
		XCTAssertEqual(field.autocapitalizationType, .words)
		XCTAssertEqual(field.autocorrectionType, .no)
		XCTAssertEqual(field.spellCheckingType, .no)
	}

	func testConfigureKeyValueFieldResetsNonNameKeys() {
		let field = UITextField()
		field.autocapitalizationType = .words
		TagKey.configureKeyValueField(field, key: "ref", presets: [])
		XCTAssertEqual(field.autocapitalizationType, .none)
		XCTAssertEqual(field.autocorrectionType, .no)
	}

	func testConfigurePresetValueFieldOverridesNoneForNameLikeKeys() {
		let field = UITextField()
		let namePreset = PresetDisplayKey(name: "Name",
		                                    type: .text,
		                                    tagKey: "name",
		                                    defaultValue: nil,
		                                    placeholder: nil,
		                                    keyboard: .default,
		                                    capitalize: .words,
		                                    autocorrect: .no,
		                                    presetValues: nil)
		let altPreset = PresetDisplayKey(name: "Alt Name",
		                                 type: .text,
		                                 tagKey: "alt_name",
		                                 defaultValue: nil,
		                                 placeholder: nil,
		                                 keyboard: .default,
		                                 capitalize: .none,
		                                 autocorrect: .no,
		                                 presetValues: nil)
		TagKey.configurePresetValueField(field, key: "alt_name", preset: altPreset, presets: [namePreset])
		XCTAssertEqual(field.autocapitalizationType, .words)
	}
}
