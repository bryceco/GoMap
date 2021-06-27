//
//  OsmNode.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

final class OsmNode: OsmBaseObject {
	private(set) var latLon: LatLon
	private(set) var wayCount: Int

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

	override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
		var point1 = point1
		var point2 = point2
		let metersPerDegree = MetersPerDegreeAt(latitude: latLon.lat)
		point1.x = (point1.x - latLon.lon) * metersPerDegree.x
		point1.y = (point1.y - latLon.lat) * metersPerDegree.y
		point2.x = (point2.x - latLon.lon) * metersPerDegree.x
		point2.y = (point2.y - latLon.lat) * metersPerDegree.y
		let dist = OSMPoint.zero.distanceToLineSegment(point1, point2)
		return dist
	}

	@objc func setLongitude(_ longitude: Double, latitude: Double, undo: MyUndoManager?) {
		if _constructed {
			assert(undo != nil)
			incrementModifyCount(undo!)
			undo!.registerUndo(withTarget: self,
			                   selector: #selector(setLongitude(_:latitude:undo:)),
			                   objects: [NSNumber(value: latLon.lon), NSNumber(value: latLon.lat), undo!])
		}
		latLon = LatLon(latitude: latitude, longitude: longitude)
	}

	override func serverUpdate(inPlace newerVersion: OsmBaseObject) {
		let newerVersion = newerVersion as! OsmNode
		super.serverUpdate(inPlace: newerVersion)
		latLon = newerVersion.latLon
	}

	override init(
		withVersion version: Int,
		changeset: Int64,
		user: String,
		uid: Int,
		ident: Int64,
		timestamp: String,
		tags: [String: String])
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
			tags: tags)
	}

	convenience init(asUserCreated userName: String) {
		let ident = OsmBaseObject.nextUnusedIdentifier()
		self.init(withVersion: 1, changeset: 0, user: userName, uid: 0, ident: ident, timestamp: "", tags: [:])
	}

	/// Initialize with XML downloaded from OSM server
	override init?(fromXmlDict attributeDict: [String: Any]) {
		latLon = .zero
		wayCount = 0
		super.init(fromXmlDict: attributeDict)
	}

	required init?(coder: NSCoder) {
		let lat = coder.decodeDouble(forKey: "lat")
		let lon = coder.decodeDouble(forKey: "lon")
		latLon = LatLon(latitude: lat, longitude: lon)
		wayCount = 0
		super.init(coder: coder)
		_constructed = true
	}

	override func encode(with coder: NSCoder) {
		super.encode(with: coder)
		coder.encode(latLon.lat, forKey: "lat")
		coder.encode(latLon.lon, forKey: "lon")
	}

	func setWayCount(_ wayCount: Int, undo: MyUndoManager?) {
		if _constructed, undo != nil {
			undo!.registerUndo(
				withTarget: self,
				selector: #selector(setWayCount(_:undo:)),
				objects: [NSNumber(value: self.wayCount), undo!])
		}
		self.wayCount = wayCount
	}
}
