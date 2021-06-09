//
//  GpxLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 2/22/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import CoreLocation

//private let PATH_SCALING = 256*256.0
//private let MAX_AGE		= 7.0 * 24 * 60 * 60


// Distance in meters
private func metersApart(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
    var lat1 = lat1
    var lat2 = lat2
    let R: Double = 6371 // km
    lat1 *= .pi / 180
    lat2 *= .pi / 180
    let dLat = lat2 - lat1
    let dLon = (lon2 - lon1) * .pi / 180

    let a: Double = sin(dLat / 2) * sin(dLat / 2) + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
    let c: Double = 2 * atan2(sqrt(a), sqrt(1 - a))
    let d = R * c
    return d * 1000
}

class GpxTrackLayerWithProperties: CAShapeLayer {
	struct Properties {
		var position: OSMPoint?
		var lineWidth: CGFloat
	}
	var props = Properties(position: nil, lineWidth: 0.0)
}

class GpxPoint: NSObject, NSCoding {
    var longitude = 0.0
    var latitude = 0.0
    var accuracy = 0.0
    var elevation = 0.0
    var timestamp: Date?

    required init(coder aDecoder: NSCoder) {
        super.init()
        latitude = aDecoder.decodeDouble(forKey: "lat")
        longitude = aDecoder.decodeDouble(forKey: "lon")
        accuracy = aDecoder.decodeDouble(forKey: "acc")
        elevation = aDecoder.decodeDouble(forKey: "ele")
        timestamp = aDecoder.decodeObject(forKey: "time") as? Date
    }
    
    override init() {
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        aCoder.encode(latitude, forKey: "lat")
        aCoder.encode(longitude, forKey: "lon")
        aCoder.encode(accuracy, forKey: "acc")
        aCoder.encode(elevation, forKey: "ele")
        aCoder.encode(timestamp, forKey: "time")
    }
}

// MARK: Track
class GpxTrack: NSObject, NSCoding {

    var recording = false
    var _distance = 0.0

    public var shapePaths = [CGPath?](repeating: nil, count: 20) // an array of paths, each simplified according to zoom level so we have good performance when zoomed out

    private var _name: String?
    var name: String {
        get {
            return _name ?? fileName()
        } set(name) {
            _name = name
        }
    }
    var creationDate = Date() // when trace was recorded or downloaded
    private(set) var points: [GpxPoint] = []
    var shapeLayer: GpxTrackLayerWithProperties?

    func addPoint(_ location: CLLocation?) {
        recording = true

        let coordinate = location?.coordinate
        let prev = points.last
        
        if prev != nil && prev?.latitude == coordinate?.latitude && prev?.longitude == coordinate?.longitude {
            return
        }

        if let prev = prev {
            let d = metersApart(coordinate?.latitude ?? 0.0, coordinate?.longitude ?? 0.0, prev.latitude, prev.longitude)
            _distance += d
        }

        let pt = GpxPoint()
        pt.latitude = coordinate?.latitude ?? 0.0
        pt.longitude = coordinate?.longitude ?? 0.0
        pt.timestamp = location?.timestamp
        pt.elevation = location?.altitude ?? 0.0
        pt.accuracy = location?.horizontalAccuracy ?? 0.0

        points.append(pt)

        //	DLog( @"%f,%f (%f): %lu gpx points", coordinate.longitude, coordinate.latitude, location.horizontalAccuracy, (unsigned long)_points.count );
    }

    func finish() {
        recording = false
    }

    convenience init(rect: CGRect) {
        self.init()
        let track = GpxTrack()
        let nw = CLLocation(latitude: CLLocationDegrees(rect.origin.y), longitude: CLLocationDegrees(rect.origin.x))
        let ne = CLLocation(latitude: CLLocationDegrees(rect.origin.y), longitude: CLLocationDegrees(rect.origin.x + rect.size.width))
        let se = CLLocation(latitude: CLLocationDegrees(rect.origin.y + rect.size.height), longitude: CLLocationDegrees(rect.origin.x + rect.size.width))
        let sw = CLLocation(latitude: CLLocationDegrees(rect.origin.y + rect.size.height), longitude: CLLocationDegrees(rect.origin.x))
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
		guard let doc: DDXMLDocument = try? DDXMLDocument(xmlString: "<gpx creator=\"Go Map!!\" version=\"1.4\"></gpx>", options: 0),
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
				  let attrLat = DDXMLNode.attribute(withName: "lat", stringValue: "\(pt.latitude)") as? DDXMLNode,
				  let attrLon = DDXMLNode.attribute(withName: "lon", stringValue: "\(pt.longitude)") as? DDXMLNode,
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

    convenience init?(xmlData data: Data?) {
		guard let data = data,
			  data.count > 0,
			  let doc = try? DDXMLDocument(data: data, options: 0)
		else {
			return nil
		}

		guard let namespace1 = DDXMLElement.namespace(withName: "ns1", stringValue: "http://www.topografix.com/GPX/1/0") as? DDXMLElement,
			  let namespace2 = DDXMLElement.namespace(withName: "ns2", stringValue: "http://www.topografix.com/GPX/1/1") as? DDXMLElement,
			  let namespace3 = DDXMLElement.namespace(withName: "ns3", stringValue: "http://topografix.com/GPX/1/1") as? DDXMLElement // HOT OSM uses this
		else { return nil }

		doc.rootElement()?.addNamespace(namespace1)
		doc.rootElement()?.addNamespace(namespace2)
		doc.rootElement()?.addNamespace(namespace3)

        let nsList = [
            "ns1:",
            "ns2:",
            "ns3:",
            ""
        ]
        var a: [DDXMLNode] = []
		for ns in nsList {
			let xpath = "./\(ns)gpx/\(ns)trk/\(ns)trkseg/\(ns)trkpt"
			a = (try? doc.nodes(forXPath: xpath)) ?? []
			if a.count > 0 {
				break
			}
		}
		if a.count == 0 {
			return nil
		}

        var points: [GpxPoint] = []
        let dateFormatter = OsmBaseObject.rfc3339DateFormatter()
        for pt in a {
			guard let pt = pt as? DDXMLElement,
				  let lat = pt.attribute(forName: "lat")?.stringValue,
				  let lon = pt.attribute(forName: "lon")?.stringValue,
				  let lat = Double(lat),
				  let lon = Double(lon)
		    else { return nil }

			let point = GpxPoint()
            point.latitude = lat
            point.longitude = lon

			if let time = pt.elements(forName: "time").last?.stringValue {
                point.timestamp = dateFormatter.date(from: time)
			}
			if let ele = pt.elements(forName: "ele").last?.stringValue,
			   let ele = Double(ele)
			{
				point.elevation = ele
			}
			points.append(point)
        }
        if points.count < 2 {
            return nil
        }

		self.init()
        self.points = points
        creationDate = Date()
    }

    convenience init?(xmlFile path: String) {
        let data = NSData(contentsOfFile: path) as Data?
        if data == nil {
            return nil
        }
        self.init(xmlData: data)
    }

    func distance() -> Double {
        if _distance == 0 {
            var prev: GpxPoint? = nil
            for pt in points {
                if let prev = prev {
                    let d = metersApart(pt.latitude, pt.longitude, prev.latitude, prev.longitude)
                    _distance += d
                }
                prev = pt
            }
        }
        return _distance
    }

    func fileName() -> String {
        return String(format: "%.3f.track", creationDate.timeIntervalSince1970)
    }

    func duration() -> TimeInterval {
        if points.count == 0 {
            return 0.0
        }
        
        let start = points.first
        let finish = points.last
        if let timestamp1 = start?.timestamp {
            return finish?.timestamp?.timeIntervalSince(timestamp1) ?? 0.0
        }
        return 0.0
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

class GpxLayer: CALayer, GetDiskCacheSize {

	public static let USER_DEFAULTS_GPX_EXPIRATIION_KEY = "GpxTrackExpirationDays"
	public static let USER_DEFAULTS_GPX_BACKGROUND_TRACKING = "GpxTrackBackgroundTracking"

	@objc let mapView: MapView	// mark as objc for KVO
	var stabilizingCount = 0
	var observations: [NSKeyValueObservation] = []

    private(set) var activeTrack: GpxTrack? // track currently being recorded

    private weak var _selectedTrack: GpxTrack?
    weak var selectedTrack: GpxTrack? {
        get {
            return _selectedTrack
        }
        set(selectedTrack) {
            if selectedTrack != _selectedTrack {
                _selectedTrack?.shapeLayer?.removeFromSuperlayer()
                _selectedTrack?.shapeLayer = nil // color changes

                _selectedTrack = selectedTrack

                _selectedTrack?.shapeLayer?.removeFromSuperlayer()
                _selectedTrack?.shapeLayer = nil // color changes

                setNeedsLayout()
            }
        }
    } // track picked in view controller
    private(set) var previousTracks: [GpxTrack] = [] // sorted with most recent first
    private(set) var uploadedTracks: [String : Any] = [:] // track name -> upload date

    init(mapView: MapView) {
		self.mapView = mapView
        super.init()

        UserDefaults.standard.register(
            defaults: [
				GpxLayer.USER_DEFAULTS_GPX_EXPIRATIION_KEY: NSNumber(value: 7),
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
		self.observations.append( self.observe( \.mapView.screenFromMapTransform ) { _,_  in
			self.setNeedsLayout()
		})

        uploadedTracks = UserDefaults.standard.object(forKey: "GpxUploads") as? [String : Any] ?? [:]

        setNeedsLayout()
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
            } catch {
            }
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
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
        }
        previousTracks.removeAll { $0 === track }
        track.shapeLayer?.removeFromSuperlayer()
        setNeedsLayout()

        if uploadedTracks[track.name] != nil {
            uploadedTracks.removeValue(forKey: track.name)
            UserDefaults.standard.set(uploadedTracks, forKey: "GpxUploads")
        }
    }

    func markTrackUploaded(_ track: GpxTrack) {
        uploadedTracks[track.name] = NSNumber(value: true)
        UserDefaults.standard.set(uploadedTracks, forKey: "GpxUploads")
    }

    func trimTracksOlderThan(_ date: Date) {
        // trim off old tracks

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

#if DEBUG && false
            // for debugging only: magnify number of GPS points to test performance
            for i in 1..<1000 {
                var loc: CLLocation? = nil
                if let timestamp1 = location?.timestamp {
                    loc = CLLocation(coordinate: CLLocationCoordinate2DMake((location?.coordinate.latitude ?? 0.0) + Double(i) / 1000000.0, location?.coordinate.longitude ?? 0), altitude: location?.altitude ?? 0, horizontalAccuracy: location?.horizontalAccuracy ?? 0, verticalAccuracy: location?.verticalAccuracy ?? 0, course: location?.course ?? 0, speed: location?.speed ?? 0, timestamp: timestamp1)
                }
                activeTrack.addPoint(loc)
            }
#endif

            // automatically save periodically
#if os(iOS)
            let saveInterval = UIApplication.shared.applicationState == .active ? 30 : 180 // save less frequently if we're in the background
#else
            let saveInterval = 30
#endif
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

    func createGpxRect(_ rect: CGRect) -> GpxTrack {
        let track = GpxTrack(rect: rect)
        previousTracks.insert(track, at: 0)
        setNeedsLayout()
        return track
    }

    func saveDirectory() -> String {
        let documentPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).map(\.path)
        let docsDir = documentPaths[0]
        let filePathInDocsDir = URL(fileURLWithPath: docsDir).appendingPathComponent("gpxPoints").path
        return filePathInDocsDir
    }

    override func action(forKey key: String) -> CAAction? {
        if key == "transform" {
            return nil
        }
        if key == "bounds" {
            return nil
        }
        if key == "position" {
            return nil
        }
        //	DLog(@"actionForKey: %@",key);
        return super.action(forKey: key)
    }

    // MARK: Caching
    // load data if not already loaded
	var didLoadSavedTracks = false
    func loadTracksInBackground(withProgress progressCallback: (() -> Void)?) {

		if didLoadSavedTracks {
			return
		}
		didLoadSavedTracks = true

		let expiration = UserDefaults.standard.object(forKey: GpxLayer.USER_DEFAULTS_GPX_EXPIRATIION_KEY) as? NSNumber
        
        let deleteIfCreatedBefore = expiration?.doubleValue ?? 0.0 == 0 ? Date.distantPast : Date(timeIntervalSinceNow: TimeInterval(-(expiration?.doubleValue ?? 0.0) * 24 * 60 * 60))
        
        DispatchQueue.global(qos: .default).async(execute: { [self] in
            let dir = saveDirectory()
            var files: [String] = []
            do {
                files = try FileManager.default.contentsOfDirectory(atPath: dir)
            } catch {
            }
                        
            files = files.sorted{$0.compare($1, options: .caseInsensitive) == .orderedAscending }.reversed() // file names are timestamps, so sort increasing
            // newest first
            
            for file in files {
                if file.hasSuffix(".track") {
                    let path = URL(fileURLWithPath: dir).appendingPathComponent(file).path
                    let track = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? GpxTrack
                    if let track = track {
                        if track.creationDate.timeIntervalSince(deleteIfCreatedBefore) < 0 {
                            // skip because its too old
                            DispatchQueue.main.async(execute: { [self] in
                                delete(track)
                            })
                            continue
                        }
                    }
                    DispatchQueue.main.async(execute: { [self] in
                        // DLog(@"track %@: %@, %ld points\n",file,track.creationDate, (long)track.points.count);
                        
                        if let track = track {
                            previousTracks.append(track)
                        }
                        setNeedsLayout()
                        if let progressCallback = progressCallback {
                            progressCallback()
                        }
#if true
                        if track?.creationDate == nil {
                            let first = track?.points[0]
                            track?.creationDate = first?.timestamp ?? Date()
                            if let track = track {
                                save(toDisk: track)
                            }
                        }
#endif
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
        } catch {
        }
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
        } catch {
        }
        do {
            try FileManager.default.createDirectory(atPath: dir , withIntermediateDirectories: true, attributes: nil)
        } catch {
        }

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
		let widthDegrees = (20.0 /*meters*/ / EarthRadius) * 360.0
		mapView.setTransformFor(latitude: pt.latitude, longitude: pt.longitude, width: widthDegrees)
	}

    // Load a GPX trace from an external source
    func loadGPXData(_ data: Data, center: Bool) -> Bool {
        guard let newTrack = GpxTrack(xmlData: data) else {
            return false
        }
        previousTracks.insert(newTrack, at: 0)
        if center {
            self.center(on: newTrack)
            selectedTrack = newTrack
            mapView.enableGpxLogging = true // ensure GPX tracks are visible
        }
        save(toDisk: newTrack)
        return true
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
            var pt = MapPointForLatitudeLongitude(point.latitude, point.longitude)
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
                path.move(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
                first = false
            } else {
                path.addLine(to: CGPoint(x: pt.x, y: pt.y), transform: .identity)
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
				refPoint = OSMPoint(x: initial.x + Double(bbox.origin.x) / PATH_SCALING, y: initial.y + Double(bbox.origin.y) / PATH_SCALING)
            } else {
            }
        }

        return path
    }

    func getShapeLayer(for track: GpxTrack) -> GpxTrackLayerWithProperties {
        if let shapeLayer = track.shapeLayer {
            return shapeLayer
        }

        var refPoint = OSMPoint(x: 0, y: 0)
        let path = self.path(for: track, refPoint: &refPoint)
        memset(&track.shapePaths, 0, MemoryLayout.size(ofValue: track.shapePaths))
        track.shapePaths[0] = path

        let color = track == selectedTrack ? UIColor.red : UIColor(red: 1.0, green: 99 / 255.0, blue: 249 / 255.0, alpha: 1.0)

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
//        var scale = floor(-log(-Double.greatestFiniteMagnitude))
//        var scale = floor(-log(Double.infinity))
//        var scale = floor(-log(pScale))
        //	DLog(@"gpx scale = %f, %ld",log(pScale),scale);
        if scale < 0 {
            scale = 0
        }
        
        for track in allTracks() {
            let layer = getShapeLayer(for: track)
            
            if track.shapePaths[scale] == nil {
                let epsilon = pow(Double(10.0), Double(scale)) / 256.0
				track.shapePaths[scale] = track.shapePaths[0]?.pathWithReducePoints( CGFloat(epsilon) )
			}
            //		DLog(@"reduce %ld to %ld\n",CGPathPointCount(track->shapePaths[0]),CGPathPointCount(track->shapePaths[scale]));
            layer.path = track.shapePaths[scale]
            
            // configure the layer for presentation
			guard let pt = layer.props.position else { return }
            let pt2 = mapView.screenPoint(fromMapPoint: pt, birdsEye: false)
            
            // rotate and scale
            var t = CGAffineTransform(translationX: CGFloat(pt2.x - pt.x), y: CGFloat(pt2.y - pt.y))
            t = t.scaledBy(x: CGFloat(pScale), y: CGFloat(pScale))
            t = t.rotated(by: CGFloat(tRotation))
            layer.setAffineTransform(t)
            
            let shape = layer
			shape.lineWidth = layer.props.lineWidth / CGFloat(pScale)
            
            // add the layer if not already present
            if layer.superlayer == nil {
				insertSublayer(layer, at: UInt32(self.sublayers?.count ?? 0))	// place at bottom
			}
        }
        
        if mapView.birdsEyeRotation != 0 {
            var t = CATransform3DIdentity
            t.m34 = -1.0 / CGFloat(mapView.birdsEyeDistance)
            t = CATransform3DRotate(t, CGFloat(mapView.birdsEyeRotation), 1.0, 0, 0)
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

            if wasHidden && !hidden {
                loadTracksInBackground(withProgress: nil)
                setNeedsLayout()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
		fatalError()
    }
}

