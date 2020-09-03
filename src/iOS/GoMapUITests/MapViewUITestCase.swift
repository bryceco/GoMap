//
//  MapViewUITestCase.swift
//  GoMapUITests
//
//  Created by Wolfgang Timme on 4/11/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

class MapViewUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        app = nil
    }

    func testLongTapOnTheLocationButtonShouldPresentTheLocationSearch() {
        let button = app.buttons["location_button"]
        button.press(forDuration: 1.0)

        waitForViewController("Search for Location")
    }
}

extension XCTestCase {
    func waitForViewController(_ identifier: String, timeout _: TimeInterval = 3.0) {
        let predicate = NSPredicate(format: "exists == 1")
        let query = XCUIApplication().navigationBars[identifier]
        let elementExistsExpectation = expectation(for: predicate, evaluatedWith: query, handler: nil)

        wait(for: [elementExistsExpectation], timeout: 3)
    }
}
