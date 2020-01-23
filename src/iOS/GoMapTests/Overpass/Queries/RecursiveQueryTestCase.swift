//
//  RecursiveQueryTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest
@testable import Go_Map__

class RecursiveQueryTestCase: XCTestCase {
    
    func testRecursiveQueryWithNoQueriesShouldReturnFalse() {
        RecursiveQuery.Logical.allCases.forEach { logical in
            let query = RecursiveQuery(logical: logical, queries: [])
            
            XCTAssertFalse(query.matches(OsmBaseObject()))
        }
    }
    
    func testRecursiveQueryWithLogicalAndAndAllQueriesReturningTrueShouldReturnTrue() {
        let firstMatchMock = BaseObjectMatcherMock()
        let secondMatchMock = BaseObjectMatcherMock()
        let query = RecursiveQuery(logical: .and, queries: [firstMatchMock, secondMatchMock])
        
        firstMatchMock.doesMatch = true
        secondMatchMock.doesMatch = true
        
        XCTAssertTrue(query.matches(OsmBaseObject()))
    }
    
    func testRecursiveQueryWithLogicalAndAndOneQueryReturningFalseShouldReturnFalse() {
        let firstMatchMock = BaseObjectMatcherMock()
        let secondMatchMock = BaseObjectMatcherMock()
        let query = RecursiveQuery(logical: .and, queries: [firstMatchMock, secondMatchMock])
        
        firstMatchMock.doesMatch = true
        secondMatchMock.doesMatch = false
        
        XCTAssertFalse(query.matches(OsmBaseObject()))
    }
    
    func testRecursiveQueryWithLogicalOrAndAllQueriesReturningFalseShouldReturnFalse() {
        let firstMatchMock = BaseObjectMatcherMock()
        let secondMatchMock = BaseObjectMatcherMock()
        let query = RecursiveQuery(logical: .or, queries: [firstMatchMock, secondMatchMock])
        
        firstMatchMock.doesMatch = false
        secondMatchMock.doesMatch = false
        
        XCTAssertFalse(query.matches(OsmBaseObject()))
    }
    
    func testRecursiveQueryWithLogicalOrAndOneQueryReturningTrueShouldReturnTrue() {
        let firstMatchMock = BaseObjectMatcherMock()
        let secondMatchMock = BaseObjectMatcherMock()
        let query = RecursiveQuery(logical: .or, queries: [firstMatchMock, secondMatchMock])
        
        firstMatchMock.doesMatch = false
        secondMatchMock.doesMatch = true
        
        XCTAssertTrue(query.matches(OsmBaseObject()))
    }
    
    func testRecursiveQueryWithLogicalOrShouldStopAskingForMatchesWhenAMatchWasFound() {
        let firstMatchMock = BaseObjectMatcherMock()
        let secondMatchMock = BaseObjectMatcherMock()
        let query = RecursiveQuery(logical: .or, queries: [firstMatchMock, secondMatchMock])
        
        firstMatchMock.doesMatch = true
        
        XCTAssertTrue(query.matches(OsmBaseObject()))
        
        XCTAssertNil(secondMatchMock.object,
                     "Since the first query yielded a positive result, the second one should not have been evaluated.")
    }

}
