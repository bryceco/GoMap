//
//  OSMServer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/26/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

enum OsmServerID {
	case osm
	case dev
	case ohm
	case ogf
}

struct OsmServer {
	let ident: OsmServerID // persistent identifier
	let fullName: String // friendly name of the server
	let apiURL: String // used for API connections
	let authURL: String // used for OAuth connections
	let client_id: String // used for OAuth connections
}

let OsmServerList = [
	OsmServer(ident: .osm,
	          fullName: "OpenStreetMap",
	          apiURL: "https://api.openstreetmap.org/",
	          authURL: "https://www.openstreetmap.org/",
	          client_id: "mzRn5Z-X0nSptHgA3o5g30HeaaljTXfv0GMOLhmwqeo"),

	OsmServer(ident: .dev,
	          fullName: "OSM Dev Server",
	          apiURL: "https://api06.dev.openstreetmap.org/",
	          authURL: "https://master.apis.dev.openstreetmap.org/",
	          client_id: "SGsePsBukg7xPkIaqNIQlAgiAa3vjauIFkbcsPXB2Tg"),

	OsmServer(ident: .ohm,
	          fullName: "OpenHistoricalMap",
	          apiURL: "https://www.openhistoricalmap.org/",
	          authURL: "https://www.openhistoricalmap.org/",
	          client_id: "UnjOHLFzRNc1VKeQJYz2ptqJu_K8fj2hVSsGkTLFjC4"),

	OsmServer(ident: .ogf,
	          fullName: "OpenGeoFiction",
	          apiURL: "https://opengeofiction.net/",
	          authURL: "https://opengeofiction.net/",
	          client_id: "EwlSaN_GLSz6fhkncxU4GWtXG1NyEy2z63QER9ISGFA")
]
