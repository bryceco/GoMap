//
//  MapViewQuestAnnotationManagerTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/10/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class MapViewQuestAnnotationManagerTestCase: XCTestCase {
    
    var manager: MapViewQuestAnnotationManaging!
    var questManagerMock: QuestManagerMock!
    var queryParserMock: OverpassQueryParserMock!

    override func setUp() {
        super.setUp()
        
        questManagerMock = QuestManagerMock()
        queryParserMock = OverpassQueryParserMock()
        manager = MapViewQuestAnnotationManager(questManager: questManagerMock,
                                                queryParser: queryParserMock)
    }

    override func tearDown() {
        manager = nil
        questManagerMock = nil
        queryParserMock = nil
        
        super.tearDown()
    }
    
    func testShowAnnotationWithoutActiveQueryShouldNotAskParserToParse() {
        let query: String? = nil
        questManagerMock.activeQuestQuery = query
        let object = OsmBaseObject()
        
        _ = manager.shouldShowQuestAnnotation(for: object)
        
        XCTAssertEqual(queryParserMock.parseCallCounter, 0)
    }
    
    func testShowAnnotationWithActiveQueryShouldAskParserToParse() {
        let query: String? = "lorem ipsum dolor sit amet"
        questManagerMock.activeQuestQuery = query
        let object = OsmBaseObject()
        
        _ = manager.shouldShowQuestAnnotation(for: object)
        
        XCTAssertEqual(queryParserMock.parseCallCounter, 1)
        XCTAssertEqual(queryParserMock.query, query)
    }
    
    func testShowAnnotationWithActiveQueryThatIsValidShouldOnlyAskParserToParseIfQueryWasChanged() {
        let object = OsmBaseObject()
        
        questManagerMock.activeQuestQuery = "man_made = surveillance"
        
        // For the first query, act as if the result did not match.
        let negativeMatcher = BaseObjectMatcherMock()
        negativeMatcher.doesMatch = false
        queryParserMock.mockedResult = .success(negativeMatcher)
        
        for _ in 0...10 {
            XCTAssertFalse(manager.shouldShowQuestAnnotation(for: object))
        }
        XCTAssertEqual(queryParserMock.parseCallCounter, 1)
        
        // Now change the query.
        questManagerMock.activeQuestQuery = "camera:mount = wall"
        
        // For the second query, act as if the result matched.
        let positiveMatcher = BaseObjectMatcherMock()
        positiveMatcher.doesMatch = true
        queryParserMock.mockedResult = .success(positiveMatcher)
        
        for _ in 0...10 {
            XCTAssertTrue(manager.shouldShowQuestAnnotation(for: object))
        }
        XCTAssertEqual(queryParserMock.parseCallCounter, 2)
    }
    
    func testShowAnnotationWithQueryThatCausesParserErrorShouldReturnFalse() {
        let query: String? = "lorem ipsum dolor sit amet"
        questManagerMock.activeQuestQuery = query
        queryParserMock.mockedResult = .error("An error occurred.")
        
        let object = OsmBaseObject()
        XCTAssertFalse(manager.shouldShowQuestAnnotation(for: object))
    }
    
    func testShowAnnotationWithQueryThatResultsInAnEmptyResultShouldReturnFalse() {
        let query: String? = "lorem"
        questManagerMock.activeQuestQuery = query
        queryParserMock.mockedResult = .success(nil)
        
        let object = OsmBaseObject()
        XCTAssertFalse(manager.shouldShowQuestAnnotation(for: object))
    }
    
    func testShowAnnotationWithValidQueryAskMatcherIfTheGivenObjectMatches() {
        let query: String? = "man_made = surveillance"
        questManagerMock.activeQuestQuery = query
        
        let matcher = BaseObjectMatcherMock()
        queryParserMock.mockedResult = .success(matcher)
        
        let object = OsmBaseObject()
        XCTAssertFalse(manager.shouldShowQuestAnnotation(for: object))
        
        XCTAssertEqual(matcher.object, object)
    }

}
