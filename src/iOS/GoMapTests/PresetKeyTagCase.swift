//
//  PresetKeyTagCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/13/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import XCTest

@testable import Go_Map__

class PresetKeyTagCase: XCTestCase {
	func testInitWithPresetsShouldPreferThePlaceholderParameterIfProvided() {
		let placeholder = "Lorem ipsum"

		let firstPreset = PresetDisplayValue(name: "Ja", details: "", icon: nil, tagValue: "yes")
		let secondPreset = PresetDisplayValue(name: "Nein", details: "", icon: nil, tagValue: "no")

		let tagKey = PresetDisplayKey(name: "Rückenlehne",
		                              type: .text,
		                              tagKey: "backreset",
		                              defaultValue: nil,
		                              placeholder: placeholder,
		                              keyboard: .default,
		                              capitalize: .none,
		                              autocorrect: .no,
									  presetValues: [firstPreset, secondPreset])

		XCTAssertEqual(tagKey.placeholder, placeholder)
	}

	func testInitWithPresetsShouldUseTheirNamesForPlaceholder() {
		let firstPresetName = "Ja"
		let firstPreset = PresetDisplayValue(name: firstPresetName, details: "", icon: nil, tagValue: "yes")

		let secondPresentName = "Nein"
		let secondPreset = PresetDisplayValue(name: secondPresentName, details: "", icon: nil, tagValue: "no")

		let tagKey = PresetDisplayKey(name: "Rückenlehne",
		                              type: .text,
		                              tagKey: "backreset",
		                              defaultValue: nil,
		                              placeholder: nil,
		                              keyboard: .default,
		                              capitalize: .none,
		                              autocorrect: .no,
									  presetValues: [firstPreset, secondPreset])

		XCTAssertEqual(tagKey.placeholder, "\(firstPresetName), \(secondPresentName)...")
	}
}
