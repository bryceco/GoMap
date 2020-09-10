//
//  RegularExpressionQueryTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/5/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class RegularExpressionQueryTestCase: XCTestCase {
    func testMatchesWithMatchingKeyButValueThatDoesNotMatchShouldReturnFalse() {
        let query = RegularExpressionQuery(key: "man_*", value: "pier|surveillance")

        let object = OsmBaseObject.makeBaseObjectWithTag("man_made", "survey_point")

        XCTAssertFalse(query.matches(object))
    }

    func testMatchesWithMatchingValueButKeyThatDoesNotMatchShouldReturnFalse() {
        let query = RegularExpressionQuery(key: "camera:type", value: "dome")

        let object = OsmBaseObject.makeBaseObjectWithTag("man_made", "dome|wall")

        XCTAssertFalse(query.matches(object))
    }

    func testMatchesWithMatchingKeyValueCombinationShouldReturnTrue() {
        let query = RegularExpressionQuery(key: "man_*", value: "pier|surveillance")

        let object = OsmBaseObject.makeBaseObjectWithTag("man_made", "surveillance")

        XCTAssertTrue(query.matches(object))
    }

    func testMatchesWithMatchingKeyValueCombinationWhenIsNegatedShouldReturnFalse() {
        let query = RegularExpressionQuery(key: "man_*", value: "pier|surveillance", isNegated: true)

        let object = OsmBaseObject.makeBaseObjectWithTag("man_made", "surveillance")

        XCTAssertFalse(query.matches(object))
    }
}
