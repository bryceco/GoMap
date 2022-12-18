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

	// init from
	init(withXML node: DDXMLNode) throws {
		let gpxPoint = try GpxPoint(withXML: node)

		description = gpxPoint.desc
		super.init(lat: gpxPoint.latLon.lat, lon: gpxPoint.latLon.lon)
	}

	override var key: String {
		fatalError() // return "waypoint-()"
	}

	override var buttonLabel: String { "W" }
}
