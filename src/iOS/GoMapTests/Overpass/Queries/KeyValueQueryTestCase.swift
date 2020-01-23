//
//  KeyValueQueryTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class KeyValueQueryTestCase: XCTestCase {
    
    func testMatchesWithObjectThatDoesNotHaveTagWithTheGivenKeyShouldReturnTrue() {
        let object = OsmBaseObject()
        
        let query = KeyValueQuery(key: "man_made", value: "surveillance")
        XCTAssertFalse(query.matches(object))
    }
    
    func testMatchesWithObjectThatDoesNotHaveTagWithTheGivenKeyButDifferentValueShouldReturnFalse() {
        let key = "man_made"
        let value = "surveillance"
        let object = OsmBaseObject.makeBaseObjectWithTag(key, value)
        
        let query = KeyValueQuery(key: key, value: "lorem-ipsum")
        XCTAssertFalse(query.matches(object))
    }
    
    func testMatchesWithObjectThatHasTagWithTheGivenKeyValueCombinationShouldReturnTrue() {
        let key = "man_made"
        let value = "surveillance"
        let object = OsmBaseObject.makeBaseObjectWithTag(key, value)
        
        let query = KeyValueQuery(key: key, value: value)
        XCTAssertTrue(query.matches(object))
    }

}
