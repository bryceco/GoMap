//
//  OSMMapDataTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/15/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

@testable import Go_Map__
import XCTest

class OSMMapDataTestCase: XCTestCase {
	var mapData: OsmMapData!
	var userDefaults: UserDefaults!

	override func setUp() {
		userDefaults = createDedicatedUserDefaults()
		mapData = OsmMapData()
	}

	override func tearDown() {
		mapData = nil
		userDefaults = nil
	}

	func testSetServerShouldAddThePathSeparatorSuffixIfItDoesNotExist() {
		let hostname = "https://example.com"
		let hostnameWithPathSeparatorSuffix = "\(hostname)/"
		XCTAssertEqual(OsmServer.serverForUrl(string: hostname)?.serverURL.absoluteString,
					   hostnameWithPathSeparatorSuffix)
	}

	func testSetServerShouldNotAddThePathSeparatorSuffixIfItAlreadyExists() {
		let hostname = "https://example.com/"
		XCTAssertEqual(OsmServer.serverForUrl(string: hostname)?.serverURL.absoluteString,
					   hostname)
	}
}
