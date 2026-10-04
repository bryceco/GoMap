//
//  GpxTrack.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/15/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import CoreLocation.CLLocation
import Foundation
import KissXML

final class GpxPoint: NSObject, NSSecureCoding {
	static let supportsSecureCoding = true

	// Accepts "2024-05-01T12:34:56Z" as well as fractional seconds and "+02:00" style offsets,
	// which many GPS devices/apps emit.
	private static let iso8601Fractional: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return f
	}()

	private static let iso8601Plain: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime]
		return f
	}()

	static func parseGpxTime(_ time: String) -> Date? {
		return parseGpxTimeFast(time)
			?? iso8601Fractional.date(from: time)
			?? iso8601Plain.date(from: time)
	}

	/// Hand-rolled ISO 8601 parser for GPX timestamps.
	/// Handles: "2024-05-01T12:34:56Z", "2024-05-01T12:34:56.123Z",
	///          "2024-05-01T12:34:56+02:00", "2024-05-01T12:34:56.123+02:00"
	private static func parseGpxTimeFast(_ str: String) -> Date? {
		/// Parse `count` ASCII digits from `buf` at `offset` into an Int.
		func parseInt(_ buf: [UInt8], _ offset: Int, _ count: Int) -> Int? {
			guard offset + count <= buf.count else { return nil }
			var result = 0
			for i in offset..<offset + count {
				let d = buf[i]
				guard d >= UInt8(ascii: "0"), d <= UInt8(ascii: "9") else { return nil }
				result = result * 10 + Int(d - UInt8(ascii: "0"))
			}
			return result
		}

		// Minimum: "2024-05-01T12:34:56Z" = 20 chars
		guard str.count >= 20 else { return nil }
		let u = Array(str.utf8)
		// Parse date: YYYY-MM-DDThh:mm:ss
		guard u[4] == UInt8(ascii: "-"),
		      u[7] == UInt8(ascii: "-"),
		      u[10] == UInt8(ascii: "T"),
		      u[13] == UInt8(ascii: ":"),
		      u[16] == UInt8(ascii: ":")
		else { return nil }

		guard let year = parseInt(u, 0, 4),
		      let month = parseInt(u, 5, 2), (1...12).contains(month),
		      let day = parseInt(u, 8, 2), (1...31).contains(day),
		      let hour = parseInt(u, 11, 2), (0...23).contains(hour),
		      let minute = parseInt(u, 14, 2), (0...59).contains(minute),
		      let second = parseInt(u, 17, 2), (0...60).contains(second) // 60 for leap second
		else { return nil }

		var idx = 19
		var fractionalSeconds = 0.0

		// Optional fractional seconds
		if idx < u.count, u[idx] == UInt8(ascii: ".") {
			idx += 1
			var frac = 0.0
			var divisor = 10.0
			while idx < u.count, u[idx] >= UInt8(ascii: "0"), u[idx] <= UInt8(ascii: "9") {
				frac += Double(u[idx] - UInt8(ascii: "0")) / divisor
				divisor *= 10.0
				idx += 1
			}
			fractionalSeconds = frac
		}

		// Timezone: Z, +HH:MM, or -HH:MM
		var tzOffset = 0
		guard idx < u.count else { return nil }
		if u[idx] == UInt8(ascii: "Z") {
			tzOffset = 0
		} else if u[idx] == UInt8(ascii: "+") || u[idx] == UInt8(ascii: "-") {
			let sign = u[idx] == UInt8(ascii: "+") ? 1 : -1
			idx += 1
			guard idx + 4 < u.count || idx + 4 == u.count else { return nil }
			guard let tzH = parseInt(u, idx, 2) else { return nil }
			idx += 2
			if idx < u.count, u[idx] == UInt8(ascii: ":") { idx += 1 }
			guard let tzM = parseInt(u, idx, 2) else { return nil }
			tzOffset = sign * (tzH * 3600 + tzM * 60)
		} else {
			return nil
		}

		// Build timeIntervalSince1970 using a table of cumulative days per month
		let isLeap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
		let cumulativeDays = isLeap
			? [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
			: [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]

		// Days from 1970-01-01 to year-01-01
		let y = year - 1
		let daysToYear = 365 * (year - 1970)
			+ (y / 4 - 492) // leap years since 1970: y/4 - 1969/4
			- (y / 100 - 19) // minus century years: y/100 - 1969/100
			+ (y / 400 - 4) // plus 400-year cycles: y/400 - 1969/400

		let dayOfYear = cumulativeDays[month - 1] + (day - 1)
		let totalSeconds = Double(daysToYear + dayOfYear) * 86400.0
			+ Double(hour) * 3600.0
			+ Double(minute) * 60.0
			+ Double(second)
			+ fractionalSeconds
			- Double(tzOffset)

		return Date(timeIntervalSince1970: totalSeconds)
	}

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

	required init(coder aDecoder: NSCoder) {
		let lat = aDecoder.decodeDouble(forKey: "lat")
		let lon = aDecoder.decodeDouble(forKey: "lon")
		latLon = LatLon(latitude: lat, longitude: lon)
		accuracy = aDecoder.decodeDouble(forKey: "acc")
		elevation = aDecoder.decodeDouble(forKey: "ele")
		timestamp = aDecoder.decodeObject(of: NSDate.self, forKey: "time") as? Date
		name = aDecoder.decodeObject(of: NSString.self, forKey: "name") as String? ?? ""
		desc = aDecoder.decodeObject(of: NSString.self, forKey: "desc") as String? ?? ""
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
		aCoder.encode(desc, forKey: "desc")
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

	var name: String?

	/// The date when the track was created. Derived from the first point's timestamp
	/// when available, falling back to a stored date for waypoint-only imports.
	var creationDate: Date {
		return points.first?.timestamp ?? _creationDate
	}

	private var _creationDate = Date()
	private(set) var points: [GpxPoint] = []
	private(set) var wayPoints: [GpxPoint] = []
	private var geoJSONFeature: GeoJSONFeature?

	var geoJSON: GeoJSONFeature {
		if geoJSONFeature == nil {
			let geom = points.count >= 2
				? GeoJSONGeometry(geometry: .lineString(points: points.map { $0.latLon }))
				: nil
			geoJSONFeature = GeoJSONFeature(type: .Feature,
			                                id: name,
			                                geometry: geom,
			                                properties: nil)
		}
		return geoJSONFeature!
	}

	func isEqual(to track: GpxTrack) -> Bool {
		return name == track.name &&
			points.count == track.points.count &&
			points.first?.latLon == track.points.first?.latLon &&
			points.last?.latLon == track.points.last?.latLon &&
			wayPoints.count == track.wayPoints.count &&
			wayPoints.first?.latLon == track.wayPoints.first?.latLon &&
			wayPoints.last?.latLon == track.wayPoints.last?.latLon
	}

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
			let d = coordinate.greatCircleDistance(to: prev.latLon)
			distance += d
		}

		let pt = GpxPoint(latLon: coordinate,
		                  accuracy: location.horizontalAccuracy,
		                  elevation: location.altitude,
		                  timestamp: location.timestamp,
		                  name: "",
		                  desc: "",
		                  extensions: [])

		points.append(pt)

		// need to recompute shape
		geoJSONFeature = nil
	}

	func finish() {
		recording = false
	}

	override init() {
		super.init()
	}

	/// Appends points and waypoints from a newer track to this track.
	func appendPoints(from track: GpxTrack) {
		points.append(contentsOf: track.points)
		wayPoints.append(contentsOf: track.wayPoints)
		geoJSONFeature = nil
		distance = 0.0
	}

	func gpxXmlString() -> String? {
		let dateFormatter = OsmBaseObject.rfc3339DateFormatter()

#if os(iOS)
		guard let doc: DDXMLDocument = try? DDXMLDocument(
			xmlString: "<gpx creator=\"Go Map!!\" version=\"1.1\" xmlns=\"http://www.topografix.com/GPX/1/1\"></gpx>",
			options: 0),
			let root = doc.rootElement()
		else { return nil }
#else
		guard let root = DDXMLNode.element(withName: "gpx") as? DDXMLElement else { return nil }
		let doc = DDXMLDocument(rootElement: root)
		doc.characterEncoding = "UTF-8"
#endif

		// Metadata: creation date
		if let metaElement = DDXMLNode.element(withName: "metadata") as? DDXMLElement,
		   let timeElement = DDXMLNode.element(withName: "time") as? DDXMLElement
		{
			timeElement.stringValue = dateFormatter.string(from: creationDate)
			metaElement.addChild(timeElement)
			root.addChild(metaElement)
		}

		guard let trkElement = DDXMLNode.element(withName: "trk") as? DDXMLElement
		else { return nil }
		root.addChild(trkElement)

		// Track name (only written if explicitly set, not the auto-generated filename)
		if let trackName = name,
		   let nameElement = DDXMLNode.element(withName: "name") as? DDXMLElement
		{
			nameElement.stringValue = trackName
			trkElement.addChild(nameElement)
		}

		guard let segElement = DDXMLNode.element(withName: "trkseg") as? DDXMLElement
		else { return nil }
		trkElement.addChild(segElement)

		for pt in points {
			guard let ptElement = DDXMLNode.element(withName: "trkpt") as? DDXMLElement,
			      let attrLat = DDXMLNode.attribute(withName: "lat", stringValue: "\(pt.latLon.lat)") as? DDXMLNode,
			      let attrLon = DDXMLNode.attribute(withName: "lon", stringValue: "\(pt.latLon.lon)") as? DDXMLNode
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

			if let eleElement = DDXMLNode.element(withName: "ele") as? DDXMLElement {
				eleElement.stringValue = "\(pt.elevation)"
				ptElement.addChild(eleElement)
			}
		}

		// Waypoints
		for pt in wayPoints {
			guard let wptElement = DDXMLNode.element(withName: "wpt") as? DDXMLElement,
			      let attrLat = DDXMLNode.attribute(withName: "lat", stringValue: "\(pt.latLon.lat)") as? DDXMLNode,
			      let attrLon = DDXMLNode.attribute(withName: "lon", stringValue: "\(pt.latLon.lon)") as? DDXMLNode
			else { continue }

			root.addChild(wptElement)
			wptElement.addAttribute(attrLat)
			wptElement.addAttribute(attrLon)

			if pt.elevation != 0,
			   let eleElement = DDXMLNode.element(withName: "ele") as? DDXMLElement
			{
				eleElement.stringValue = "\(pt.elevation)"
				wptElement.addChild(eleElement)
			}
			if let timestamp = pt.timestamp,
			   let timeElement = DDXMLNode.element(withName: "time") as? DDXMLElement
			{
				timeElement.stringValue = dateFormatter.string(from: timestamp)
				wptElement.addChild(timeElement)
			}
			if !pt.name.isEmpty,
			   let nameElement = DDXMLNode.element(withName: "name") as? DDXMLElement
			{
				nameElement.stringValue = pt.name
				wptElement.addChild(nameElement)
			}
			if !pt.desc.isEmpty,
			   let descElement = DDXMLNode.element(withName: "desc") as? DDXMLElement
			{
				descElement.stringValue = pt.desc
				wptElement.addChild(descElement)
			}
		}

		return doc.xmlString
	}

	func gpxXmlData() -> Data? {
		let data = gpxXmlString()?.data(using: .utf8)
		return data
	}

	convenience init(xmlFile url: URL) throws {
		guard
			let data = try? Data(contentsOf: url)
		else {
			throw GpxError.noData
		}
		try self.init(xmlData: data)
	}

	// MARK: Streaming XML parser (SAX-based, much faster than DOM)

	convenience init(xmlData data: Data) throws {
		guard data.count > 0 else {
			throw GpxError.noData
		}
		let handler = GpxSAXParser()
		let parser = XMLParser(data: data)
		parser.delegate = handler
		guard parser.parse(), handler.error == nil else {
			throw handler.error ?? GpxError.badGpxFormat
		}
		if handler.wayPoints.isEmpty, handler.trkPoints.count < 2 {
			throw GpxError.fewerThanTwoPoints
		}
		self.init()
		points = handler.trkPoints
		wayPoints = handler.wayPoints
		_creationDate = handler.metadataDate
			?? handler.trkPoints.first?.timestamp
			?? handler.wayPoints.first?.timestamp
			?? Date()
		if let trackName = handler.trackName {
			name = trackName
		}
	}

	func lengthInMeters() -> Double {
		if distance == 0 {
			var prev: GpxPoint?
			for pt in points {
				if let prev = prev {
					let d = pt.latLon.greatCircleDistance(to: prev.latLon)
					distance += d
				}
				prev = pt
			}
		}
		return distance
	}

	func center() -> LatLon? {
		if let wayPoint = wayPoints.first {
			return wayPoint.latLon
		} else {
			// get midpoint
			let mid = points.count / 2
			guard mid < points.count else {
				return nil
			}
			return points[mid].latLon
		}
	}

	private static let fileNameFormatter: DateFormatter = {
		let df = DateFormatter()
		df.dateFormat = "yyyyMMdd_HHmmss.SSS"
		df.locale = Locale(identifier: "en_US_POSIX")
		df.timeZone = .current
		return df
	}()

	func fileBaseName() -> String {
		return Self.fileNameFormatter.string(from: creationDate)
	}

	/// The old unix-timestamp filename used by old versions.
	func legacyFileBaseName() -> String {
		return String(format: "%.3f", creationDate.timeIntervalSince1970)
	}

	func fileGpxName() -> String {
		return fileBaseName() + ".gpx"
	}

	func fileTrackName() -> String {
		return fileBaseName() + ".track"
	}

	func duration() -> TimeInterval {
		guard let start = points.first?.timestamp,
		      let finish = points.last?.timestamp
		else { return 0.0 }
		return finish.timeIntervalSince(start)
	}

	required init?(coder aDecoder: NSCoder) {
		super.init()
		points = aDecoder.decodeObject(of: [NSArray.self, GpxPoint.self], forKey: "points") as? [GpxPoint] ?? []
		wayPoints = aDecoder.decodeObject(of: [NSArray.self, GpxPoint.self], forKey: "waypoints") as? [GpxPoint] ?? []
		_creationDate = aDecoder.decodeObject(of: NSDate.self, forKey: "creationDate") as Date? ?? Date()
		// Discard auto-generated names stored by older versions
		let decodedName = aDecoder.decodeObject(of: NSString.self, forKey: "name") as String? ?? ""
		if !decodedName.isEmpty,
		   decodedName != legacyFileBaseName() + ".track"
		{
			name = decodedName
		}
	}

	func encode(with aCoder: NSCoder) {
		aCoder.encode(points, forKey: "points")
		aCoder.encode(wayPoints, forKey: "waypoints")
		aCoder.encode(name, forKey: "name")
		aCoder.encode(creationDate, forKey: "creationDate")
	}
}

// MARK: - SAX-based GPX parser

private final class GpxSAXParser: NSObject, XMLParserDelegate {
	var trkPoints: [GpxPoint] = []
	var wayPoints: [GpxPoint] = []
	var trackName: String?
	var metadataDate: Date?
	var error: Error?

	// Element path stack (without namespace prefixes)
	private var elementStack: [String] = []
	private var textBuffer = ""

	// Current point being built (for trkpt / wpt)
	private var currentLat: Double?
	private var currentLon: Double?
	private var currentTime: Date?
	private var currentElevation: Double = 0.0
	private var currentName = ""
	private var currentDesc = ""
	private var isWaypoint = false

	private func localName(_ name: String) -> String {
		// Strip namespace prefix if present (e.g. "ns1:trkpt" -> "trkpt")
		if let idx = name.firstIndex(of: ":") {
			return String(name[name.index(after: idx)...])
		}
		return name
	}

	func parser(_ parser: XMLParser,
	            didStartElement elementName: String,
	            namespaceURI: String?,
	            qualifiedName: String?,
	            attributes: [String: String] = [:])
	{
		let local = localName(elementName)
		elementStack.append(local)
		textBuffer = ""

		switch local {
		case "trkpt", "wpt":
			guard let latStr = attributes["lat"],
			      let lonStr = attributes["lon"],
			      let lat = Double(latStr),
			      let lon = Double(lonStr)
			else { return }
			currentLat = lat
			currentLon = lon
			currentTime = nil
			currentElevation = 0.0
			currentName = ""
			currentDesc = ""
			isWaypoint = (local == "wpt")
		default:
			break
		}
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		textBuffer += string
	}

	func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
		if let str = String(data: CDATABlock, encoding: .utf8) {
			textBuffer += str
		}
	}

	func parser(_ parser: XMLParser,
	            didEndElement elementName: String,
	            namespaceURI: String?,
	            qualifiedName: String?)
	{
		let local = localName(elementName)
		defer { elementStack.removeLast() }

		let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

		// Inside a trkpt or wpt
		if let _ = currentLat, elementStack.contains("trkpt") || elementStack.contains("wpt") {
			switch local {
			case "time":
				currentTime = GpxPoint.parseGpxTime(text)
			case "ele":
				currentElevation = Double(text) ?? 0.0
			case "name":
				currentName = text
			case "desc":
				currentDesc = text
			case "trkpt", "wpt":
				if let lat = currentLat, let lon = currentLon {
					let pt = GpxPoint(latLon: LatLon(latitude: lat, longitude: lon),
					                  accuracy: 0.0,
					                  elevation: currentElevation,
					                  timestamp: currentTime,
					                  name: currentName,
					                  desc: currentDesc,
					                  extensions: [])
					if isWaypoint {
						wayPoints.append(pt)
					} else {
						trkPoints.append(pt)
					}
				}
				currentLat = nil
				currentLon = nil
			default:
				break
			}
			return
		}

		// Track name: gpx > trk > name
		if local == "name",
		   elementStack.count >= 3,
		   elementStack[elementStack.count - 2] == "trk",
		   !text.isEmpty
		{
			trackName = text
			return
		}

		// Metadata time: gpx > metadata > time
		if local == "time",
		   elementStack.count >= 3,
		   elementStack[elementStack.count - 2] == "metadata"
		{
			metadataDate = GpxPoint.parseGpxTime(text)
			return
		}
	}

	func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
		error = parseError
	}
}
