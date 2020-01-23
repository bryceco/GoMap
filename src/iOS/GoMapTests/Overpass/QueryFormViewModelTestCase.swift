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
    var questManagerMock: QuestManagerMock!
    var delegateMock: QueryFormViewModelDelegateMock!

    override func setUp() {
        super.setUp()
        
        queryParserMock = OverpassQueryParserMock()
        questManagerMock = QuestManagerMock()
        viewModel = QueryFormViewModel(parser: queryParserMock,
                                       questManager: questManagerMock)
        
        delegateMock = QueryFormViewModelDelegateMock()
        viewModel.delegate = delegateMock
    }

    override func tearDown() {
        viewModel = nil
        queryParserMock = nil
        questManagerMock = nil
        delegateMock = nil
        
        super.tearDown()
    }
    
    // MARK: queryText
    
    func testQueryTextShouldBeTheActiveQuestQuery() {
        let query = "camera:mount = wall"
        questManagerMock.activeQuestQuery = query
        
        // Re-create the view model so that it reads from the manager.
        viewModel = QueryFormViewModel(parser: queryParserMock,
                                       questManager: questManagerMock)
        
        XCTAssertEqual(viewModel.queryText.value, query)
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
    
    func testIsPreviewButtonEnabledShouldInitiallyBeFalseIfTheActiveQuestQueryIsNil() {
        questManagerMock.activeQuestQuery = nil
        
        // Re-create the view model so that it reads from the manager.
        viewModel = QueryFormViewModel(parser: queryParserMock,
                                       questManager: questManagerMock)
        
        XCTAssertFalse(viewModel.isPreviewButtonEnabled.value)
    }
    
    func testIsPreviewButtonEnabledShouldInitiallyBeTrueIfTheActiveQuestQueryWasNotNil() {
        questManagerMock.activeQuestQuery = "man_made=surveillance"
        
        // Re-create the view model so that it reads from the manager.
        viewModel = QueryFormViewModel(parser: queryParserMock,
                                       questManager: questManagerMock)
        
        XCTAssertTrue(viewModel.isPreviewButtonEnabled.value)
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
    
    // MARK: viewWillDisappear
    
    func testViewWillDisappearShouldSetTheActiveQuestToNilWhenTheQueryIsNotValid() {
        queryParserMock.mockedResult = .error("")
        viewModel.evaluateQuery("lorem ipsum dolor sit amet")
        
        viewModel.viewWillDisappear()
        
        XCTAssertNil(questManagerMock.activeQuestQuery)
    }
    
    func testViewWillDisappearShouldSetTheActiveQuestToNilWhenParserProducedEmptyResult() {
        queryParserMock.mockedResult = .success(nil)
        viewModel.evaluateQuery("abc")
        
        viewModel.viewWillDisappear()
        
        XCTAssertNil(questManagerMock.activeQuestQuery)
    }
    
    func testViewWillDisappearShouldSetTheActiveQuestToTheGivenQueryWhenParserProducedAResultThatIsNotEmpty() {
        let query = "man_made=surveillance"
        viewModel.evaluateQuery(query)
        
        viewModel.viewWillDisappear()
        
        XCTAssertEqual(questManagerMock.activeQuestQuery, query)
    }
    
    func testViewWillDisappearShouldNotSetTheActiveQuestToNilWhenTheViewModelIsRecreated() {
        let query = "man_made=surveillance"
        
        let firstViewModel = QueryFormViewModel(parser: queryParserMock, questManager: questManagerMock)
        firstViewModel.evaluateQuery(query)
        
        firstViewModel.viewWillDisappear()
        
        let secondViewModel = QueryFormViewModel(parser: queryParserMock, questManager: questManagerMock)
        secondViewModel.viewWillDisappear()
        
        XCTAssertEqual(questManagerMock.activeQuestQuery, query)
    }

}
