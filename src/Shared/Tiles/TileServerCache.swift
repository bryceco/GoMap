//
//  TileServerCache.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/1/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

/// The tile cache for one `TileServer`: owns the `PersistentWebCache` plus the
/// tile-specific conventions layered on top of it (quadkey naming, URL lookup,
/// placeholder rejection, dark-mode conversion). `MercatorTileLayer` and the globe
/// share a single instance so a tile is downloaded and decoded only once.
@MainActor
final class TileServerCache {
	let tileServer: TileServer
	let supportDarkMode: Bool
	private let webCache: PersistentWebCache<UIImage>

	init(tileServer: TileServer, supportDarkMode: Bool) {
		self.tileServer = tileServer
		self.supportDarkMode = supportDarkMode
		webCache = PersistentWebCache(name: tileServer.identifier,
		                              memorySize: 20 * 1000 * 1000,
		                              daysToKeep: tileServer.daysToCache())
	}

	/// Returns the tile synchronously if it is in memory; otherwise returns nil and
	/// calls `completion` exactly once on the main thread when it has been read from
	/// disk or downloaded.
	func image(forZoom zoom: Int, tileX: Int, tileY: Int,
	           completion: @escaping (Result<UIImage, Error>) -> Void) -> UIImage?
	{
		return image(forKey: QuadKey(forZoom: zoom, tileX: tileX, tileY: tileY),
		             completion: completion)
	}

	/// Same as above but keyed by quadkey, for callers that already have one
	/// (bulk download enumerates keys).
	func image(forKey cacheKey: String,
	           completion: @escaping (Result<UIImage, Error>) -> Void) -> UIImage?
	{
		let (tileX, tileY, zoom) = QuadKeyToTileXY(cacheKey)
		let tileServer = tileServer
		let supportDarkMode = supportDarkMode
		return webCache.object(
			withKey: cacheKey,
			fallbackURL: {
				tileServer.url(forZoom: zoom, tileX: tileX, tileY: tileY)
			},
			objectForData: { data in
				Self.decode(data, tileServer: tileServer, supportDarkMode: supportDarkMode)
			},
			completion: completion)
	}

	/// Async form for callers that aren't on the main thread, such as the globe renderer.
	func image(forZoom zoom: Int, tileX: Int, tileY: Int) async throws -> UIImage {
		return try await withCheckedThrowingContinuation { continuation in
			let cached = image(forZoom: zoom, tileX: tileX, tileY: tileY) { result in
				continuation.resume(with: result)
			}
			if let cached {
				continuation.resume(returning: cached)
			}
		}
	}

	/// Data -> UIImage conversion shared by every path, so the memory cache holds
	/// the same object regardless of who requested the tile.
	private static func decode(_ data: Data, tileServer: TileServer, supportDarkMode: Bool) -> UIImage? {
		if data.count == 0 || tileServer.isPlaceholderImage(data) {
			return nil
		}
		if supportDarkMode,
		   UIScreen.main.traitCollection.userInterfaceStyle == .dark
		{
			return DarkModeImage.shared.darkModeImageFor(data: data)
		}
		return UIImage(data: data)
	}

	// MARK: Maintenance, forwarded to the underlying cache

	func resetMemoryCache() {
		webCache.resetMemoryCache()
	}

	func removeAllObjects() {
		webCache.removeAllObjects()
	}

	func allKeys() -> [String] {
		return webCache.allKeys()
	}

	func getDiskCacheSize() async -> (size: Int, count: Int) {
		return await webCache.getDiskCacheSize()
	}
}
