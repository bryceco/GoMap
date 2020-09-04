//
//  OsmNode_DirectionTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/10/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest
@testable import Go_Map__

class OsmNode_DirectionTestCase: XCTestCase {
    
    func testLowerBoundOfDirectionShouldBeNotFoundIfNoDirectionTagExists() {
        let node = OsmNode()
        
        XCTAssertEqual(node.direction.lowerBound, NSNotFound)
    }
    
    func testDirectionShouldUseTheDirectionTagForLowerBound() {
        let key = "direction"
        let direction = 42
        
        let node = OsmNode()
        node.constructTag(key, value: "\(direction)")
        
        XCTAssertEqual(node.direction.lowerBound, direction)
    }
    
    func testDirectionShouldUseTheCameraDirectionTagForLowerBound() {
        let key = "camera:direction"
        let direction = 42
        
        let node = OsmNode()
        node.constructTag(key, value: "\(direction)")
        
        XCTAssertEqual(node.direction.lowerBound, direction)
    }
    
    func testDirectionShouldParseCardinalDirectionToLowerBound() {
        let key = "camera:direction"
        
        let cardinalDirectionToDegree: [String: Int] = ["N": 0,
                                                        "NE": 45,
                                                        "E": 90,
                                                        "SE": 135,
                                                        "S": 180,
                                                        "SW": 225,
                                                        "W": 270,
                                                        "NW": 315]
        for (cardinalDirection, expectedDirection) in cardinalDirectionToDegree {
            let node = OsmNode()
            node.constructTag(key, value: cardinalDirection)
            
            XCTAssertEqual(node.direction.lowerBound, expectedDirection)
        }
    }

}
