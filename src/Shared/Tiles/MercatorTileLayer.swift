//
//  MercatorTileLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

// let CUSTOM_TRANSFORM = 1

@inline(__always) private func modulus(_ a: Int, _ n: Int) -> Int {
	var m = a % n
	if m < 0 {
		m += n
	}
	assert(m >= 0)
	return m
}

final class MercatorTileLayer: CALayer, GetDiskCacheSize {
	private var webCache = PersistentWebCache<UIImage>(name: "", memorySize: 0)
	private var layerDict: [String: CALayer] = [:] // map of tiles currently displayed

	@objc let mapView: MapView // mark as objc for KVO
	private var isPerformingLayout = AtomicInt(0)

	// MARK: Implementation

	override init(layer: Any) {
		let layer = layer as! MercatorTileLayer
		mapView = layer.mapView
		tileServer = layer.tileServer
		super.init(layer: layer)
	}

	init(mapView: MapView) {
		self.mapView = mapView
		tileServer = TileServer.none // arbitrary, just need a default value
		super.init()

		needsDisplayOnBoundsChange = true

		// disable animations
		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"anchorPoint": NSNull(),
			"transform": NSNull(),
			"isHidden": NSNull()
		]

		mapView.mapTransform.observe(by: self, callback: {
			var t = CATransform3DIdentity
			t.m34 = -1 / CGFloat(mapView.mapTransform.birdsEyeDistance)
			t = CATransform3DRotate(t, CGFloat(mapView.mapTransform.birdsEyeRotation), 1, 0, 0)
			self.sublayerTransform = t
			self.setNeedsLayout()
		})
	}

	deinit {
		// mapView.removeObserver(self, forKeyPath: "screenFromMapTransform")
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
			webCache = PersistentWebCache(name: tileServer.identifier, memorySize: 20 * 1000 * 1000)

			let expirationDate = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)
			purgeOldCacheItemsAsync(expirationDate)
			setNeedsLayout()
		}
	}

	func zoomLevel() -> Int {
		return tileServer.roundZoomUp ? Int(ceil(mapView.mapTransform.zoom())) : Int(floor(mapView.mapTransform.zoom()))
	}

	func metadata(_ callback: @escaping (Result<Data, Error>?) -> Void) {
		guard let metadataUrl = tileServer.metadataUrl else {
			callback(nil)
			return
		}

		let rc = mapView.screenLatLonRect()

		var zoomLevel = self.zoomLevel()
		if zoomLevel > 21 {
			zoomLevel = 21
		}

		let url = String(
			format: metadataUrl,
			rc.origin.y + rc.size.height / 2,
			rc.origin.x + rc.size.width / 2,
			zoomLevel)

		if let url = URL(string: url) {
			URLSession.shared.data(with: url, completionHandler: { result in
				DispatchQueue.main.async(execute: {
					callback(result)
				})
			})
		}
	}

	func purgeTileCache() {
		webCache.removeAllObjects()
		layerDict.removeAll()
		sublayers = nil
		URLCache.shared.removeAllCachedResponses()
		setNeedsLayout()
	}

	func purgeOldCacheItemsAsync(_ expiration: Date) {
		webCache.removeObjectsAsyncOlderThan(expiration)
	}

	func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int) {
		webCache.getDiskCacheSize(&pSize, count: &pCount)
	}

	private func layerOverlapsScreen(_ layer: CALayer) -> Bool {
		let rc = layer.frame
		let center = rc.center()

		var p1 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y))
		var p2 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y + rc.size.height))
		var p3 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y + rc.size.height))
		var p4 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y))

		p1 = mapView.mapTransform.toBirdsEye(p1, center)
		p2 = mapView.mapTransform.toBirdsEye(p2, center)
		p3 = mapView.mapTransform.toBirdsEye(p3, center)
		p4 = mapView.mapTransform.toBirdsEye(p4, center)

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
				print("oops")
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

	private func quadKey(forZoom zoom: Int, tileX: Int, tileY: Int) -> String {
		return TileToQuadKey(x: tileX, y: tileY, z: zoom)
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
			// #if !CUSTOM_TRANSFORM
			//        layer?.anchorPoint = CGPoint(x: 0, y: 1)
			//        let scale = 256.0 / Double((1 << zoomLevel))
			//        layer?.frame = CGRect(x: CGFloat(Double(tileX) * scale), y: CGFloat(Double(tileY) * scale), width: CGFloat(scale), height: CGFloat(scale))
			// #endif
			layerDict[tileKey] = layer

			isPerformingLayout.increment()
			addSublayer(layer)
			isPerformingLayout.decrement()

			// check memory cache
			let cacheKey = String(quadKey(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY))
			let cachedImage: UIImage? = webCache.object(
				withKey: cacheKey,
				fallbackURL: { [self] in
					self.tileServer.url(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY)
				},
				objectForData: { data in
					if data.count == 0 || self.tileServer.isPlaceholderImage(data) {
						return nil
					}
					return UIImage(data: data)
				},
				completion: { [self] result in
					switch result {
					case let .success(image):
						if layer.superlayer != nil {
#if os(iOS)
							layer.contents = image.cgImage
#else
							layer.contents = image
#endif
							layer.isHidden = false
							// #if CUSTOM_TRANSFORM
							setNeedsLayout()
							// #else
							//                    let rc = mapView.boundingMapRectForScreen()
							//                    removeUnneededTiles(for: rc, zoomLevel: Int(zoomLevel))
							// #endif

							// after we've set the content we need to prune other layers since we're no longer transparent
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

	// #if CUSTOM_TRANSFORM
	private func setSublayerPositions(_ _layerDict: [String: CALayer]) {
		// update locations of tiles
		let tRotation = mapView.screenFromMapTransform.rotation()
		let tScale = mapView.screenFromMapTransform.scale()
		for (tileKey, layer) in _layerDict {
			let splitTileKey: [String] = tileKey.components(separatedBy: ",")
			let tileZ = Int32(splitTileKey[0]) ?? 0
			let tileX = Int32(splitTileKey[1]) ?? 0
			let tileY = Int32(splitTileKey[2]) ?? 0

			var scale = 256.0 / Double(1 << tileZ)
			let pt = OSMPoint(x: Double(tileX) * scale, y: Double(tileY) * scale)
			let cgPt = mapView.mapTransform.screenPoint(forMapPoint: pt, birdsEye: false)
			layer.position = cgPt
			layer.bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
			layer.anchorPoint = CGPoint(x: 0, y: 0)

			scale *= tScale / 256
			let t = CGAffineTransform(rotationAngle: CGFloat(tRotation)).scaledBy(x: CGFloat(scale), y: CGFloat(scale))
			layer.setAffineTransform(t)
		}
	}

	// #endif

	private func layoutSublayersSafe() {
		let rect = mapView.boundingMapRectForScreen()
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
		for tileX in tileWest..<tileEast {
			for tileY in tileNorth..<tileSouth {
				mapView.progressIncrement()
				fetchTile(
					forTileX: tileX,
					tileY: tileY,
					minZoom: max(zoomLevel - 6, 1),
					zoomLevel: zoomLevel,
					completion: { [self] error in
						if let error = error {
							mapView.presentError(error, flash: true)
						}
						mapView.progressDecrement()
					})
			}
		}

		// #if CUSTOM_TRANSFORM
		// update locations of tiles
		setSublayerPositions(layerDict)
		removeUnneededTiles(for: OSMRect(bounds), zoomLevel: zoomLevel)
		// #else
		//        let rc = mapView.boundingMapRectForScreen()
		//        removeUnneededTiles(for: rc, zoomLevel: Int(zoomLevel))
		// #endif
	}

	override func layoutSublayers() {
		if isHidden {
			return
		}
		isPerformingLayout.increment()
		layoutSublayersSafe()
		isPerformingLayout.decrement()
	}

	// this function is used for bulk downloading tiles
	func downloadTile(forKey cacheKey: String, completion: @escaping () -> Void) {
		let (tileX, tileY, zoomLevel) = QuadKeyToTileXY(cacheKey)
		let data2 = webCache.object(withKey: cacheKey,
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

	// Used for bulk downloading tiles for offline use
	func allTilesIntersectingVisibleRect() -> [String] {
		let currentTiles = webCache.allKeys()
		let currentSet = Set(currentTiles)

		let rect = mapView.boundingMapRectForScreen()
		let minZoomLevel = min(zoomLevel(), tileServer.maxZoom)
		let maxZoomLevel = min(zoomLevel() + 2, tileServer.maxZoom)

		var neededTiles: [String] = []
		for zoomLevel in minZoomLevel...maxZoomLevel {
			let zoom = Double(1 << zoomLevel) / 256.0
			let tileNorth = Int(floor(rect.origin.y * zoom))
			let tileWest = Int(floor(rect.origin.x * zoom))
			let tileSouth = Int(ceil((rect.origin.y + rect.size.height) * zoom))
			let tileEast = Int(ceil((rect.origin.x + rect.size.width) * zoom))

			if tileWest < 0 || tileWest >= tileEast || tileNorth < 0 || tileNorth >= tileSouth {
				// stuff breaks if they zoom all the way out
				continue
			}

			for tileX in tileWest..<tileEast {
				for tileY in tileNorth..<tileSouth {
					let cacheKey = quadKey(forZoom: zoomLevel, tileX: tileX, tileY: tileY)
					if currentSet.contains(cacheKey) {
						// already have it
					} else {
						neededTiles.append(cacheKey)
					}
				}
			}
		}
		return neededTiles
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

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
