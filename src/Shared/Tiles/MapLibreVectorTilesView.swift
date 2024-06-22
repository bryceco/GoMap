//
//  MapLibreVectorTilesView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/4/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation
import MapLibre

class MapLibreVectorTilesView: MLNMapView, MLNMapViewDelegate {
	let mapView: MapView
	let tileServer: TileServer

	init(mapView: MapView, tileServer: TileServer) {
		self.mapView = mapView
		self.tileServer = tileServer
		super.init(frame: .zero,
		           styleURL: URL(string: tileServer.url)!)

		// don't use MapLibre built-in gestures
		gestureRecognizers = nil
		delegate = self
		logoView.isHidden = true
		compassView.isHidden = true
		attributionButton.isHidden = true

		let transformCallback = { [weak self] in
			guard let self = self else { return }
			let center = mapView.mapTransform.latLon(forScreenPoint: mapView.mapTransform.center)
			let zoom = mapView.mapTransform.zoom() - 1.0
			let dir = (360.0 + mapView.mapTransform.rotation() * 180 / .pi).remainder(dividingBy: 360.0)

			self.setCenter(CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon),
			               zoomLevel: zoom,
			               direction: 360 - dir,
			               animated: false)
		}
		transformCallback()
		mapView.mapTransform.observe(by: self, callback: transformCallback)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {}

	func mapView(_ map: MLNMapView, didFinishLoading style: MLNStyle) {
		let locale = Locale(identifier: PresetLanguages.preferredLanguageCode())
		style.localizeLabels(into: locale)
		for source: MLNSource in style.sources {
			if let tileSource = source as? MLNTileSource {
				for attrib in tileSource.attributionInfos {
					print("\(attrib)")
				}
			}
		}
		/*
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
		  */
	}
}

extension MapLibreVectorTilesView: TilesProvider {
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

	func purgeTileCache() {
		MLNOfflineStorage.shared.resetDatabase(completionHandler: { _ in })
		URLCache.shared.removeAllCachedResponses()
		setNeedsLayout()
	}
}

extension MapLibreVectorTilesView: DiskCacheSizeProtocol {
	func getDiskCacheSize() -> (size: Int, count: Int) {
		let size = Int(MLNOfflineStorage.shared.countOfBytesCompleted)
		return (size, 1)
	}
}
