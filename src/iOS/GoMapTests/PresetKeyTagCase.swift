//
//  PresetKeyTagCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/13/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class PresetKeyTagCase: XCTestCase {
    
    func testInitWithPresetsShouldPreferThePlaceholderParameterIfProvided() {
        let placeholder = "Lorem ipsum"
        
        let firstPreset = PresetValue(name: "Ja", details: "", tagValue: "yes").require()
        let secondPreset = PresetValue(name: "Nein", details: "", tagValue: "no").require()
        
        let tagKey = PresetKey(name: "Rückenlehne",
                                  featureKey: "backreset",
                                  defaultValue: nil,
                                  placeholder: placeholder,
                                  keyboard: .default,
                                  capitalize: .none,
                                  presets: [firstPreset, secondPreset])
        
        XCTAssertEqual(tagKey.require().placeholder, placeholder)
    }
    
    func testInitWithPresetsShouldUseTheirNamesForPlaceholder() {
        let firstPresetName = "Ja"
        let firstPreset = PresetValue(name: firstPresetName, details: "", tagValue: "yes").require()
        
        let secondPresentName = "Nein"
        let secondPreset = PresetValue(name: secondPresentName, details: "", tagValue: "no").require()
        
        let tagKey = PresetKey(name: "Rückenlehne",
                                  featureKey: "backreset",
                                  defaultValue: nil,
                                  placeholder: nil,
                                  keyboard: .default,
                                  capitalize: .none,
                                  presets: [firstPreset, secondPreset])
        
        XCTAssertEqual(tagKey.require().placeholder, "\(firstPresetName), \(secondPresentName)...")
    }

}
