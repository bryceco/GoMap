//
//  CLHeadingMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/3/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import CoreLocation

class CLHeadingMock: CLHeading {
	var mockedTrueHeading: CLLocationDirection

	init(trueHeading: CLLocationDirection = 0.0) {
		mockedTrueHeading = trueHeading

		super.init()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var trueHeading: CLLocationDirection {
		return mockedTrueHeading
	}
}
