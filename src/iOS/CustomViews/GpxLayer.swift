//
//  GpxLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 2/22/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import UIKit

final class GpxLayer: DrawingLayer, DrawingLayerDelegate {
	let gpxTracks = AppState.shared.gpxTracks

	override init(viewPort: MapViewPort) {
		super.init(viewPort: viewPort)
		super.geojsonDelegate = self

		gpxTracks.onChangeTracks.subscribe(self) { [weak self] in
			self?.setNeedsLayout()
		}
		gpxTracks.OnChangeCurrent.subscribe(self) { [weak self] in
			self?.setNeedsLayout()
		}
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}

	// MARK: Properties

	// Delegate function to provide GeoJSONLayer with data
	func geojsonData() -> [DrawingLayerDelegate.OverlayData] {
		return gpxTracks.allTracks().compactMap {
			guard let geom = $0.geoJSON.geometry else { return nil }
			let color = $0 == gpxTracks.selectedTrack
				? UIColor.red
				: UIColor(red: 1.0,
				          green: 99 / 255.0,
				          blue: 249 / 255.0,
				          alpha: 1.0)
			return (geom, color, nil)
		}
	}
}

extension GpxLayer: MapLayersView.LayerOrView {
	var hasTileServer: TileServer? {
		return nil
	}

	func removeFromSuper() {
		removeFromSuperlayer()
	}
}
