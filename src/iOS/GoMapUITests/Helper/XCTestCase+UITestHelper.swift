//
//  XCTestCase+UITestHelper.swift
//  GoMapUITests
//
//  Created by Wolfgang Timme on 5/6/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

extension XCTestCase {

    func waitForViewController(_ identifier: String, timeout: TimeInterval = 3.0) {
        let predicate = NSPredicate(format: "exists == 1")
        let query = XCUIApplication().navigationBars[identifier]
        let elementExistsExpectation = expectation(for: predicate, evaluatedWith: query, handler: nil)
        
        wait(for: [elementExistsExpectation], timeout: 3)
    }

}
