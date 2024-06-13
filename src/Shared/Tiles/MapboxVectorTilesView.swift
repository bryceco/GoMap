//
//  MapboxVectorTilesView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/4/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation
import MapLibre

class MapboxVectorTilesView: MLNMapView, MLNMapViewDelegate {
	let mapView: MapView

	init(mapView: MapView) {
		self.mapView = mapView
		super.init(frame: .zero,
				   styleURL: URL(string: "https://zelonewolf.github.io/openstreetmap-americana/style.json")!)

		// don't use MapLibre built-in gestures
		self.gestureRecognizers = nil
		self.delegate = self
		self.logoView.isHidden = true
		self.compassView.isHidden = true
		self.attributionButton.isHidden = true

		mapView.mapTransform.observe(by: self, callback: {
			let center = mapView.mapTransform.latLon(forScreenPoint: mapView.mapTransform.center)
			let zoom = mapView.mapTransform.zoom() - 1.0
			let dir = (360.0 + mapView.mapTransform.rotation() * 180 / .pi).remainder(dividingBy: 360.0)

			self.setCenter(CLLocationCoordinate2D(center),
						   zoomLevel: zoom,
						   direction: 360-dir,
						   animated: false)
		})
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func mapView(_ map:MLNMapView, didFinishLoading style: MLNStyle) {
		let locale = Locale(identifier: PresetLanguages.preferredLanguageCode())
		style.localizeLabels(into: locale)
		for source: MLNSource in style.sources {
			if let tileSource = source as? MLNTileSource {
				for attrib in tileSource.attributionInfos {
					print("\(attrib)")
				}
			}
		}
		for layer: MLNStyleLayer in style.layers {
			switch layer {
			case let layer as MLNBackgroundStyleLayer:
				break
			case let layer as MLNForegroundStyleLayer:
				switch layer {
				case let layer as MLNRasterStyleLayer:
					break
				case let layer as MLNHillshadeStyleLayer:
					break
				case let layer as MLNVectorStyleLayer:
					break
				default:
					break
				}
				break
			case let layer as MLNFillStyleLayer:
				break
			default:
				break
			}
		}
	}
}

extension MapboxVectorTilesView: TilesProvider {
	func currentTiles() -> [String] {
		return []
	}

	func zoomLevel() -> Int {
		return 18
	}

	func maxZoom() -> Int {
		return 21
	}

	func downloadTile(forKey cacheKey: String, completion: @escaping () -> Void) {
		print("xx")
	}
}

extension MapboxVectorTilesView: GetDiskCacheSize {
	func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int) {
		pSize = 0
		pCount = 0
	}
	
}

