//
//  OsmNode.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

final class OsmNode: OsmBaseObject {
    
    private(set) var lat: Double
    private(set) var lon: Double

    private var _wayCount = 0
    var wayCount: Int {
        get {
            return _wayCount
        } set(wayCount) {
            _wayCount = wayCount
		}
    }
    
	var turnRestrictionParentWay: OsmWay! = nil // temporarily used during turn restriction processing

    override var description: String {
        return "OsmNode (\(lon),\(lat)) \(super.description)"
    }

	override func isNode() -> OsmNode? {
        return self
    }

    func location() -> OSMPoint {
		return OSMPoint(x: lon, y: lat)
    }

    override func selectionPoint() -> OSMPoint {
		return OSMPoint(x: lon, y: lat)
    }

	override func pointOnObjectForPoint(_ target: OSMPoint) -> OSMPoint {
		return OSMPoint(x: lon, y: lat)
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
        if lon != 0.0 || lat != 0.0 {
			_boundingBox = OSMRect(origin: OSMPoint(x: lon, y: lat), size: OSMSize(width: 0, height: 0))
        } else {
            // object at null island
			_boundingBox = OSMRect(origin: OSMPoint(x: Double(Float.leastNormalMagnitude), y: lat), size: OSMSize(width: 0, height: 0))
		}
	}

	override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
        var point1 = point1
        var point2 = point2
		let metersPerDegree = MetersPerDegreeAt(latitude: lat)
		point1.x = (point1.x - lon) * metersPerDegree.x
        point1.y = (point1.y - lat) * metersPerDegree.y
        point2.x = (point2.x - lon) * metersPerDegree.x
        point2.y = (point2.y - lat) * metersPerDegree.y
		let dist = OSMPoint.zero.distanceToLineSegment(point1, point2)
        return dist
    }

    @objc func setLongitude(_ longitude: Double, latitude: Double, undo: MyUndoManager?) {
		if _constructed {
			assert(undo != nil)
            incrementModifyCount(undo!)
            undo!.registerUndo(withTarget: self, selector: #selector(setLongitude(_:latitude:undo:)), objects: [NSNumber(value: lon), NSNumber(value: lat), undo!])
		}
        lon = longitude
        lat = latitude
    }
    
    override func serverUpdate(inPlace newerVersion: OsmBaseObject) {
		let newerVersion = newerVersion as! OsmNode
		super.serverUpdate(inPlace: newerVersion)
        lon = newerVersion.lon
        lat = newerVersion.lat
    }

	override init(withVersion version: Int, changeset: Int64, user: String, uid: Int, ident: Int64, timestamp: String, tags: [String:String]) {
		self.lat = 0.0
		self.lon = 0.0
		super.init(withVersion: version, changeset: changeset, user: user, uid: uid, ident: ident, timestamp: timestamp, tags: tags)
	}

	convenience init(asUserCreated userName: String) {
		let ident = OsmBaseObject.nextUnusedIdentifier()
		self.init(withVersion: 1, changeset: 0, user: userName, uid: 0, ident: ident, timestamp: "", tags: [:])
	}

	override init?(fromXmlDict attributeDict: [String : Any]) {
		self.lat = 0.0
		self.lon = 0.0
		super.init(fromXmlDict: attributeDict)
	}

    required init?(coder: NSCoder) {
		lat = coder.decodeDouble(forKey: "lat")
		lon = coder.decodeDouble(forKey: "lon")
		super.init(coder: coder)
		wayCount = coder.decodeInteger(forKey: "wayCount")
		_constructed = true
   }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
		coder.encode(lat, forKey: "lat")
		coder.encode(lon, forKey: "lon")
		coder.encode(wayCount, forKey: "wayCount")
    }

    @objc func setWayCount(_ wayCount: Int, undo: MyUndoManager?) {
		if _constructed && undo != nil {
            undo!.registerUndo(withTarget: self, selector: #selector(setWayCount(_:undo:)), objects: [NSNumber(value: self.wayCount), undo!])
        }
        self.wayCount = wayCount
    }
}
