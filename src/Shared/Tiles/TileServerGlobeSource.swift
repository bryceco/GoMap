//
//  TileServerGlobeSource.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/30/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import GlobeRenderer
import UIKit

/// Adapts a `TileServerCache` to GlobeRenderer's `TileSource`, so the globe displays
/// the same imagery as the flat `MercatorTileLayer` it replaces and shares that
/// layer's memory and disk cache rather than downloading tiles twice.
struct TileServerGlobeSource: TileSource {
	let cache: TileServerCache
	let maxZoom: Int

	@MainActor
	init(cache: TileServerCache) {
		self.cache = cache
		maxZoom = cache.tileServer.maxZoom
	}

	func fetchTile(_ tile: TileCoordinate) async throws -> UIImage {
		return try await cache.image(forZoom: tile.zoom, tileX: tile.x, tileY: tile.y)
	}
}
