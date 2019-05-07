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
    var delegateMock: QueryFormViewModelDelegateMock!

    override func setUp() {
        super.setUp()
        
        queryParserMock = OverpassQueryParserMock()
        viewModel = QueryFormViewModel(parser: queryParserMock)
        
        delegateMock = QueryFormViewModelDelegateMock()
        viewModel.delegate = delegateMock
    }

    override func tearDown() {
        viewModel = nil
        queryParserMock = nil
        delegateMock = nil
        
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
    
    // MARK: isPreviewButtonEnabled
    
    func testIsPreviewButtonEnabledShouldInitiallyBeFalse() {
        XCTAssertFalse(viewModel.isPreviewButtonEnabled.value)
    }
    
    func testIsPreviewButtonEnabledAfterEvaluatingAValidQueryShouldBeTrue() {
        viewModel.evaluateQuery("man_made=surveillance")
        
        XCTAssertTrue(viewModel.isPreviewButtonEnabled.value)
    }
    
    func testIsPreviewButtonEnabledAfterEvaluatingAnInvalidQueryShouldBeFalse() {
        queryParserMock.mockedResult = .error("")
        viewModel.evaluateQuery("lorem ipsum dolor sit amet")
        
        XCTAssertFalse(viewModel.isPreviewButtonEnabled.value)
    }
    
    func testIsPreviewButtonEnabledAfterEvaluatingEmptyQueryShouldBeFalse() {
        viewModel.evaluateQuery("man_made=surveillance")
        viewModel.evaluateQuery("")
        
        XCTAssertFalse(viewModel.isPreviewButtonEnabled.value)
    }
    
    // MARK: presentPreview
    
    func testPresentPreviewWithEmptyQueryShouldNotNotifyDelegate() {
        viewModel.evaluateQuery("")
        
        viewModel.presentPreview()
        
        XCTAssertFalse(delegateMock.didCallPresentPreview)
    }
    
    func testPresentPreviewWithInvalidQueryShouldNotNotifyDelegate() {
        queryParserMock.mockedResult = .error("")
        viewModel.evaluateQuery("lorem ipsum dolor sit amet")
        
        viewModel.presentPreview()
        
        XCTAssertFalse(delegateMock.didCallPresentPreview)
    }
    
    func testPresentPreviewWithValidQueryShouldNotifyDelegate() {
        viewModel.evaluateQuery("man_made=surveillance")
        
        viewModel.presentPreview()
        
        XCTAssertTrue(delegateMock.didCallPresentPreview)
    }
    
    func testPresentPreviewWithValidQueryShouldNotifyDelegateWithOverpassTurboURLAndEncodedQuery() {
        let query = "type:node and man_made=surveillance and camera:mount=pole"
        viewModel.evaluateQuery(query)
        
        viewModel.presentPreview()
        
        let encodedQuery = "type%3Anode%20and%20man_made%3Dsurveillance%20and%20camera%3Amount%3Dpole"
        let expectedURL = "https://overpass-turbo.eu?w=\(encodedQuery)&R"
        XCTAssertEqual(delegateMock.previewURL, expectedURL)
    }

}
