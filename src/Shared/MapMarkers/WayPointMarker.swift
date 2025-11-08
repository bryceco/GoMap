//
//  WayPointMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

// A GPX waypoint
final class WayPointMarker: MapMarker {
	let description: NSAttributedString

	init(with latLon: LatLon, description: NSAttributedString) {
		self.description = description
		super.init(latLon: latLon)
	}

	convenience init(with gpxPoint: GpxPoint) {
		let name: NSAttributedString
		if let data = gpxPoint.name.data(using: .utf8),
		   let attr = try? NSAttributedString(data: data,
		                                      options: [.documentType: NSAttributedString.DocumentType.html,
		                                                .characterEncoding: String.Encoding.utf8.rawValue],
		                                      documentAttributes: nil)
		{
			name = attr
		} else {
			name = NSAttributedString(string: gpxPoint.name)
		}
		self.init(with: gpxPoint.latLon, description: name)
	}

	override var markerIdentifier: String {
		return "waypoint-\(latLon.lat),\(latLon.lon)"
	}

	override var buttonLabel: String { "W" }
}
