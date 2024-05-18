//
//  CustomLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/29/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

import CoreLocation.CLLocation
import UIKit

// A layer in MapView that displays custom data (GeoJSON, etc) that the user wants to load
final class CustomLayer: LineDrawingLayer, GeoJSONDataSource {
	override init(mapView: MapView) {
		super.init(mapView: mapView)
		geojsonDelegate = self
	}

	var allCustom: [GeoJSONFile] = []

	func geojsonData() -> [(GeoJSONGeometry, UIColor)] {
		//let color = UIColor(red: 115 / 255.0, green: 67 / 255.0, blue: 211 / 255.0, alpha: 1.0)
		return allCustom.flatMap { $0.features.map { ($0.geometry, UIColor.cyan) } }
	}

	// Load GeoJSON from an external source
	func loadGeoJSON(_ data: Data, center: Bool) throws {
		let geo = try GeoJSONFile(data: data)

		if center,
		   let first = geo.features.first?.geometry.latLonBezierPath?.cgPath.getPoints().first
		{
			self.center(on: LatLon(lon: first.x, lat: first.y))
		}
		allCustom.append(geo)
		isHidden = false
		setNeedsLayout()
	}

	// MARK: Properties

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
