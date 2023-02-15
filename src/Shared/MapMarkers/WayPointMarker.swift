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

	convenience init(with gpxPoint: GpxPoint) {
		var text = gpxPoint.name
		if let r1 = text.range(of: "<a "),
		   let r2 = text.range(of: "\">")
		{
			text.removeSubrange(r1.lowerBound..<r2.upperBound)
		}
		text = text.replacingOccurrences(of: "&quot;", with: "\"")

		self.init(with: gpxPoint.latLon, description: text)
	}

	override var markerIdentifier: String {
		return "waypoint-\(lat),\(lon)"
	}

	override var buttonLabel: MapMarkerButton.TextOrImage { .text("W") }
}
