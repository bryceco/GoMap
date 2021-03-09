//
//  HeadingProviderMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

@testable import Go_Map__

class HeadingProviderMock: NSObject, HeadingProviding {
    var startUpdatingHeadingCalled = false
    var stopUpdatingHeadingCalled = false

    // MARK: HeadingProviding

    var delegate: HeadingProviderDelegate?

    var isHeadingAvailable: Bool = true

    func startUpdatingHeading() {
        startUpdatingHeadingCalled = true
    }

    func stopUpdatingHeading() {
        stopUpdatingHeadingCalled = true
    }
}
