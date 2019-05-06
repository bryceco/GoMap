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
    
    func testParseQueryForKeyValuePair() {
        let queryString = "man_made = surveillance"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let keyValueQuery = query as? KeyValueQuery else {
            XCTFail("The parser should have returned a query that queries for a tag's key/value pair.")
            return
        }
        
        XCTAssertEqual(keyValueQuery.key, "man_made")
        XCTAssertEqual(keyValueQuery.value, "surveillance")
        XCTAssertFalse(keyValueQuery.isNegated)
    }
    
    func testInvokingParseVeryQuicklyWithAlteringValuesShouldResetExceptionAfterEveryEncounter() {
        let invalidQueryString = "**"
        let validQueryString = "man_made = surveillance"
        
        for iteration in 1...20 {
            let useValidQuery = iteration % 2 == 0
            let queryToUse = useValidQuery ? validQueryString : invalidQueryString
            
            let result = parser.parse(queryToUse)
            switch result {
            case .error(_):
                XCTAssertFalse(useValidQuery,
                               "The parser should return an error if the query is _not_ valid.")
            case .success(_):
                XCTAssertTrue(useValidQuery,
                              "The parser should return success if the query was valid.")
            }
        }
    }
    
    func testParseQueryForAbsenceOfKeyValuePair() {
        let queryString = "man_made != surveillance"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let keyValueQuery = query as? KeyValueQuery else {
            XCTFail("The parser should have returned a query that queries for a tag's key/value pair.")
            return
        }
        
        XCTAssertEqual(keyValueQuery.key, "man_made")
        XCTAssertEqual(keyValueQuery.value, "surveillance")
        XCTAssertTrue(keyValueQuery.isNegated)
    }
    
    func testParseLikeQuery() {
        let queryString = "\"man_made\" ~= \"pier|surveillance\""
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let regularExpressionQuery = query as? RegularExpressionQuery else {
            XCTFail("The parser should have returned a query that queries for a tag with regular expressions.")
            return
        }
        
        XCTAssertEqual(regularExpressionQuery.key, "man_made")
        XCTAssertEqual(regularExpressionQuery.value, "pier|surveillance")
    }
    
    func testParseLikeLikeQuery() {
        let queryString = "~ \"man_*\" ~= \"pier|surveillance\""
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let regularExpressionQuery = query as? RegularExpressionQuery else {
            XCTFail("The parser should have returned a query that queries for a tag with regular expressions.")
            return
        }
        
        XCTAssertEqual(regularExpressionQuery.key, "man_*")
        XCTAssertEqual(regularExpressionQuery.value, "pier|surveillance")
    }
    
    func testParseSubstrQueryShouldResultInRegularExpressionQuery() {
        let queryString = "man_made:ll"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let regularExpressionQuery = query as? RegularExpressionQuery else {
            XCTFail("The parser should have returned a query that queries for a tag with regular expressions.")
            return
        }
        
        XCTAssertEqual(regularExpressionQuery.key, "man_made")
        XCTAssertEqual(regularExpressionQuery.value, ".*ll.*")
    }
    
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

    func testParseQueryShouldIgnoreUnexpectedTypes() {
        let queryString = "type:lorem-ipsum"
        let result = parser.parse(queryString)

        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }

        XCTAssertNil(query)
    }
    
    func testParseQueryForType() {
        let queryString = "type:way"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let typeQuery = query as? TypeQuery else {
            XCTFail("The parser should have returned a query that queries for the type.")
            return
        }
        
        XCTAssertEqual(typeQuery.type, .way)
    }
    
    func testParserQueryWithRecursiveQueryAndLogicalAnd() {
        let queryString = "man_made != * and camera:type != *"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let recursiveQuery = query as? RecursiveQuery else {
            XCTFail("The parser should have returned a recursive query.")
            return
        }
        
        XCTAssertEqual(recursiveQuery.logical, .and)
        XCTAssertEqual(recursiveQuery.queries.count, 2)
    }
    
    func testParserQueryWithRecursiveQueryAndLogicalOr() {
        let queryString = "man_made != * or camera:type != *"
        let result = parser.parse(queryString)
        
        guard case let .success(query) = result else {
            XCTFail("The parser should have successfully parsed the query.")
            return
        }
        
        guard let recursiveQuery = query as? RecursiveQuery else {
            XCTFail("The parser should have returned a recursive query.")
            return
        }
        
        XCTAssertEqual(recursiveQuery.logical, .or)
        XCTAssertEqual(recursiveQuery.queries.count, 2)
    }

}
