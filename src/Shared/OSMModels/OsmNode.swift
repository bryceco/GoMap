//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  OsmNode.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

class OsmNode: OsmBaseObject {
    
    private(set) var lat: Double = 0.0
    private(set) var lon: Double = 0.0

    private var _wayCount = 0
    var wayCount: Int {
        get {
            return _wayCount
        } set(wayCount) {
            _wayCount = wayCount
        }
    }
    
//    var wayCount: Int {
//        return _wayCount
//    }
    var turnRestrictionParentWay = OsmWay() // temporarily used during turn restriction processing

    override var description: String {
        return "OsmNode (\(lon),\(lat)) \(super.description)"
    }

    func isNode() -> OsmNode {
        return self
    }

    func location() -> OSMPoint {
        return OSMPointMake(lon, lat)
    }

    override func selectionPoint() -> OSMPoint {
        return OSMPointMake(lon, lat)
    }

    override func pointOnObject(for target: OSMPoint) -> OSMPoint {
        return OSMPointMake(lon, lat)
    }

    func isBetter(toKeepThan node: OsmNode) -> Bool {
        if (ident.int64Value > 0) == (node.ident.int64Value > 0) {
            // both are new or both are old, so take whichever has more tags
            return (tags?.count ?? 0) > (node.tags?.count ?? 0)
        }
        // take the previously existing one
        return ident.int64Value > 0
    }
    
    override func nodeSet() -> Set<AnyHashable> {
        return Set<AnyHashable>([self])
    }

    override func computeBoundingBox() {
        if lon != 0.0 || lat != 0.0 {
            let rc = OSMRect(origin: OSMPoint(x: lon, y: lat), size: OSMSize(width: 0, height: 0))
            boundingBox = rc
        } else {
            // object at null island
            let rc = OSMRect(origin: OSMPoint(x: Double(Float.leastNormalMagnitude), y: lat), size: OSMSize(width: 0, height: 0))
            boundingBox = rc
        }
    }

    override func distance(toLineSegment point1: OSMPoint, point point2: OSMPoint) -> Double {
        var point1 = point1
        var point2 = point2
        let metersPerDegree = OSMPoint(x: MetersPerDegreeLongitude(&lat), y: MetersPerDegreeLatitude(&lat))
        point1.x = (point1.x - lon) * metersPerDegree.x
        point1.y = (point1.y - lat) * metersPerDegree.y
        point2.x = (point2.x - lon) * metersPerDegree.x
        point2.y = (point2.y - lat) * metersPerDegree.y
        let dist = Double(DistanceFromPointToLineSegment(OSMPointMake(0, 0), point1, point2))
        return dist
    }

    @objc func setLongitude(_ longitude: Double, latitude: Double, undo: UndoManager?) {
        if _constructed {
            assert(undo != nil)
            incrementModifyCount(undo)
            undo?.registerUndo(withTarget: self, selector: #selector(setLongitude(_:latitude:undo:)), objects: [NSNumber(value: lon), NSNumber(value: lat), undo])
        }
        lon = longitude
        lat = latitude
    }
    
    func serverUpdate(inPlace newerVersion: OsmNode) {
        super.serverUpdate(inPlace: newerVersion)
        lon = newerVersion.lon
        lat = newerVersion.lat
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        if coder.allowsKeyedCoding {
            lat = coder.decodeDouble(forKey: "lat")
            lon = coder.decodeDouble(forKey: "lon")
            wayCount = coder.decodeInteger(forKey: "wayCount")
        } else {
            var len: Int
//            coder.decodeBytes(withReturnedLength: UnsafeMutablePointer<Int>(mutating: &len))
            lat = coder.decodeBytes(withReturnedLength: UnsafeMutablePointer<Int>(mutating: &len))
            lon = coder.decodeBytes(withReturnedLength: UnsafeMutablePointer<Int>(mutating: &len))
            wayCount = coder.decodeBytes(withReturnedLength: UnsafeMutablePointer<Int>(mutating: &len))
        }
        constructed = true
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if coder.allowsKeyedCoding {
            coder.encode(lat, forKey: "lat")
            coder.encode(lon, forKey: "lon")
            coder.encode(wayCount, forKey: "wayCount")
        } else {
            coder.encodeBytes(UnsafeRawPointer(&lat), length: MemoryLayout.size(ofValue: lat))
            coder.encodeBytes(UnsafeRawPointer(&lon), length: MemoryLayout.size(ofValue: lon))
            coder.encodeBytes(UnsafeRawPointer(&wayCount), length: MemoryLayout.size(ofValue: wayCount))
        }
    }

    @objc func setWayCount(_ wayCount: Int, undo: UndoManager?) {
        if constructed && undo != nil {
            undo?.registerUndo(withTarget: self, selector: #selector(setWayCount(_:undo:)), objects: [NSNumber(value: self.wayCount), undo])
        }
        self.wayCount = wayCount
    }
}
