//
//  GpxLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 2/22/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import QuartzCore
import UIKit

final class GpxTrackLayerWithProperties: CAShapeLayer {
	struct Properties {
		var position: OSMPoint?
		var lineWidth: CGFloat
	}

	var props = Properties(position: nil, lineWidth: 0.0)
}

final class GpxPoint: NSObject, NSCoding {
	let latLon: LatLon
	let accuracy: Double
	let elevation: Double
	let timestamp: Date? // imported GPX files may not contain a date
	// These fields are only used by waypoints
	let desc: String
	let extensions: [DDXMLNode]

	init(latLon: LatLon, accuracy: Double, elevation: Double, timestamp: Date?,
	     desc: String, extensions: [DDXMLNode])
	{
		self.latLon = latLon
		self.accuracy = accuracy
		self.elevation = elevation
		self.timestamp = timestamp
		self.desc = desc
		self.extensions = extensions
		super.init()
	}

	convenience init(withXML pt: DDXMLNode) throws {
		guard let pt = pt as? DDXMLElement,
		      let lat2 = pt.attribute(forName: "lat")?.stringValue,
		      let lon2 = pt.attribute(forName: "lon")?.stringValue,
		      let lat = Double(lat2),
		      let lon = Double(lon2)
		else {
			throw GpxError.badGpxFormat
		}

		let latLon = LatLon(latitude: lat, longitude: lon)
		var timestamp: Date?
		var elevation = 0.0
		if let time = pt.elements(forName: "time").last?.stringValue {
			timestamp = OsmBaseObject.rfc3339DateFormatter().date(from: time)
		}
		if let ele2 = pt.elements(forName: "ele").last?.stringValue,
		   let ele = Double(ele2)
		{
			elevation = ele
		}

		var description = ""
		var extensions: [DDXMLNode] = []

		for child in pt.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			switch child.name {
			case "name":
				// ignore for now
				break
			case "desc":
				description = child.stringValue ?? ""
			case "extensions":
				if let children = child.children {
					extensions = children
				}
			default:
				break
			}
		}

		self.init(latLon: latLon,
		          accuracy: 0.0,
		          elevation: elevation,
		          timestamp: timestamp,
		          desc: description,
		          extensions: extensions)
	}

	required init(coder aDecoder: NSCoder) {
		let lat = aDecoder.decodeDouble(forKey: "lat")
		let lon = aDecoder.decodeDouble(forKey: "lon")
		latLon = LatLon(latitude: lat, longitude: lon)
		accuracy = aDecoder.decodeDouble(forKey: "acc")
		elevation = aDecoder.decodeDouble(forKey: "ele")
		timestamp = aDecoder.decodeObject(forKey: "time") as? Date
		desc = ""
		extensions = []
		super.init()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(latLon.lat, forKey: "lat")
		aCoder.encode(latLon.lon, forKey: "lon")
		aCoder.encode(accuracy, forKey: "acc")
		aCoder.encode(elevation, forKey: "ele")
		aCoder.encode(timestamp, forKey: "time")
	}
}

// MARK: Track

enum GpxError: LocalizedError {
	case noData
	case fewerThanTwoPoints
	case badGpxFormat

	public var errorDescription: String? {
		switch self {
		case .noData: return "The file is not accessible"
		case .fewerThanTwoPoints: return "The GPX track must contain at least 2 points"
		case .badGpxFormat: return "Invalid GPX file format"
		}
	}
}

final class GpxTrack: NSObject, NSCoding {
	private var recording = false
	private var distance = 0.0

	static let nullShapePaths = [CGPath?](repeating: nil, count: 32)

	// An array of paths, each simplified according to zoom level
	// so we have good performance when zoomed out:
	public var shapePaths = GpxTrack.nullShapePaths

	private var _name: String?
	var name: String {
		get {
			return _name ?? fileName()
		}
		set(name) {
			_name = name
		}
	}

	var creationDate = Date() // when trace was recorded or downloaded
	private(set) var points: [GpxPoint] = []
	var shapeLayer: GpxTrackLayerWithProperties?

	func addPoint(_ location: CLLocation) {
		recording = true

		let coordinate = LatLon(location.coordinate)
		let prev = points.last

		if let prev = prev,
		   prev.latLon.lat == coordinate.lat,
		   prev.latLon.lon == coordinate.lon
		{
			return
		}

		if let prev = prev {
			let d = GreatCircleDistance(coordinate, prev.latLon)
			distance += d
		}

		let pt = GpxPoint(latLon: coordinate,
		                  accuracy: location.horizontalAccuracy,
		                  elevation: location.altitude,
		                  timestamp: location.timestamp,
		                  desc: "",
		                  extensions: [])

		points.append(pt)
	}

	func finish() {
		recording = false
	}

	convenience init(rect: CGRect) {
		self.init()
		let track = GpxTrack()
		let nw = CLLocation(latitude: CLLocationDegrees(rect.origin.y), longitude: CLLocationDegrees(rect.origin.x))
		let ne = CLLocation(
			latitude: CLLocationDegrees(rect.origin.y),
			longitude: CLLocationDegrees(rect.origin.x + rect.size.width))
		let se = CLLocation(
			latitude: CLLocationDegrees(rect.origin.y + rect.size.height),
			longitude: CLLocationDegrees(rect.origin.x + rect.size.width))
		let sw = CLLocation(
			latitude: CLLocationDegrees(rect.origin.y + rect.size.height),
			longitude: CLLocationDegrees(rect.origin.x))
		track.addPoint(nw)
		track.addPoint(ne)
		track.addPoint(se)
		track.addPoint(sw)
		track.addPoint(nw)
		track.finish()
	}

	override init() {
		super.init()
	}

	func gpxXmlString() -> String? {
		let dateFormatter = OsmBaseObject.rfc3339DateFormatter()

#if os(iOS)
		guard let doc: DDXMLDocument = try? DDXMLDocument(
			xmlString: "<gpx creator=\"Go Map!!\" version=\"1.4\"></gpx>",
			options: 0),
			let root = doc.rootElement(),
			let trkElement = DDXMLNode.element(withName: "trk") as? DDXMLElement
		else { return nil }
#else
		let root = DDXMLNode.element(withName: "gpx") as? DDXMLElement
		let doc = DDXMLDocument(rootElement: root)
		doc.characterEncoding = "UTF-8"
#endif
		root.addChild(trkElement)

		guard let segElement = DDXMLNode.element(withName: "trkseg") as? DDXMLElement
		else { return nil }
		trkElement.addChild(segElement)

		for pt in points {
			guard let ptElement = DDXMLNode.element(withName: "trkpt") as? DDXMLElement,
			      let attrLat = DDXMLNode.attribute(withName: "lat", stringValue: "\(pt.latLon.lat)") as? DDXMLNode,
			      let attrLon = DDXMLNode.attribute(withName: "lon", stringValue: "\(pt.latLon.lon)") as? DDXMLNode,
			      let eleElement = DDXMLNode.element(withName: "ele") as? DDXMLElement
			else { return nil }

			segElement.addChild(ptElement)
			ptElement.addAttribute(attrLat)
			ptElement.addAttribute(attrLon)

			if let timestamp = pt.timestamp,
			   let timeElement = DDXMLNode.element(withName: "time") as? DDXMLElement
			{
				timeElement.stringValue = dateFormatter.string(from: timestamp)
				ptElement.addChild(timeElement)
			}

			eleElement.stringValue = "\(pt.elevation)"
			ptElement.addChild(eleElement)
		}

		let string = doc.xmlString
		return string
	}

	func gpxXmlData() -> Data? {
		let data = gpxXmlString()?.data(using: .utf8)
		return data
	}

	convenience init(xmlData data: Data) throws {
		guard data.count > 0,
		      let doc = try? DDXMLDocument(data: data, options: 0)
		else {
			throw GpxError.noData
		}

		guard let ns1 = DDXMLElement.namespace(withName: "ns1",
		                                       stringValue: "http://www.topografix.com/GPX/1/0") as? DDXMLNode,
			let ns2 = DDXMLElement.namespace(withName: "ns2",
			                                 stringValue: "http://www.topografix.com/GPX/1/1") as? DDXMLNode,
			let ns3 = DDXMLElement.namespace(withName: "ns3",
			                                 stringValue: "http://topografix.com/GPX/1/1") as? DDXMLNode // HOT OSM uses this
		else {
			throw GpxError.badGpxFormat
		}

		doc.rootElement()?.addNamespace(ns1)
		doc.rootElement()?.addNamespace(ns2)
		doc.rootElement()?.addNamespace(ns3)

		let nsList = [
			"ns1:",
			"ns2:",
			"ns3:",
			""
		]
		var trkNodes: [DDXMLNode] = []
		var wptNodes: [DDXMLNode] = []
		for ns in nsList {
			let trkPath = "./\(ns)gpx/\(ns)trk/\(ns)trkseg/\(ns)trkpt"
			trkNodes = (try? doc.nodes(forXPath: trkPath)) ?? []
			let wptPath = "./\(ns)gpx/\(ns)wpt"
			wptNodes = (try? doc.nodes(forXPath: wptPath)) ?? []
			if trkNodes.count > 0 || wptNodes.count > 0 {
				break
			}
		}
		if wptNodes.count == 0, trkNodes.count < 2 {
			throw GpxError.fewerThanTwoPoints
		}

		var wayPoints: [GpxPoint] = []
		for pt in wptNodes {
			let waypoint = try GpxPoint(withXML: pt)
			wayPoints.append(waypoint)
		}

		var points: [GpxPoint] = []
		for pt in trkNodes {
			let point = try GpxPoint(withXML: pt)
			points.append(point)
		}
		if points.count < 2 {
			throw GpxError.fewerThanTwoPoints
		}

		self.init()
		self.points = points
		creationDate = Date()
	}

	convenience init(xmlFile path: String) throws {
		guard let data = NSData(contentsOfFile: path) as Data?
		else {
			throw GpxError.noData
		}
		try self.init(xmlData: data)
	}

	func lengthInMeters() -> Double {
		if distance == 0 {
			var prev: GpxPoint?
			for pt in points {
				if let prev = prev {
					let d = GreatCircleDistance(pt.latLon, prev.latLon)
					distance += d
				}
				prev = pt
			}
		}
		return distance
	}

	func fileName() -> String {
		return String(format: "%.3f.track", creationDate.timeIntervalSince1970)
	}

	func duration() -> TimeInterval {
		if points.count == 0 {
			return 0.0
		}

		guard let start = points.first?.timestamp,
		      let finish = points.last?.timestamp
		else { return 0.0 }
		return finish.timeIntervalSince(start)
	}

	required init?(coder aDecoder: NSCoder) {
		super.init()
		points = aDecoder.decodeObject(forKey: "points") as? [GpxPoint] ?? []
		name = aDecoder.decodeObject(forKey: "name") as? String ?? ""
		creationDate = aDecoder.decodeObject(forKey: "creationDate") as? Date ?? Date()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(points, forKey: "points")
		aCoder.encode(name, forKey: "name")
		aCoder.encode(creationDate, forKey: "creationDate")
	}
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
		if track.points.count >= 2 {
			// make sure save directory exists
			var time = TimeInterval(CACurrentMediaTime())
			let dir = saveDirectory()
			let path = URL(fileURLWithPath: dir).appendingPathComponent(track.fileName()).path
			do {
				try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
			} catch {}
			NSKeyedArchiver.archiveRootObject(track, toFile: path)
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
		let documentPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).map(\.path)
		let docsDir = documentPaths[0]
		let filePathInDocsDir = URL(fileURLWithPath: docsDir).appendingPathComponent("gpxPoints").path
		return filePathInDocsDir
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

			files = files.sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }
				.reversed() // file names are timestamps, so sort increasing
			// newest first

			for file in files {
				if file.hasSuffix(".track") {
					let path = URL(fileURLWithPath: dir).appendingPathComponent(file).path
					guard let track = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? GpxTrack else {
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
		// get midpoint
		var mid = track.points.count / 2
		if mid >= track.points.count {
			mid = 0
		}
		let pt = track.points[mid]
		let widthDegrees = (20.0 /* meters */ / EarthRadius) * 360.0
		mapView.setTransformFor(latLon: pt.latLon, width: widthDegrees)
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
