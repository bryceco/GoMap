//
//  WayPoint.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

// A GPX waypoint
class WayPointMarker: MapMarker {
	let description: String

	/// Initialize based on KeepRight query
	static func parseXML(gpxWaypointXml waypointElement: DDXMLElement, namespace ns: String)
		-> (lon: Double, lat: Double, desc: String, extensions: [DDXMLNode])?
	{
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

		guard let lon2 = waypointElement.attribute(forName: "lon")?.stringValue,
		      let lat2 = waypointElement.attribute(forName: "lat")?.stringValue,
		      let lon = Double(lon2),
		      let lat = Double(lat2)
		else { return nil }

		var description: String = ""
		var extensions: [DDXMLNode] = []

		for child in waypointElement.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			if child.name == "name" {
				// ignore for now
			} else if child.name == "desc" {
				description = child.stringValue ?? ""
			} else if child.name == "extensions",
			          let children = child.children
			{
				extensions = children
			}
		}
		return (lon, lat, description, extensions)
	}

	/// Initialize based on KeepRight query
	init?(gpxWaypointXml waypointElement: DDXMLElement, status: String, namespace ns: String, mapData: OsmMapData) {
		guard let (lon, lat, desc, _) = Self.parseXML(gpxWaypointXml: waypointElement, namespace: ns)
		else { return nil }

		description = desc
		super.init(lat: lat, lon: lon)
	}

	override var key: String {
		fatalError() // return "waypoint-()"
	}

	override var buttonLabel: String { "W" }
}
