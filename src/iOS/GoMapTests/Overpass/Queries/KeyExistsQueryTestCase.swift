//
//  KeyExistsQueryTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class KeyExistsQueryTestCase: XCTestCase {
    
    func testMatchesWithTagThatExistsShouldReturnTrue() {
        let query = KeyExistsQuery(key: "highway")
        
        XCTAssertTrue(query.matches(OsmBaseObject.makeBaseObjectWithTag("highway", "residential")))
    }
    
    func testMatchesWithTagThatDoesNotExistShouldReturnFalse() {
        let query = KeyExistsQuery(key: "highway")
        
        XCTAssertFalse(query.matches(OsmBaseObject.makeBaseObjectWithTag("name", "Townhall")))
    }
    
    // MARK: Negation
    
    func testMatchesWithTagThatExistsShouldReturnFalseWhenNegatedIsSetToTrue() {
        let query = KeyExistsQuery(key: "highway", isNegated: true)
        
        XCTAssertFalse(query.matches(OsmBaseObject.makeBaseObjectWithTag("highway", "residential")))
    }
    
    func testMatchesWithTagThatDoesNotExistShouldReturnTrueWhenNegatedIsSetToTrue() {
        let query = KeyExistsQuery(key: "highway", isNegated: true)
        
        XCTAssertTrue(query.matches(OsmBaseObject.makeBaseObjectWithTag("name", "Townhall")))
    }

}
