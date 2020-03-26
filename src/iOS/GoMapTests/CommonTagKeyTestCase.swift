//
//  CommonTagKeyTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/13/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

//@testable import Go_Map__

class CommonTagKeyTestCase: XCTestCase {
    
    func testInitWithPresetsShouldPreferThePlaceholderParameterIfProvided() {
        let placeholder = "Lorem ipsum"
        
        let firstPreset = CommonTagValue(name: "Ja", details: "", tagValue: "yes")
        let secondPreset = CommonTagValue(name: "Nein", details: "", tagValue: "no")
        
        let tagKey = CommonTagKey(name: "Rückenlehne",
                                  tagKey: "backreset",
                                  defaultValue: nil,
                                  placeholder: placeholder,
                                  keyboard: .default,
                                  capitalize: .none,
                                  presets: [firstPreset, secondPreset])
        
        XCTAssertEqual(tagKey.require().placeholder, placeholder)
    }
    
    func testInitWithPresetsShouldUseTheirNamesForPlaceholder() {
        let firstPresetName = "Ja"
        let firstPreset = CommonTagValue(name: firstPresetName, details: "", tagValue: "yes")
        
        let secondPresentName = "Nein"
        let secondPreset = CommonTagValue(name: secondPresentName, details: "", tagValue: "no")
        
        let tagKey = CommonTagKey(name: "Rückenlehne",
                                  tagKey: "backreset",
                                  defaultValue: nil,
                                  placeholder: nil,
                                  keyboard: .default,
                                  capitalize: .none,
                                  presets: [firstPreset, secondPreset])
        
        XCTAssertEqual(tagKey.require().placeholder, "\(firstPresetName), \(secondPresentName)...")
    }

}
