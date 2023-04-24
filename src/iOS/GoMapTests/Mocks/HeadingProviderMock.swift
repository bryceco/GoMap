//
//  HeadingProviderMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import Foundation

@testable import Go_Map__

class HeadingProviderMock: HeadingProviding {
	var startUpdatingHeadingCalled = false
	var stopUpdatingHeadingCalled = false

	// MARK: HeadingProviding

	var delegate: HeadingProviderDelegate?

	var isHeadingAvailable = true

	func startUpdatingHeading() {
		startUpdatingHeadingCalled = true
	}

	func stopUpdatingHeading() {
		stopUpdatingHeadingCalled = true
	}
}
