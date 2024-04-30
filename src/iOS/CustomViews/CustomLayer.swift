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
		let geo: GeoJSON = try JSONDecoder().decode(GeoJSON.self, from: data)
		var lines: [LineShapeLayer] = []

		switch geo.coordinates {
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
