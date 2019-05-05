//
//  OverpassQueryParserTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/4/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class OverpassQueryParserTestCase: XCTestCase {
    
    var parser: OverpassQueryParsing!

    override func setUp() {
        super.setUp()
        
        parser = OverpassQueryParser()
    }

    override func tearDown() {
        parser = nil
        
        super.tearDown()
    }
    
    // MARK: Syntax Error
    
    func testParseShouldReturnErrorForQueryStringWithError() {
        let queryString = "!!"
        let result = parser.parse(queryString)
        
        guard case let .error(errorMessage) = result else {
            XCTFail("The parser should have encountered an error.")
            return
        }
        
        XCTAssertEqual(errorMessage, "SyntaxError: Expected \"(\", \"id\", \"newer\", \"type\", \"uid\", \"user\", \"~\", Key, or string but \"!\" found.")
    }
    
    // MARK: Valid queries
    
    func testParseQueryForExistinceOfAKey() {
        let queryString = "capacity = *"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let keyExistQuery = query as? KeyExistsQuery else {
            XCTFail("The parser should have returned a query that queries for the existance of a key.")
            return
        }
        
        XCTAssertEqual(keyExistQuery.key, "capacity")
        XCTAssertFalse(keyExistQuery.isNegated)
    }
    
    func testParseQueryForNonExistinceOfAKey() {
        let queryString = "capacity != *"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let keyExistQuery = query as? KeyExistsQuery else {
            XCTFail("The parser should have returned a query that queries for the existance of a key.")
            return
        }
        
        XCTAssertEqual(keyExistQuery.key, "capacity")
        XCTAssertTrue(keyExistQuery.isNegated)
    }

}
