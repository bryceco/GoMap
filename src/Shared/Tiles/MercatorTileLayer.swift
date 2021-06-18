//
//  MercatorTileLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

//let CUSTOM_TRANSFORM = 1

@inline(__always) private func modulus(_ a: Int, _ n: Int) -> Int {
	var m = a % n
	if m < 0 {
		m += n
	}
	assert(m >= 0)
	return m
}

final class MercatorTileLayer: CALayer, GetDiskCacheSize {
    
	private var _webCache = PersistentWebCache<UIImage>(name: "", memorySize: 0)
	private var _layerDict: [String : CALayer] = [:] // map of tiles currently displayed
    
	@objc let mapView: MapView	// mark as objc for KVO
	private var isPerformingLayout = AtomicInt(0)
    
    // MARK: Implementation

	override init(layer: Any) {
		let layer = layer as! MercatorTileLayer
		self.mapView = layer.mapView
		self.tileServer = layer.tileServer
		super.init(layer: layer)
	}

    init(mapView: MapView) {
		self.mapView = mapView
		self.tileServer = TileServer.none	// arbitrary, just need a default value
		super.init()

        needsDisplayOnBoundsChange = true
        
        // disable animations
		self.actions = [
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
        willSet(service) {
            if service === tileServer {
                return
            }
            
            // remove previous data
			sublayers = nil
			_layerDict.removeAll()
            
			// update service
			_webCache = PersistentWebCache(name: service.identifier, memorySize: 20 * 1000 * 1000)

			let expirationDate = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)
			purgeOldCacheItemsAsync(expirationDate)
			setNeedsLayout()
        }
    }
    
    func zoomLevel() -> Int {
		return tileServer.roundZoomUp ? Int(ceil(mapView.mapTransform.zoom())): Int(floor(mapView.mapTransform.zoom()))
    }
    
    func metadata(_ callback: @escaping (Data?, Error?) -> Void) {
        guard let metadataUrl = tileServer.metadataUrl else {
			callback(nil, nil)
			return
        }

		let rc = mapView.screenLongitudeLatitude()

		var zoomLevel = self.zoomLevel()
		if zoomLevel > 21 {
			zoomLevel = 21
		}

		let url = String(format: metadataUrl, rc.origin.y + rc.size.height / 2, rc.origin.x + rc.size.width / 2, zoomLevel)

		if let url = URL(string: url) {
			let task = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
				DispatchQueue.main.async(execute: {
					callback(data, error)
				})
			})
			task.resume()
		}
    }
    
    func purgeTileCache() {
        _webCache.removeAllObjects()
        _layerDict.removeAll()
        sublayers = nil
        URLCache.shared.removeAllCachedResponses()
        setNeedsLayout()
    }
    
    func purgeOldCacheItemsAsync(_ expiration: Date) {
        _webCache.removeObjectsAsyncOlderThan(expiration)
    }
    
    func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int) {
        _webCache.getDiskCacheSize(&pSize, count: &pCount)
    }

    private func layerOverlapsScreen(_ layer: CALayer) -> Bool {
        let rc = layer.frame
		let center = rc.center()
        
        var p1 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y))
        var p2 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y + rc.size.height))
        var p3 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y + rc.size.height))
        var p4 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y))
        
		p1 = ToBirdsEye(p1, center, Double(mapView.mapTransform.birdsEyeDistance), Double(mapView.mapTransform.birdsEyeRotation))
		p2 = ToBirdsEye(p2, center, Double(mapView.mapTransform.birdsEyeDistance), Double(mapView.mapTransform.birdsEyeRotation))
		p3 = ToBirdsEye(p3, center, Double(mapView.mapTransform.birdsEyeDistance), Double(mapView.mapTransform.birdsEyeRotation))
		p4 = ToBirdsEye(p4, center, Double(mapView.mapTransform.birdsEyeDistance), Double(mapView.mapTransform.birdsEyeRotation))
        
        let rect = OSMRect(rc)
		return rect.containsPoint(p1) || rect.containsPoint(p2) || rect.containsPoint(p3) || rect.containsPoint(p4)
	}

	private func removeUnneededTiles(for rect: OSMRect, zoomLevel: Int) {
		guard let sublayers = self.sublayers else { return }

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
				_layerDict.removeValue(forKey: key)
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
			let z = Int( tileKey[..<tileKey.firstIndex(of: ",")!] )!
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
			_layerDict.removeValue(forKey: key)
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
        completion: @escaping (_ error: Error?) -> Void )
	{
        let tileModX = modulus(tileX, 1 << zoomLevel)
        let tileModY = modulus(tileY, 1 << zoomLevel)
        let tileKey = "\(zoomLevel),\(tileX),\(tileY)"

		if _layerDict[tileKey] != nil {
			// already have it
			completion(nil)
			return
		} else {
            // create layer
            let layer = CALayer()
			layer.actions = self.actions
            layer.zPosition = CGFloat(zoomLevel) * 0.01 - 0.25
            layer.edgeAntialiasingMask = CAEdgeAntialiasingMask(rawValue: 0) // don't AA edges of tiles or there will be a seam visible
            layer.isOpaque = true
            layer.isHidden = true
            layer.setValue(tileKey, forKey: "tileKey")
            //#if !CUSTOM_TRANSFORM
            //        layer?.anchorPoint = CGPoint(x: 0, y: 1)
            //        let scale = 256.0 / Double((1 << zoomLevel))
            //        layer?.frame = CGRect(x: CGFloat(Double(tileX) * scale), y: CGFloat(Double(tileY) * scale), width: CGFloat(scale), height: CGFloat(scale))
            //#endif
            _layerDict[tileKey] = layer
            
			isPerformingLayout.increment()
            addSublayer(layer)
			isPerformingLayout.decrement()
            
            // check memory cache
            let cacheKey = String(quadKey(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY))
            let cachedImage: UIImage? = _webCache.object(
                withKey: cacheKey,
                fallbackURL: { [self] in
					return self.tileServer.url(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY)
				},
                objectForData: { data in
					if data.count == 0 || self.tileServer.isPlaceholderImage(data) {
						return nil
					}
					return UIImage(data: data)
                },
				completion: { [self] image in
					if let image = image {
						if layer.superlayer != nil {
	#if os(iOS)
							layer.contents = image.cgImage
	#else
							layer.contents = image
	#endif
							layer.isHidden = false
							//#if CUSTOM_TRANSFORM
							setNeedsLayout()
							//#else
							//                    let rc = mapView.boundingMapRectForScreen()
							//                    removeUnneededTiles(for: rc, zoomLevel: Int(zoomLevel))
							//#endif

							// after we've set the content we need to prune other layers since we're no longer transparent
						} else {
							// no longer needed
						}
						completion(nil)
					} else if zoomLevel > minZoom {
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
	#if false
						if let data = data {
							var json: JSONSerialization?
							do {
								json = try JSONSerialization.jsonObject(with: data, options: [])
								text = json.description()
							} catch error {
								text = String(bytes: data.bytes, encoding: .utf8)
							}
						}
	#endif
						let error = NSError(domain: "Image", code: 100, userInfo: [
							NSLocalizedDescriptionKey: NSLocalizedString("No image data available", comment: "")
						])
						DispatchQueue.main.async(execute: {
							completion(error)
						})
					}
				})
			if cachedImage != nil {
				#if os(iOS)
				layer.contents = cachedImage!.cgImage
				#else
				layer?.contents = cachedImage
				#endif
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
    
//#if CUSTOM_TRANSFORM
	private func setSublayerPositions(_ _layerDict: [String : CALayer]) {
        // update locations of tiles
		let tRotation = mapView.screenFromMapTransform.rotation()
		let tScale = mapView.screenFromMapTransform.scale()
		for (tileKey, layer) in _layerDict {
            let splitTileKey : [String] = tileKey.components(separatedBy: ",")
            let tileZ: Int32 = Int32(splitTileKey[0]) ?? 0
            let tileX: Int32 = Int32(splitTileKey[1]) ?? 0
            let tileY: Int32 = Int32(splitTileKey[2]) ?? 0
            
            var scale = 256.0 / Double((1 << tileZ))
            var pt = OSMPoint(x: Double(tileX) * scale, y: Double(tileY) * scale)
			pt = mapView.mapTransform.screenPoint(fromMapPoint: pt, birdsEye: false)
            layer.position = CGPoint(pt)
            layer.bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
            layer.anchorPoint = CGPoint(x: 0, y: 0)
            
            scale *= tScale / 256
            let t = CGAffineTransform(rotationAngle: CGFloat(tRotation)).scaledBy(x: CGFloat(scale), y: CGFloat(scale))
            layer.setAffineTransform(t)
        }
    }
//#endif

	private func layoutSublayersSafe() {
        let rect = mapView.boundingMapRectForScreen()
        var zoomLevel = self.zoomLevel()
        
        if zoomLevel < 1 {
            zoomLevel = 1
        } else if zoomLevel > tileServer.maxZoom {
            zoomLevel = tileServer.maxZoom
        }
        
        let zoom = Double((1 << zoomLevel)) / 256.0
        let tileNorth = Int(floor((rect.origin.y) * zoom))
        let tileWest = Int(floor((rect.origin.x) * zoom))
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
                    minZoom: max(zoomLevel - 8, 1),
                    zoomLevel: zoomLevel,
					completion: { [self] error in
						if let error = error {
							mapView.presentError(error, flash: true)
						}
						mapView.progressDecrement()
                })
            }
        }
        
//#if CUSTOM_TRANSFORM
        // update locations of tiles
        setSublayerPositions(_layerDict)
        removeUnneededTiles(for: OSMRect(bounds), zoomLevel: zoomLevel)
//#else
//        let rc = mapView.boundingMapRectForScreen()
//        removeUnneededTiles(for: rc, zoomLevel: Int(zoomLevel))
//#endif
        
        mapView.progressAnimate()
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
        let data2 = _webCache.object(withKey: cacheKey,
			fallbackURL: {
				return self.tileServer.url(forZoom: zoomLevel, tileX: tileX, tileY: tileY)
			},
			objectForData: { data in
				if data.count == 0 || self.tileServer.isPlaceholderImage(data) {
					return nil
				}
				return UIImage(data: data)
			}, completion: { data in
				completion()
			})
        if data2 != nil {
            completion()
        }
    }
    
    // Used for bulk downloading tiles for offline use
    func allTilesIntersectingVisibleRect() -> [String] {
        let currentTiles = _webCache.allKeys()
        let currentSet = Set(currentTiles)
        
        let rect = mapView.boundingMapRectForScreen()
        var minZoomLevel = zoomLevel()
        
        if minZoomLevel < 1 {
            minZoomLevel = 1
        }
        if minZoomLevel > 31 {
            minZoomLevel = 31 // shouldn't be necessary, except to shup up the Xcode analyzer
        }
        
        var maxZoomLevel = tileServer.maxZoom
        if maxZoomLevel > minZoomLevel + 2 {
            maxZoomLevel = minZoomLevel + 2
        }
        if maxZoomLevel > 31 {
            maxZoomLevel = 31 // shouldn't be necessary, except to shup up the Xcode analyzer
        }
        
        var neededTiles: [String] = []
        for zoomLevel in minZoomLevel...maxZoomLevel {
            let zoom = Double((1 << zoomLevel)) / 256.0
            let tileNorth = Int(floor((rect.origin.y) * zoom))
            let tileWest = Int(floor((rect.origin.x) * zoom))
            let tileSouth = Int(ceil((rect.origin.y + rect.size.height) * zoom))
            let tileEast = Int(ceil((rect.origin.x + rect.size.width) * zoom))
            
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
			if wasHidden && !self.isHidden {
				setNeedsLayout()
			}
		}
	}

    required init?(coder aDecoder: NSCoder) {
		fatalError()
    }
}
