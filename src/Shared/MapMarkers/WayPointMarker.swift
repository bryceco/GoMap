//
//  WayPoint.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

// A GPX waypoint
class WayPointMarker: MapMarker {
	let description: String

	init(with latLon: LatLon, description: String) {
		self.description = description
		super.init(lat: latLon.lat, lon: latLon.lon)
	}

	override var key: String {
		return "waypoint-\(lat),\(lon)"
	}

	override var buttonLabel: String { "W" }
}
