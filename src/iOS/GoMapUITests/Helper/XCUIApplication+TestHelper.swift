//
//  XCUIApplication+TestHelper.swift
//  GoMapUITests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

extension XCUIApplication {
    
    func tapBackButton() {
        navigationBars.buttons.element(boundBy: 0).tap()
    }
    
}
