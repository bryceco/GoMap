//
//  GpxTrack.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/15/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import CoreLocation.CLLocation
import Foundation
import QuartzCore

final class GpxPoint: NSObject, NSSecureCoding {
	static let supportsSecureCoding = true

	let latLon: LatLon
	let accuracy: Double
	let elevation: Double
	let timestamp: Date? // imported GPX files may not contain a date
	// These fields are only used by waypoints
	let name: String
	let desc: String
	let extensions: [DDXMLNode]

	init(latLon: LatLon, accuracy: Double, elevation: Double, timestamp: Date?,
	     name: String, desc: String, extensions: [DDXMLNode])
	{
		self.latLon = latLon
		self.accuracy = accuracy
		self.elevation = elevation
		self.timestamp = timestamp
		self.name = name
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

		var name = ""
		var description = ""
		var extensions: [DDXMLNode] = []

		for child in pt.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			switch child.name {
			case "name":
				name = child.stringValue ?? ""
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
		          name: name,
		          desc: description,
		          extensions: extensions)
	}

	required init(coder aDecoder: NSCoder) {
		let lat = aDecoder.decodeDouble(forKey: "lat")
		let lon = aDecoder.decodeDouble(forKey: "lon")
		latLon = LatLon(latitude: lat, longitude: lon)
		accuracy = aDecoder.decodeDouble(forKey: "acc")
		elevation = aDecoder.decodeDouble(forKey: "ele")
		timestamp = aDecoder.decodeObject(of: NSDate.self, forKey: "time") as? Date
		name = aDecoder.decodeObject(forKey: "name") as? String ?? ""
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
		aCoder.encode(name, forKey: "name")
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

final class GpxTrack: NSObject, NSSecureCoding {
	static let supportsSecureCoding = true

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
	private(set) var wayPoints: [GpxPoint] = []
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
		} else {
			// Use the first timestamp as the creation date
			creationDate = location.timestamp
		}

		let pt = GpxPoint(latLon: coordinate,
		                  accuracy: location.horizontalAccuracy,
		                  elevation: location.altitude,
		                  timestamp: location.timestamp,
		                  name: "",
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
			let wptPath = "./\(ns)gpx/\(ns)wpt"
			trkNodes = (try? doc.nodes(forXPath: trkPath)) ?? []
			wptNodes = (try? doc.nodes(forXPath: wptPath)) ?? []
			if trkNodes.count > 0 || wptNodes.count > 0 {
				break
			}
		}
		if wptNodes.count == 0, trkNodes.count < 2 {
			throw GpxError.fewerThanTwoPoints
		}

		let trkPoints: [GpxPoint] = try trkNodes.map { try GpxPoint(withXML: $0) }
		let wptPoints: [GpxPoint] = try wptNodes.map { try GpxPoint(withXML: $0) }

		self.init()
		points = trkPoints
		wayPoints = wptPoints
		creationDate = trkPoints.first?.timestamp ?? wptPoints.first?.timestamp ?? Date()
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
		guard let start = points.first?.timestamp,
		      let finish = points.last?.timestamp
		else { return 0.0 }
		return finish.timeIntervalSince(start)
	}

	required init?(coder aDecoder: NSCoder) {
		super.init()
		points = aDecoder.decodeObject(forKey: "points") as? [GpxPoint] ?? []
		wayPoints = aDecoder.decodeObject(forKey: "waypoints") as? [GpxPoint] ?? []
		name = aDecoder.decodeObject(forKey: "name") as? String ?? ""
		creationDate = aDecoder.decodeObject(forKey: "creationDate") as? Date ?? Date()
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(points, forKey: "points")
		aCoder.encode(wayPoints, forKey: "waypoints")
		aCoder.encode(name, forKey: "name")
		aCoder.encode(creationDate, forKey: "creationDate")
	}
}
