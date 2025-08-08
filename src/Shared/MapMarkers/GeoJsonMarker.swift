//
//  GeoJsonMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/7/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

// A GeoJSON point with attached properties
final class GeoJsonMarker: MapMarker {
	let properties: AnyJSON

	var description: String {
		return properties.prettyPrinted()
	}

	init(with latLon: LatLon, properties: AnyJSON) {
		self.properties = properties
		super.init(latLon: latLon)
	}

	override var markerIdentifier: String {
		return "geojson-\(latLon.lat),\(latLon.lon)"
	}

	override var buttonLabel: String { "G" }
}
