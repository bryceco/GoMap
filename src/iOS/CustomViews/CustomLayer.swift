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
final class CustomLayer: LineDrawingLayer {
	private(set) var allLayers: [LineShapeLayer] = []

	override init(mapView: MapView) {
		super.init(mapView: mapView)
	}

	override func allLineShapeLayers() -> [LineShapeLayer] {
		return allLayers
	}

	func center(on point: LatLon) {
		mapView.centerOn(latLon: point, metersWide: 20.0)
	}

	// Load GeoJSON from an external source
	func loadGeoJSON(_ data: Data, center: Bool) throws {
		let geo: GeoJSONFile = try JSONDecoder().decode(GeoJSONFile.self, from: data)
		var lines: [LineShapeLayer] = []
		let color = UIColor(red: 115 / 255.0, green: 67 / 255.0, blue: 211 / 255.0, alpha: 1.0)

		for feature in geo.features {
			switch feature.geometry.coordinates {
			case let .polygon(poly):
				for line in poly {
					let shape = LineShapeLayer(with: line.map { LatLon(x: $0[0], y: $0[1]) })
					lines.append(shape)
				}
			case let .multiPolygon(multi):
				for poly in multi {
					for line in poly {
						let shape = LineShapeLayer(with: line.map { LatLon(x: $0[0], y: $0[1]) })
						lines.append(shape)
					}
				}
			}
		}
		for line in lines {
			line.color = color
		}
		if center,
		   let first = lines.first?.firstPoint
		{
			self.center(on: first)
		}
		allLayers = lines
		isHidden = false
		setNeedsLayout()
	}

	// MARK: Properties

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
