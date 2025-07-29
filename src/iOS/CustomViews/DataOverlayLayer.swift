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
final class DataOverlayLayer: DrawingLayer, DrawingLayerDelegate {
	override init(mapView: MapView) {
		super.init(mapView: mapView)
		geojsonDelegate = self
	}

	var allCustom: [URL: GeoJSONFile] = [:]

	override func layoutSublayers() {
		let previous = Set(allCustom.keys)
		let current = geoJsonList.visible()
		for url in previous.subtracting(current) {
			allCustom.removeValue(forKey: url)
		}
		for url in geoJsonList.visible() {
			if allCustom[url] == nil {
				do {
					allCustom[url] = try GeoJSONFile(url: url)
				} catch {
					print("\(error)")
				}
			}
		}
		super.layoutSublayers()
	}

	// Delegate function
	func geojsonData() -> [(GeoJSONGeometry, UIColor)] {
		return allCustom.values.flatMap {
			$0.features.compactMap {
				guard let geometry = $0.geometry else { return nil }
				return (geometry, UIColor.cyan)
			}
		}
	}

	// MARK: Properties

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}

extension DataOverlayLayer: MapView.LayerOrView {
	var hasTileServer: TileServer? {
		return nil
	}

	func removeFromSuper() {
		removeFromSuperlayer()
	}
}
