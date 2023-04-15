//
//  GpxLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 2/22/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import CoreLocation.CLLocation
import UIKit

final class GpxTrackLayerWithProperties: CAShapeLayer {
	struct Properties {
		var position: OSMPoint?
		var lineWidth: CGFloat
	}

	var props = Properties(position: nil, lineWidth: 0.0)
}

final class GpxLayer: CALayer, GetDiskCacheSize {
	private static let DefaultExpirationDays = 7
	private static let USER_DEFAULTS_GPX_EXPIRATIION_KEY = "GpxTrackExpirationDays"
	private static let USER_DEFAULTS_GPX_BACKGROUND_TRACKING = "GpxTrackBackgroundTracking"

	let mapView: MapView
	var stabilizingCount = 0

	private(set) var activeTrack: GpxTrack? // track currently being recorded

	// track picked in view controller
	weak var selectedTrack: GpxTrack? {
		didSet {
			if oldValue != selectedTrack {
				oldValue?.shapeLayer?.removeFromSuperlayer()
				oldValue?.shapeLayer = nil // color changes
				selectedTrack?.shapeLayer?.removeFromSuperlayer()
				selectedTrack?.shapeLayer = nil // color changes
			}
			setNeedsLayout()
		}
	}

	private(set) var previousTracks: [GpxTrack] = [] // sorted with most recent first

	override init(layer: Any) {
		let layer = layer as! GpxLayer
		mapView = layer.mapView
		uploadedTracks = [:]
		super.init(layer: layer)
	}

	init(mapView: MapView) {
		self.mapView = mapView
		let uploads = UserDefaults.standard.object(forKey: "GpxUploads") as? [String: NSNumber] ?? [:]
		uploadedTracks = uploads.mapValues({ $0.boolValue })

		super.init()

		UserDefaults.standard.register(
			defaults: [
				GpxLayer.USER_DEFAULTS_GPX_EXPIRATIION_KEY: NSNumber(value: GpxLayer.DefaultExpirationDays),
				GpxLayer.USER_DEFAULTS_GPX_BACKGROUND_TRACKING: NSNumber(value: false)
			])

		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"hidden": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"transform": NSNull(),
			"lineWidth": NSNull()
		]

		// observe changes to geometry
		mapView.mapTransform.observe(by: self, callback: { self.setNeedsLayout() })

		setNeedsLayout()
	}

	var uploadedTracks: [String: Bool] {
		didSet {
			let dict = uploadedTracks.mapValues({ NSNumber(value: $0) })
			UserDefaults.standard.set(dict, forKey: "GpxUploads")
		}
	}

	func startNewTrack() {
		if activeTrack != nil {
			endActiveTrack()
		}
		activeTrack = GpxTrack()
		stabilizingCount = 0
		selectedTrack = activeTrack
	}

	func endActiveTrack() {
		if let activeTrack = activeTrack {
			// redraw shape with archive color
			activeTrack.finish()
			activeTrack.shapeLayer?.removeFromSuperlayer()
			activeTrack.shapeLayer = nil

			// add to list of previous tracks
			if activeTrack.points.count > 1 {
				previousTracks.insert(activeTrack, at: 0)
			}

			save(toDisk: activeTrack)
			self.activeTrack = nil
			selectedTrack = nil
		}
	}

	func save(toDisk track: GpxTrack) {
		if track.points.count >= 2 || track.wayPoints.count > 0 {
			// make sure save directory exists
			var time = TimeInterval(CACurrentMediaTime())
			let dir = saveDirectory()
			let path = URL(fileURLWithPath: dir).appendingPathComponent(track.fileName())
			do {
				try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
				let data = try NSKeyedArchiver.archivedData(withRootObject: track, requiringSecureCoding: true)
				try data.write(to: path)
			} catch {
				print("\(error)")
			}
			time = TimeInterval(CACurrentMediaTime() - time)
			DLog("GPX track \(track.points.count) points, save time = \(time)")
		}
	}

	func saveActiveTrack() {
		if let activeTrack = activeTrack {
			save(toDisk: activeTrack)
		}
	}

	func delete(_ track: GpxTrack) {
		let path = URL(fileURLWithPath: saveDirectory()).appendingPathComponent(track.fileName()).path
		try? FileManager.default.removeItem(atPath: path)
		previousTracks.removeAll { $0 === track }
		track.shapeLayer?.removeFromSuperlayer()
		uploadedTracks.removeValue(forKey: track.name)
		setNeedsLayout()
	}

	func markTrackUploaded(_ track: GpxTrack) {
		uploadedTracks[track.name] = true
	}

	// Removes GPX tracks older than date.
	// This is called when the user selects a new age limit for tracks.
	func trimTracksOlderThan(_ date: Date) {
		while let track = previousTracks.last {
			let point = track.points[0]
			if let timestamp1 = point.timestamp {
				if date.timeIntervalSince(timestamp1) > 0 {
					// delete oldest
					delete(track)
				} else {
					break
				}
			}
		}
	}

	func totalPointCount() -> Int {
		var total = activeTrack?.points.count ?? 0
		for track in previousTracks {
			total += track.points.count
		}
		return total
	}

	func addPoint(_ location: CLLocation) {
		if let activeTrack = activeTrack {
			// need to recompute shape layer
			activeTrack.shapeLayer?.removeFromSuperlayer()
			activeTrack.shapeLayer = nil

			// ignore bad data while starting up
			stabilizingCount += 1
			if stabilizingCount >= 5 {
				// take it
			} else if stabilizingCount == 1 {
				// always skip first point
				return
			} else if location.horizontalAccuracy > 10.0 {
				// skip it
				return
			}

			activeTrack.addPoint(location)

			// automatically save periodically
			let saveInterval = UIApplication.shared
				.applicationState == .active ? 30 : 180 // save less frequently if we're in the background

			if activeTrack.points.count % saveInterval == 0 {
				saveActiveTrack()
			}

			// if the number of points is too large then the periodic save will begin taking too long,
			// and drawing performance will degrade, so start a new track every hour
			if activeTrack.points.count >= 3600 {
				endActiveTrack()
				startNewTrack()
				stabilizingCount = 100 // already stable
				addPoint(location)
			}

			setNeedsLayout()
		}
	}

	func allTracks() -> [GpxTrack] {
		if let activeTrack = activeTrack {
			return [activeTrack] + previousTracks
		} else {
			return previousTracks
		}
	}

	func saveDirectory() -> String {
		return ArchivePath.urlForName("gpxPoints",
		                              in: .documentDirectory,
		                              bundleID: false).path
	}

	override func action(forKey key: String) -> CAAction? {
		switch key {
		case "transform",
		     "bounds",
		     "position":
			return nil
		default:
			return super.action(forKey: key)
		}
	}

	// MARK: Caching

	// Number of days after which we automatically delete tracks
	// If zero then never delete them
	static var expirationDays: Int {
		get {
			(UserDefaults.standard.object(forKey: GpxLayer.USER_DEFAULTS_GPX_EXPIRATIION_KEY) as? NSNumber)?
				.intValue ?? Self.DefaultExpirationDays
		}
		set { UserDefaults.standard.set(NSNumber(value: newValue), forKey: GpxLayer.USER_DEFAULTS_GPX_EXPIRATIION_KEY) }
	}

	static var backgroundTracking: Bool {
		get {
			(UserDefaults.standard.object(forKey: GpxLayer.USER_DEFAULTS_GPX_BACKGROUND_TRACKING) as? NSNumber)?
				.boolValue ?? false
		}
		set {
			UserDefaults.standard
				.set(NSNumber(value: newValue), forKey: GpxLayer.USER_DEFAULTS_GPX_BACKGROUND_TRACKING)
		}
	}

	// load data if not already loaded
	var didLoadSavedTracks = false
	func loadTracksInBackground(withProgress progressCallback: (() -> Void)?) {
		if didLoadSavedTracks {
			return
		}
		didLoadSavedTracks = true

		let expiration = GpxLayer.expirationDays
		let deleteIfCreatedBefore = expiration == 0 ? Date.distantPast
			: Date(timeIntervalSinceNow: TimeInterval(-expiration * 24 * 60 * 60))

		DispatchQueue.global(qos: .default).async(execute: { [self] in
			let dir = saveDirectory()
			var files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []

			// file names are timestamps, so sort increasing newest first
			files = files.sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }.reversed()

			for file in files {
				if file.hasSuffix(".track") {
					let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
					guard
						let data = try? Data(contentsOf: url, options: .alwaysMapped),
						let track = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [GpxTrack.self,
						                                                                GpxPoint.self,
						                                                                NSDate.self,
						                                                                NSArray.self],
						                                                    from: data) as? GpxTrack
					else {
						continue
					}

					if track.creationDate.timeIntervalSince(deleteIfCreatedBefore) < 0 {
						// skip because its too old
						DispatchQueue.main.async(execute: { [self] in
							delete(track)
						})
						continue
					}
					DispatchQueue.main.async(execute: { [self] in
						previousTracks.append(track)
						setNeedsLayout()
						if let progressCallback = progressCallback {
							progressCallback()
						}
					})
				}
			}
		})
	}

	func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int) {
		var size = 0
		let dir = saveDirectory()
		var files: [String] = []
		do {
			files = try FileManager.default.contentsOfDirectory(atPath: dir)
		} catch {}
		for file in files {
			if file.hasSuffix(".track") {
				let path = URL(fileURLWithPath: dir).appendingPathComponent(file).path
				var status = stat()
				stat((path as NSString).fileSystemRepresentation, &status)
				size += (Int(status.st_size) + 511) & -512
			}
		}
		pSize = size
		pCount = files.count + (activeTrack != nil ? 1 : 0)
	}

	func purgeTileCache() {
		let active = activeTrack != nil
		let stable = stabilizingCount

		endActiveTrack()
		//        previousTracks = nil
		sublayers = nil

		let dir = saveDirectory()
		do {
			try FileManager.default.removeItem(atPath: dir)
		} catch {}
		do {
			try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
		} catch {}

		setNeedsLayout()

		if active {
			startNewTrack()
			stabilizingCount = stable
		}
	}

	func center(on track: GpxTrack) {
		let center: GpxPoint
		if let wayPoint = track.wayPoints.first {
			center = wayPoint
		} else {
			// get midpoint
			let mid = track.points.count / 2
			guard mid < track.points.count else {
				return
			}
			center = track.points[mid]
		}
		let widthDegrees = (20.0 /* meters */ / EarthRadius) * 360.0
		mapView.setTransformFor(latLon: center.latLon, width: widthDegrees)
	}

	// Load a GPX trace from an external source
	func loadGPXData(_ data: Data, center: Bool) throws {
		let newTrack = try GpxTrack(xmlData: data)
		previousTracks.insert(newTrack, at: 0)
		if center {
			self.center(on: newTrack)
			selectedTrack = newTrack
			mapView.displayGpxLogs = true // ensure GPX tracks are visible
		}
		save(toDisk: newTrack)
	}

	// MARK: Drawing

	override var bounds: CGRect {
		get {
			return super.bounds
		}
		set(bounds) {
			super.bounds = bounds
			//	_baseLayer.frame = bounds;
			setNeedsLayout()
		}
	}

	// Convert the track to a CGPath so we can draw it
	func path(for track: GpxTrack, refPoint: inout OSMPoint) -> CGPath {
		var path = CGMutablePath()
		var initial = OSMPoint(x: 0, y: 0)
		var haveInitial = false
		var first = true

		for point in track.points {
			var pt = MapTransform.mapPoint(forLatLon: point.latLon)
			if pt.x.isInfinite {
				break
			}
			if !haveInitial {
				initial = pt
				haveInitial = true
			}
			pt.x -= initial.x
			pt.y -= initial.y
			pt.x *= PATH_SCALING
			pt.y *= PATH_SCALING
			if first {
				path.move(to: CGPoint(x: pt.x, y: pt.y))
				first = false
			} else {
				path.addLine(to: CGPoint(x: pt.x, y: pt.y))
			}
		}

		if haveInitial {
			// place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
			let bbox = path.boundingBoxOfPath
			if !bbox.origin.x.isInfinite {
				var tran = CGAffineTransform(translationX: -bbox.origin.x, y: -bbox.origin.y)
				if let path2 = path.mutableCopy(using: &tran) {
					path = path2
				}
				refPoint = OSMPoint(
					x: initial.x + Double(bbox.origin.x) / PATH_SCALING,
					y: initial.y + Double(bbox.origin.y) / PATH_SCALING)
			} else {}
		}

		return path
	}

	func getShapeLayer(for track: GpxTrack) -> GpxTrackLayerWithProperties {
		if let shapeLayer = track.shapeLayer {
			return shapeLayer
		}

		var refPoint = OSMPoint(x: 0, y: 0)
		let path = self.path(for: track, refPoint: &refPoint)
		track.shapePaths = GpxTrack.nullShapePaths
		track.shapePaths[0] = path

		let color = track == selectedTrack ? UIColor.red : UIColor(
			red: 1.0,
			green: 99 / 255.0,
			blue: 249 / 255.0,
			alpha: 1.0)

		let layer = GpxTrackLayerWithProperties()
		layer.anchorPoint = CGPoint.zero
		layer.position = CGPoint(refPoint)
		layer.path = path
		layer.strokeColor = color.cgColor
		layer.fillColor = nil
		layer.lineWidth = 2.0
		layer.lineCap = .square
		layer.lineJoin = .miter
		layer.zPosition = 0.0
		layer.actions = actions
		layer.props.position = refPoint
		layer.props.lineWidth = layer.lineWidth
		track.shapeLayer = layer
		return layer
	}

	func layoutSublayersSafe() {
		let tRotation = mapView.screenFromMapTransform.rotation()
		let tScale = mapView.screenFromMapTransform.scale()
		let pScale = tScale / PATH_SCALING
		var scale = Int(floor(-log(pScale)))
		if scale < 0 {
			scale = 0
		}

		for track in allTracks() {
			let layer = getShapeLayer(for: track)

			if track.shapePaths[scale] == nil {
				let epsilon = pow(Double(10.0), Double(scale)) / 256.0
				track.shapePaths[scale] = track.shapePaths[0]?.pathWithReducedPoints(epsilon)
			}
			//		DLog(@"reduce %ld to %ld\n",CGPathPointCount(track->shapePaths[0]),CGPathPointCount(track->shapePaths[scale]));
			layer.path = track.shapePaths[scale]

			// configure the layer for presentation
			guard let pt = layer.props.position else { return }
			let pt2 = OSMPoint(mapView.mapTransform.screenPoint(forMapPoint: pt, birdsEye: false))

			// rotate and scale
			var t = CGAffineTransform(translationX: CGFloat(pt2.x - pt.x), y: CGFloat(pt2.y - pt.y))
			t = t.scaledBy(x: CGFloat(pScale), y: CGFloat(pScale))
			t = t.rotated(by: CGFloat(tRotation))
			layer.setAffineTransform(t)

			let shape = layer
			shape.lineWidth = layer.props.lineWidth / CGFloat(pScale)

			// add the layer if not already present
			if layer.superlayer == nil {
				insertSublayer(layer, at: UInt32(sublayers?.count ?? 0)) // place at bottom
			}
		}

		if mapView.mapTransform.birdsEyeRotation != 0 {
			var t = CATransform3DIdentity
			t.m34 = -1.0 / CGFloat(mapView.mapTransform.birdsEyeDistance)
			t = CATransform3DRotate(t, CGFloat(mapView.mapTransform.birdsEyeRotation), 1.0, 0, 0)
			sublayerTransform = t
		} else {
			sublayerTransform = CATransform3DIdentity
		}
	}

	override func layoutSublayers() {
		if !isHidden {
			layoutSublayersSafe()
		}
	}

	// MARK: Properties

	override var isHidden: Bool {
		get {
			return super.isHidden
		}
		set(hidden) {
			let wasHidden = isHidden
			super.isHidden = hidden

			if wasHidden, !hidden {
				loadTracksInBackground(withProgress: nil)
				setNeedsLayout()
			}
		}
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
