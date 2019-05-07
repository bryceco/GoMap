//
//  QueryFormViewModelTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class QueryFormViewModelTestCase: XCTestCase {
    
    var viewModel: QueryFormViewModel!
    var queryParserMock: OverpassQueryParserMock!

    override func setUp() {
        super.setUp()
        
        queryParserMock = OverpassQueryParserMock()
        viewModel = QueryFormViewModel(parser: queryParserMock)
    }

    override func tearDown() {
        viewModel = nil
        queryParserMock = nil
        
        super.tearDown()
    }
    
    // MARK: queryText
    
    func testQueryTextShouldInitiallyBeEmpty() {
        XCTAssertTrue(viewModel.queryText.value.isEmpty)
    }
    
    // MARK: errorMessage
    
    func testErrorMessageShouldInitiallyBeEmpty() {
        XCTAssertTrue(viewModel.errorMessage.value.isEmpty)
    }
    
    func testEvaluateQueryShouldShowErrorMessageIfParserResultedInError() {
        let errorMessage = "Lorem ipsum"
        queryParserMock.mockedResult = .error(errorMessage)
        
        viewModel.evaluateQuery("**")

        XCTAssertEqual(viewModel.errorMessage.value, errorMessage)
    }
    
    func testEvaluateQueryShouldEmptyErrorMessageIfParserWasSuccessful() {
        viewModel.evaluateQuery("type:node")
        
        XCTAssertTrue(viewModel.errorMessage.value.isEmpty)
    }
    
    func testEvaluateQueryShouldEmptyErrorMessageIfQueryIsEmpty() {
        viewModel.evaluateQuery("**")
        viewModel.evaluateQuery("")
        
        XCTAssertTrue(viewModel.errorMessage.value.isEmpty)
    }
    
    // MARK: isSaveButtonEnabled
    
    func testIsSavedButtonEnabledShouldInitiallyBeFalse() {
        XCTAssertFalse(viewModel.isSaveButtonEnabled.value)
    }
    
    

}
