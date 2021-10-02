//
//  MapMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit

class MapMarker {
	let buttonId: Int // a unique value we assign to track note buttons. If > 0 this is the noteID, otherwise it is assigned by us.
	let lat: Double
	let lon: Double

	// a unique identifier for a note across multiple downloads
	var key: String {
		fatalError()
	}

	private static var g_nextButtonID = 1
	static func NextButtonID() -> Int {
		g_nextButtonID += 1
		return g_nextButtonID
	}

	init(lat: Double,
	     lon: Double)
	{
		buttonId = MapMarker.NextButtonID()
		self.lat = lat
		self.lon = lon
	}

	func shouldHide() -> Bool {
		return false
	}

	var buttonLabel: String { fatalError() }
	var buttonIcon: UIImage? { nil }
}
