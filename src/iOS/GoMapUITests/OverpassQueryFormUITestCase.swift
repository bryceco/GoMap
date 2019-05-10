//
//  OverpassQueryFormUITestCase.swift
//  GoMapUITests
//
//  Created by Wolfgang Timme on 5/6/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

class OverpassQueryFormUITestCase: XCTestCase {

    var app: XCUIApplication!
    
    override func setUp() {
        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDown() {
        app.terminate()
        app = nil
    }
    
    func testTapOnOverpassQueryMenuItemInDisplayOptionsShouldShowOverpassQueryFormViewController() {
        goToOverpassQueryViewController()
    }
    
    func testQueryTextFieldShouldInitiallyBeEmpty() {
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        XCTAssertTrue(textField.label.isEmpty)
    }
    
    func testPreviewButtonShouldInitiallyBeDisabled() {
        goToOverpassQueryViewController()
        
        let button = app.buttons["preview_button"]
        XCTAssertFalse(button.isEnabled)
    }
    
    func testErrorMessageLabelShouldInitiallyNotBePresent() {
        goToOverpassQueryViewController()
        
        let errorMessageLabel = app.staticTexts["error_message"]
        XCTAssertFalse(errorMessageLabel.exists)
    }
    
    func testEnteringAnInvalidQueryShouldDisplayAnErrorMessage() {
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText("**")
        
        let errorLabel = app.staticTexts["error_message"]
        XCTAssertTrue(errorLabel.isHittable)
    }
    
    func testEnteringAnInvalidQueryShouldDisplaySyntaxErrorMessage() {
        goToOverpassQueryViewController()

        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText("**")

        let errorLabel = app.staticTexts["error_message"]
        XCTAssertTrue(errorLabel.label.hasPrefix("SyntaxError:"))
    }
    
    func testEnteringAValidQueryShouldHideTheErrorMessageLabel() {
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText("man_made = surveillance")
        
        let errorLabel = app.staticTexts["error_message"]
        XCTAssertFalse(errorLabel.exists)
    }
    
    func testEnteringQueryAndThenRemovingAllTextShouldHideTheErrorMessageLabel() {
        goToOverpassQueryViewController()
        
        let query = "man_made = surveillance"
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText(query)
        
        let deleteCharacters = String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count)
        textField.typeText(deleteCharacters)
        
        let errorLabel = app.staticTexts["error_message"]
        XCTAssertFalse(errorLabel.exists)
    }
    
    func testTappingOnTheErrorLabelShouldDismissTheKeyboard() {
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText("**")
        
        let errorLabel = app.staticTexts["error_message"]
        errorLabel.tap()
        
        XCTAssert(app.keyboards.count == 0, "The keyboard should be dismissed")
    }
    
    // MARK: previewButton
    
    func testPreviewButtonShouldBeEnabledWhenEnteringAValidQuery() {
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText("man_made = surveillance")
        
        XCTAssertTrue(app.buttons["preview_button"].isEnabled)
    }
    
    func testPreviewButtonShouldBeDisabledWhenEnteringAnInvalidQuery() {
        let invalidQuery = "lorem ipsum dolor sit amet"
        
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText(invalidQuery)
        
        XCTAssertFalse(app.buttons["preview_button"].isEnabled)
    }
    
    func testPreviewButtonShouldBeDisabledWhenTheQueryIsEmpty() {
        let invalidQuery = "lorem ipsum dolor sit amet"
        
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText(invalidQuery)
        
        // Remove all characters.
        let deleteCharacters = String(repeating: XCUIKeyboardKey.delete.rawValue, count: invalidQuery.count)
        textField.typeText(deleteCharacters)
        
        XCTAssertFalse(app.buttons["preview_button"].isEnabled)
    }
    
    func testTappingOnPreviewButtonWhenAValidQueryWasEnteredShouldPresentThePreview() {
        goToOverpassQueryViewController()
        
        let textField = app.textViews["query_text_view"]
        textField.clearTextField()
        
        textField.tap()
        textField.typeText("man_made = surveillance")
        
        app.buttons["preview_button"].tap()
        
        let elementExistsExpectation = expectation(for: NSPredicate(format: "exists == 1"),
                                                   evaluatedWith: app.webViews.firstMatch)
        wait(for: [elementExistsExpectation], timeout: 3)
    }
    
    // MARK: Helper methods
    
    private func goToOverpassQueryViewController() {
        let button = app.buttons["display_options_button"]
        button.press(forDuration: 1.0)
        
        waitForViewController("Display")
        
        app.cells["overpass_query"].tap()
        
        waitForViewController("Overpass Query")
    }

}
