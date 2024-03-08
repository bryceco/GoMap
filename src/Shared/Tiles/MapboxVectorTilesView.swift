//
//  MapboxVectorTilesView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/4/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation
import MapLibre

class MapboxVectorTilesView: MLNMapView {
	let mapView: MapView

	init(mapView: MapView) {
		self.mapView = mapView
		super.init()

		mapView.mapTransform.observe(by: self, callback: {
			var t = CATransform3DIdentity
			t.m34 = -1 / CGFloat(mapView.mapTransform.birdsEyeDistance)
			t = CATransform3DRotate(t, CGFloat(mapView.mapTransform.birdsEyeRotation), 1, 0, 0)
			//			self.sublayerTransform = t
			self.setNeedsLayout()
		})
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
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
	}
}

extension MapboxVectorTilesView: GetDiskCacheSize {
	func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int) {
		pSize = 0
		pCount = 0
	}
	
}

