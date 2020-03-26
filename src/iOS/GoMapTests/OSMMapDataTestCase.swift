//
//  OSMMapDataTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/15/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest
@testable import Go_Map__

class OSMMapDataTestCase: XCTestCase {
    
    var mapData: OsmMapData!
    var userDefaults: UserDefaults!

    override func setUp() {
        userDefaults = createDedicatedUserDefaults()
        mapData = OsmMapData(userDefaults: userDefaults)
    }

    override func tearDown() {
        mapData = nil
        userDefaults = nil
    }
    
    func testSetServerShouldAddThePathSeparatorSuffixIfItDoesNotExist() {
        let hostname = "https://example.com"
        mapData.setServer(hostname)
        
        let hostnameWithPathSeparatorSuffix = "\(hostname)/"
        XCTAssertEqual(OSM_API_URL, hostnameWithPathSeparatorSuffix)
    }
    
    func testSetServerShouldNotAddThePathSeparatorSuffixIfItAlreadyExists() {
        let hostname = "https://example.com/"
        mapData.setServer(hostname)
        
        XCTAssertEqual(OSM_API_URL, hostname)
    }

}
