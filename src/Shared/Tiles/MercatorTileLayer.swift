//
//  MercatorTileLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

@inline(__always) private func modulus(_ a: Int, _ n: Int) -> Int {
	var m = a % n
	if m < 0 {
		m += n
	}
	assert(m >= 0)
	return m
}

@MainActor
final class MercatorTileLayer: CALayer {
	private var webCache: PersistentWebCache<UIImage>?
	private var layerDict: [String: CALayer] = [:] // map of tiles currently displayed

	let mapViewPort: MapViewPort
	private var isPerformingLayout = AtomicInt(0)

	var supportDarkMode = false

	// MARK: Implementation

	override init(layer: Any) {
		let layer = layer as! MercatorTileLayer
		mapViewPort = layer.mapViewPort
		tileServer = layer.tileServer
		supportDarkMode = layer.supportDarkMode
		super.init(layer: layer)
	}

	init(mapView: MapViewPort) {
		self.mapViewPort = mapView
		tileServer = TileServer.none // arbitrary, just need a default value
		super.init()

		needsDisplayOnBoundsChange = true

		mapView.mapTransform.onChange.subscribe(self) { [weak self] in
			guard let self = self,
			      !self.isHidden
			else { return }
			var t = CATransform3DIdentity
			t.m34 = -1 / CGFloat(mapView.mapTransform.birdsEyeDistance)
			t = CATransform3DRotate(t, CGFloat(mapView.mapTransform.birdsEyeRotation), 1, 0, 0)
			self.sublayerTransform = t
			self.setNeedsLayout()
		}
	}

	deinit {}

	override func action(forKey event: String) -> CAAction? {
		return NSNull()
	}

	var tileServer: TileServer {
		didSet {
			if oldValue === tileServer {
				return
			}

			// remove previous data
			sublayers = nil
			layerDict.removeAll()

			// update service
			webCache = PersistentWebCache(name: tileServer.identifier,
			                              memorySize: 20 * 1000 * 1000,
			                              daysToKeep: tileServer.daysToCache())
			setNeedsLayout()
		}
	}

	func zoomLevel() -> Int {
		let z = mapViewPort.mapTransform.zoom()
		guard
			z.isFinite,
			z >= Double(Int.min),
			z <= Double(Int.max)
		else {
			return 0
		}
		return tileServer.roundZoomUp ? Int(ceil(z)) : Int(floor(z))
	}

	func metadata() async throws -> Data {
		guard let metadataUrl = tileServer.metadataUrl else {
			throw URLError(.resourceUnavailable)
		}

		let center = await MainActor.run {
			mapViewPort.screenCenterLatLon()
		}
		var zoomLevel = self.zoomLevel()
		if zoomLevel > 21 {
			zoomLevel = 21
		}

		let url = String(format: metadataUrl, center.lat, center.lon, zoomLevel)

		guard let url = URL(string: url) else {
			throw URLError(.badURL)
		}
		return try await URLSession.shared.data(with: url)
	}

	func updateDarkMode() {
		webCache?.resetMemoryCache()
		layerDict.removeAll()
		sublayers = nil
		setNeedsLayout()
	}

	func purgeTileCache() {
		webCache?.removeAllObjects()
		layerDict.removeAll()
		sublayers = nil
		URLCache.shared.removeAllCachedResponses()
		setNeedsLayout()
	}

	private func layerOverlapsScreen(_ layer: CALayer) -> Bool {
		let rc = layer.frame
		let center = rc.center()

		var p1 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y))
		var p2 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y + rc.size.height))
		var p3 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y + rc.size.height))
		var p4 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y))

		p1 = mapViewPort.mapTransform.toBirdsEye(p1, center)
		p2 = mapViewPort.mapTransform.toBirdsEye(p2, center)
		p3 = mapViewPort.mapTransform.toBirdsEye(p3, center)
		p4 = mapViewPort.mapTransform.toBirdsEye(p4, center)

		let rect = OSMRect(rc)
		return rect.containsPoint(p1) || rect.containsPoint(p2) || rect.containsPoint(p3) || rect.containsPoint(p4)
	}

	private func removeUnneededTiles(for rect: OSMRect, zoomLevel: Int) {
		guard let sublayers = sublayers else { return }

		let MAX_ZOOM = 30

		var removeList: [CALayer] = []

		// remove any tiles that don't intersect the current view
		for layer in sublayers {
			if !layerOverlapsScreen(layer) {
				removeList.append(layer)
			}
		}
		for layer in removeList {
			if let key = layer.value(forKey: "tileKey") as? String {
				// DLog("prune \(key): \(layer)")
				layerDict.removeValue(forKey: key)
				layer.removeFromSuperlayer()
				layer.contents = nil
			}
		}
		removeList.removeAll()

		// next remove objects that are covered by a parent (larger) object
		var layerList = [[CALayer]](repeating: [CALayer](), count: MAX_ZOOM)
		var transparent = [Bool](repeating: false, count: MAX_ZOOM) // some objects at this level are transparent
		// place each object in a zoom level bucket
		for layer in sublayers {
			let tileKey = layer.value(forKey: "tileKey") as! String
			let z = Int(tileKey[..<tileKey.firstIndex(of: ",")!])!
			if z < MAX_ZOOM {
				if layer.contents == nil {
					transparent[z] = true
				}
				layerList[z].append(layer)
			} else {
				print("unfound layer in MercatorTileLayer")
			}
		}

		// remove tiles at zoom levels less than us if we don't have any transparent tiles (we've tiled everything in greater detail)
		var remove = false
		for z in (0...zoomLevel).reversed() {
			if remove {
				removeList.append(contentsOf: layerList[z])
			}
			if !transparent[z] {
				remove = true
			}
		}

		// remove tiles at zoom levels greater than us if we're not transparent (we cover the more detailed tiles)
		remove = false
		for z in zoomLevel..<MAX_ZOOM {
			if remove {
				removeList.append(contentsOf: layerList[z])
			}
			if !transparent[z] {
				remove = true
			}
		}

		for layer in removeList {
			let key = layer.value(forKey: "tileKey") as! String
			layerDict.removeValue(forKey: key)
			layer.removeFromSuperlayer()
			layer.contents = nil
		}
	}

	private func fetchTile(
		forTileX tileX: Int,
		tileY: Int,
		minZoom: Int,
		zoomLevel: Int,
		completion: @escaping (_ error: Error?) -> Void)
	{
		if tileY < 0 || tileY >= (1 << zoomLevel) {
			// past north/south mercator limit
			completion(nil)
			return
		}
		let tileModY = tileY // modulus(tileY, 1 << zoomLevel)
		let tileModX = modulus(tileX, 1 << zoomLevel)
		let tileKey = "\(zoomLevel),\(tileX),\(tileY)"

		if layerDict[tileKey] != nil {
			// already have it
			completion(nil)
			return
		} else {
			// create layer
			let layer = CALayer()
			layer.actions = actions
			layer.zPosition = CGFloat(zoomLevel) * 0.01 - 0.25
			// don't AA edges of tiles or there will be a seam visible
			layer.edgeAntialiasingMask = CAEdgeAntialiasingMask(rawValue: 0)
			layer.isOpaque = true
			layer.isHidden = true
			layer.setValue(tileKey, forKey: "tileKey")
			layerDict[tileKey] = layer

			isPerformingLayout.increment()
			addSublayer(layer)
			isPerformingLayout.decrement()

			// check memory cache
			let cacheKey = QuadKey(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY)
			let cachedImage: UIImage? = webCache!.object(
				withKey: cacheKey,
				fallbackURL: { [self] in
					self.tileServer.url(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY)
				},
				objectForData: { data in
					if data.count == 0 || self.tileServer.isPlaceholderImage(data) {
						return nil
					}
					if self.supportDarkMode,
					   #available(iOS 13.0, *),
					   UIScreen.main.traitCollection.userInterfaceStyle == .dark
					{
						return DarkModeImage.shared.darkModeImageFor(data: data)
					} else {
						return UIImage(data: data)
					}
				},
				completion: { [self] result in
					switch result {
					case let .success(image):
						if layer.superlayer != nil {
							CATransaction.begin()
							CATransaction.setDisableActions(true)
#if os(iOS)
							layer.contents = image.cgImage
#else
							layer.contents = image
#endif
							layer.isHidden = false
							CATransaction.commit()
							setNeedsLayout()
						} else {
							// no longer needed
						}
						completion(nil)
					case let .failure(error):
						if zoomLevel > minZoom {
							// try to show tile at one zoom level higher
							DispatchQueue.main.async(execute: { [self] in
								fetchTile(
									forTileX: tileX >> 1,
									tileY: tileY >> 1,
									minZoom: minZoom,
									zoomLevel: zoomLevel - 1,
									completion: completion)
							})
						} else {
							// report error
							DispatchQueue.main.async(execute: {
								completion(error)
							})
						}
					}
				})
			if let cachedImage = cachedImage {
				layer.contents = cachedImage.cgImage
				layer.isHidden = false
				completion(nil)
				return
			}
			return
		}
	}

	override func setNeedsLayout() {
		if isPerformingLayout.value() != 0 {
			return
		}
		super.setNeedsLayout()
	}

	private func setSublayerPositions(_ _layerDict: [String: CALayer]) {
		// update locations of tiles
		let metersPerPixel = mapViewPort.metersPerPixel()
		let offsetPixels = CGPoint(x: imageryOffsetMeters.x / metersPerPixel,
		                           y: -imageryOffsetMeters.y / metersPerPixel)
		let tRotation = mapViewPort.mapTransform.rotation()
		let tScale = mapViewPort.mapTransform.scale()
		for (tileKey, layer) in _layerDict {
			let splitTileKey: [String] = tileKey.components(separatedBy: ",")
			let tileZ = Int32(splitTileKey[0]) ?? 0
			let tileX = Int32(splitTileKey[1]) ?? 0
			let tileY = Int32(splitTileKey[2]) ?? 0

			var scale = 256.0 / Double(1 << tileZ)
			let pt = OSMPoint(x: Double(tileX) * scale, y: Double(tileY) * scale)
			let cgPt = mapViewPort.mapTransform.screenPoint(forMapPoint: pt, birdsEye: false)
			layer.position = cgPt
			layer.bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
			layer.anchorPoint = CGPoint(x: 0, y: 0)

			scale *= tScale / 256
			var t = CGAffineTransform(rotationAngle: CGFloat(tRotation)).scaledBy(x: CGFloat(scale), y: CGFloat(scale))
			t = t.translatedBy(x: offsetPixels.x / scale, y: offsetPixels.y / scale)
			layer.setAffineTransform(t)
		}
	}

	private func layoutSublayersSafe() {
		let rect = mapViewPort.boundingMapRectForScreen()
		var zoomLevel = self.zoomLevel()

		if zoomLevel < 1 {
			zoomLevel = 1
		} else if zoomLevel > tileServer.maxZoom {
			zoomLevel = tileServer.maxZoom
		}

		let zoom = Double(1 << zoomLevel) / 256.0
		let tileNorth = Int(floor(rect.origin.y * zoom))
		let tileWest = Int(floor(rect.origin.x * zoom))
		let tileSouth = Int(ceil((rect.origin.y + rect.size.height) * zoom))
		let tileEast = Int(ceil((rect.origin.x + rect.size.width) * zoom))

		if (tileEast - tileWest) * (tileSouth - tileNorth) > 4000 {
			DLog("Bad tile transform: \((tileEast - tileWest) * (tileSouth - tileNorth))")
			return // something is wrong
		}

		// create any tiles that don't yet exist
		mapViewPort.progressIncrement((tileEast - tileWest) * (tileSouth - tileNorth))
		for tileX in tileWest..<tileEast {
			for tileY in tileNorth..<tileSouth {
				fetchTile(
					forTileX: tileX,
					tileY: tileY,
					minZoom: max(zoomLevel - 6, 1),
					zoomLevel: zoomLevel,
					completion: { [self] error in
						if let error = error,
						   self.tileServer != TileServer.mapboxLocator
						{
							mapViewPort.presentError(title: tileServer.name, error: error, flash: true)
						}
						mapViewPort.progressDecrement()
					})
			}
		}

		// update locations of tiles
		setSublayerPositions(layerDict)
		removeUnneededTiles(for: OSMRect(bounds), zoomLevel: zoomLevel)
	}

	override func layoutSublayers() {
		if isHidden {
			return
		}
		isPerformingLayout.increment()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		layoutSublayersSafe()
		CATransaction.commit()
		isPerformingLayout.decrement()
	}

	// this function is used for bulk downloading tiles
	func downloadTile(forKey cacheKey: String, completion: @escaping () -> Void) {
		let (tileX, tileY, zoomLevel) = QuadKeyToTileXY(cacheKey)
		let data2 = webCache!.object(withKey: cacheKey,
		                             fallbackURL: {
		                             	self.tileServer.url(forZoom: zoomLevel, tileX: tileX, tileY: tileY)
		                             },
		                             objectForData: { data in
		                             	if data.count == 0 || self.tileServer.isPlaceholderImage(data) {
		                             		return nil
		                             	}
		                             	return UIImage(data: data)
		                             }, completion: { _ in
		                             	completion()
		                             })
		if data2 != nil {
			completion()
		}
	}

	override var transform: CATransform3D {
		get {
			return super.transform
		}
		set(transform) {
			super.transform = transform
			setNeedsLayout()
		}
	}

	override var isHidden: Bool {
		didSet(wasHidden) {
			if wasHidden, !isHidden {
				setNeedsLayout()
			}
		}
	}

	var imageryOffsetMeters = CGPoint.zero {
		didSet {
			if imageryOffsetMeters != oldValue {
				setNeedsLayout()
			}
		}
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}

extension MercatorTileLayer: TilesProvider {
	func currentTiles() -> [String] {
		return webCache!.allKeys()
	}

	func maxZoom() -> Int {
		return tileServer.maxZoom
	}
}

extension MercatorTileLayer: DiskCacheSizeProtocol {
	func getDiskCacheSize() async -> (size: Int, count: Int) {
		return await webCache!.getDiskCacheSize()
	}
}

extension MercatorTileLayer: MapView.LayerOrView {
	var hasTileServer: TileServer? {
		return tileServer
	}

	func removeFromSuper() {
		removeFromSuperlayer()
	}
}
