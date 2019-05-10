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
        
        XCTAssertFalse(queryParserMock.didCallParse)
    }
    
    func testShowAnnotationWithActiveQueryShouldAskParserToParse() {
        let query: String? = "lorem ipsum dolor sit amet"
        questManagerMock.activeQuestQuery = query
        let object = OsmBaseObject()
        
        _ = manager.shouldShowQuestAnnotation(for: object)
        
        XCTAssertTrue(queryParserMock.didCallParse)
        XCTAssertEqual(queryParserMock.query, query)
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
