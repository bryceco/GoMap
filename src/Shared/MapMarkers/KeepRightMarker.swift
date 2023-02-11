//
//  KeepRight.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

// A keep-right entry. These use XML just like a GPS waypoint, but with an extension to define OSM data.
class KeepRightMarker: MapMarker {
	let description: String
	let keepRightID: Int
	private let objectId: OsmExtendedIdentifier

	override var markerIdentifier: String {
		return "keepright-\(keepRightID)"
	}

	override var buttonLabel: String { "R" }

	private static var ignoreList: Set<Int> = Set(KeepRightMarker.readIgnoreList())

	func object(from mapData: OsmMapData) -> OsmBaseObject? {
		return mapData.object(withExtendedIdentifier: objectId)
	}

	/// Initialize based on KeepRight query
	init?(gpxWaypoint gpx: GpxPoint, mapData: OsmMapData) {
		//		<wpt lon="-122.2009985" lat="47.6753189">
		//		<name><![CDATA[website, http error]]></name>
		//		<desc><![CDATA[The URL (<a target="_blank" href="http://www.stjamesespresso.com/">http://www.stjamesespresso.com/</a>) cannot be opened (HTTP status code 301)]]></desc>
		//		<extensions>
		//								<schema>21</schema>
		//								<id>78427597</id>
		//								<error_type>411</error_type>
		//								<object_type>node</object_type>
		//								<object_id>2627663149</object_id>
		//		</extensions></wpt>

		var osmIdent: OsmIdentifier?
		var osmType: String?
		var keepRightID: Int?
		for child2 in gpx.extensions {
			guard let child2 = child2 as? DDXMLElement else {
				continue
			}
			if child2.name == "id",
			   let string = child2.stringValue,
			   let id = Int(string)
			{
				keepRightID = id
			} else if child2.name == "object_id" {
				osmIdent = Int64(child2.stringValue ?? "") ?? 0
			} else if child2.name == "object_type" {
				osmType = child2.stringValue
			}
		}
		guard let osmIdent = osmIdent,
		      let osmType = osmType,
		      let keepRightID = keepRightID
		else { return nil }

		guard let type = try? OSM_TYPE(string: osmType) else { return nil }
		let objectId = OsmExtendedIdentifier(type, osmIdent)

		let objectName: String
		if let object = mapData.object(withExtendedIdentifier: objectId) {
			let friendlyDescription = object.friendlyDescription()
			objectName = "\(friendlyDescription) (\(osmType) \(osmIdent))"
		} else {
			objectName = "\(osmType) \(osmIdent)"
		}

		description = "\(objectName): \(gpx.desc)"
		self.keepRightID = keepRightID
		self.objectId = objectId
		super.init(lat: gpx.latLon.lat,
		           lon: gpx.latLon.lon)
	}

	func ignore() {
		Self.ignoreList.insert(keepRightID)
		Self.writeIgnoreList()
		button = nil
	}

	override func shouldHide() -> Bool {
		return Self.ignoreList.contains(keepRightID)
	}

	static func readIgnoreList() -> [Int] {
		if let path = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
			.appendingPathComponent("keepRightIgnoreList"),
			let data = try? Data(contentsOf: path),
			let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data),
			let list = unarchiver.decodeDecodable([Int].self, forKey: NSKeyedArchiveRootObjectKey)
		{
			return list
		} else {
			return []
		}
	}

	static func writeIgnoreList() {
		let archiver = NSKeyedArchiver(requiringSecureCoding: true)
		if let path = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
			.appendingPathComponent("keepRightIgnoreList"),
			(try? archiver.encodeEncodable(Array(ignoreList), forKey: NSKeyedArchiveRootObjectKey)) != nil
		{
			try? archiver.encodedData.write(to: path)
		}
	}
}
