//
//  OsmNode.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

final class OsmNode: OsmBaseObject {

	private(set) var latLon: LatLon
	/// The last state received from the server, kept only while the object has local edits
	private(set) var serverObject: OsmServerNode?
	var wayCount: Int {
		didSet {
			// a node is drawn differently depending on whether it belongs to a way
			clearCachedProperties()
		}
	}

	var turnRestrictionParentWay: OsmWay! // temporarily used during turn restriction processing

	override var description: String {
		return "OsmNode (\(latLon.lon),\(latLon.lat)) \(super.description)"
	}

	override func isNode() -> OsmNode? {
		return self
	}

	func location() -> OSMPoint {
		return OSMPoint(latLon)
	}

	override func centerPoint() -> LatLon {
		return latLon
	}

	override func selectionPoint() -> LatLon {
		return latLon
	}

	override func latLonOnObject(forLatLon target: LatLon) -> LatLon {
		return latLon
	}

	func isBetter(toKeepThan node: OsmNode) -> Bool {
		if (ident > 0) == (node.ident > 0) {
			// both are new or both are old, so take whichever has more tags
			return tags.count > node.tags.count
		}
		// take the previously existing one
		return ident > 0
	}

	override func nodeSet() -> Set<OsmNode> {
		return Set<OsmNode>([self])
	}

	override func computeBoundingBox() {
		if latLon.lon != 0.0 || latLon.lat != 0.0 {
			_boundingBox = OSMRect(origin: OSMPoint(latLon), size: OSMSize.zero)
		} else {
			// object at null island
			_boundingBox = OSMRect(origin: OSMPoint(x: Double.leastNormalMagnitude, y: latLon.lat), size: OSMSize.zero)
		}
	}

	override func distanceToLineSegment(from latLon1: LatLon, to latLon2: LatLon) -> Double {
		let metersPerDegree = MetersPerDegreeAt(latitude: latLon.lat)
		let p0 = OSMPoint(x: latLon.lon * metersPerDegree.x, y: latLon.lat * metersPerDegree.y)
		let p1 = OSMPoint(x: latLon1.lon * metersPerDegree.x, y: latLon1.lat * metersPerDegree.y)
		let p2 = OSMPoint(x: latLon2.lon * metersPerDegree.x, y: latLon2.lat * metersPerDegree.y)
		return p0.distanceToLineSegment(p1, p2)
	}

	func setLatLon(_ latLon: LatLon, _ token: EditToken) {
		self.latLon = latLon
		clearCachedProperties()
	}

	func serverUpdate(with data: OsmServerNode) {
		super.serverUpdate(header: data)
		latLon = data.latLon
		serverObject = nil
	}

	override func captureServerCopy() {
		if ident > 0, serverObject == nil {
			serverObject = OsmServerNode(self)
		}
	}

	override func clearServerCopy() {
		serverObject = nil
	}

	convenience init(_ data: OsmServerNode) {
		self.init(withVersion: data.version, changeset: data.changeset, user: data.user, uid: data.uid,
		          ident: data.ident, timestamp: data.timestamp, tags: data.tags, latLon: data.latLon)
	}

	override private init(
		withVersion version: Int,
		changeset: Int64,
		user: String,
		uid: Int,
		ident: Int64,
		timestamp: String,
		tags: [String: String],
		deleted: Bool = false)
	{
		latLon = .zero
		wayCount = 0
		super.init(
			withVersion: version,
			changeset: changeset,
			user: user,
			uid: uid,
			ident: ident,
			timestamp: timestamp,
			tags: tags,
			deleted: deleted)
	}

	convenience init(
		withVersion version: Int,
		changeset: Int64,
		user: String,
		uid: Int,
		ident: Int64,
		timestamp: String,
		tags: [String: String],
		latLon: LatLon)
	{
		self.init(withVersion: version, changeset: changeset, user: user,
		          uid: uid, ident: ident, timestamp: timestamp, tags: tags)
		self.latLon = latLon
	}

	convenience init(asUserCreated userName: String, at latLon: LatLon) {
		let ident = OsmBaseObject.nextUnusedIdentifier()
		self.init(withVersion: 1, changeset: 0, user: userName, uid: 0, ident: ident, timestamp: "", tags: [:], deleted: true)
		self.latLon = latLon
	}

	override class var supportsSecureCoding: Bool { true }

	required init?(coder: NSCoder) {
		let lat = coder.decodeDouble(forKey: "lat")
		let lon = coder.decodeDouble(forKey: "lon")
		latLon = LatLon(latitude: lat, longitude: lon)
		wayCount = 0
		if let data = coder.decodeObject(of: NSData.self, forKey: "server") as Data? {
			serverObject = OsmServerNode(serializedData: data)
		}
		super.init(coder: coder)
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(latLon.lat, forKey: "lat")
		coder.encode(latLon.lon, forKey: "lon")
		if let data = serverObject?.serializedData() {
			coder.encode(data, forKey: "server")
		}
	}
}
