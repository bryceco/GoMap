//
//  MapLibreVectorTilesView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/4/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

#if canImport(MapLibre)
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

		setPreferredFrameRate()

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

		let bad = [
			"place_town",
			"place_city"
		]
		for layer in style.layers {
			if let layer = layer as? MLNSymbolStyleLayer {
				// an icon and/or label
				if bad.contains(layer.identifier) {
					continue
				}
				layer.text = layer.text.mgl_expressionLocalized(into: locale)
			}
		}
	}

	func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {}

	func setPreferredFrameRate() {
		if #available(iOS 15.0, *) {
			let rate = Int(DisplayLink.shared.displayLink.preferredFrameRateRange.maximum)
			preferredFramesPerSecond = MLNMapViewPreferredFramesPerSecond(rawValue: rate)
		}
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
	func getDiskCacheSize() async -> (size: Int, count: Int) {
		let size = Int(MLNOfflineStorage.shared.countOfBytesCompleted)
		return (size, 1)
	}
}
#else

// Create a minimal dummy implementation that asserts if used
import UIKit
class MapLibreVectorTilesView: UIView, TilesProvider, DiskCacheSizeProtocol {
	var mapView: MapView
	let tileServer: TileServer
	var styleURL: URL

	init(mapView: MapView, tileServer: TileServer) {
		fatalError()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError()
	}

	func currentTiles() -> [String] {
		return []
	}

	func zoomLevel() -> Int {
		return 0
	}

	func maxZoom() -> Int {
		return 0
	}

	func downloadTile(forKey cacheKey: String, completion: @escaping () -> Void) {}

	func purgeTileCache() {}

	func getDiskCacheSize() async -> (size: Int, count: Int) {
		return (0, 0)
	}

	func setPreferredFrameRate() {}
}
#endif

extension MapLibreVectorTilesView: MapView.LayerOrView {
	func removeFromSuper() {
		removeFromSuperview()
	}
}
