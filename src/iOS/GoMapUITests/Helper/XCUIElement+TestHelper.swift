//
//  XCUIElement+TestHelper.swift
//  GoMapUITests
//
//  Created by Wolfgang Timme on 5/8/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

extension XCUIElement {
    
    /// Clears the UI element.
    /// This method assumes that it is invoked on a text field.
    func clearTextField() {
        // Make sure that the text field has the keyboard focus.
        tap()
        
        // Enter some text so that we can actually select something, in case the text field is already empty.
        typeText(".")
        
        // Use the context menu to select the whole text.
        press(forDuration: 1.3)
        XCUIApplication().menuItems["Select All"].tap()
        
        // Reset it to an empty string.
        XCUIApplication().keys["delete"].tap()
    }
    
}
