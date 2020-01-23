//
//  TypeQueryTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class TypeQueryTestCase: XCTestCase {
    
    // MARK: Type: node
    
    func testMatchesWithTypeNodeShouldMatchNode() {
        let query = TypeQuery(type: .node)
        let object = OsmNode()
        
        XCTAssertTrue(query.matches(object))
    }
    
    func testMatchesWithTypeNodeShouldNotMatchAnyOtherObject() {
        let query = TypeQuery(type: .node)
        
        // Objects that this query should _not_ match.
        let otherObjects: [OsmBaseObject] = [OsmBaseObject(), OsmWay(), OsmRelation()]
        
        otherObjects.forEach {
            XCTAssertFalse(query.matches($0))
        }
    }
    
    // MARK: Type: way
    
    func testMatchesWithTypeWayShouldMatchWay() {
        let query = TypeQuery(type: .way)
        let object = OsmWay()
        
        XCTAssertTrue(query.matches(object))
    }
    
    func testMatchesWithTypeWayShouldNotMatchAnyOtherObject() {
        let query = TypeQuery(type: .way)
        
        // Objects that this query should _not_ match.
        let otherObjects: [OsmBaseObject] = [OsmBaseObject(), OsmNode(), OsmRelation()]
        
        otherObjects.forEach {
            XCTAssertFalse(query.matches($0))
        }
    }
    
    // MARK: Type: relation
    
    func testMatchesWithTypeRelationShouldMatchRelation() {
        let query = TypeQuery(type: .relation)
        let object = OsmRelation()
        
        XCTAssertTrue(query.matches(object))
    }
    
    func testMatchesWithTypeRelationShouldNotMatchAnyOtherObject() {
        let query = TypeQuery(type: .relation)
        
        // Objects that this query should _not_ match.
        let otherObjects: [OsmBaseObject] = [OsmBaseObject(), OsmNode(), OsmWay()]
        
        otherObjects.forEach {
            XCTAssertFalse(query.matches($0))
        }
    }
    
}
