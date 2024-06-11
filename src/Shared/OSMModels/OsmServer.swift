//
//  OSMServer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/26/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

// "https://api.openstreetmap.org/"
var OSM_SERVER: OsmServer = {
	guard let serverUrl = UserPrefs.shared.osmServerUrl.value else {
		return OsmServerList.first!
	}
	return OsmServer.serverForUrl(serverUrl)
}() {
	didSet {
		if oldValue.apiURL == OSM_SERVER.apiURL {
			return
		}
		UserPrefs.shared.osmServerUrl.value = OSM_SERVER.apiURL
		AppDelegate.shared.mapView.editorLayer.mapData.setServer(OSM_SERVER)
	}
}

struct OsmServer {
	let fullName: String // friendly name of the server
	let apiURL: String // used for API connections
	let authURL: String // used for OAuth connections
	let nominatimUrl: String
	let client_id: String // used for OAuth connections

	var queryURL: String { // used for things like "www.openstreetmap.org/user/bryceco"
		return authURL
	}

	init(fullName: String,
	     apiHost: String,
	     authHost: String,
	     nominatimHost: String,
	     client_id: String)
	{
		self.fullName = fullName
		apiURL = "https://" + apiHost + "/"
		authURL = "https://" + authHost + "/"
		nominatimUrl = "https://" + nominatimHost + "/"
		self.client_id = client_id
	}

	init(apiUrl: String) {
		fullName = ""
		apiURL = apiUrl
		authURL = ""
		nominatimUrl = ""
		client_id = ""
	}

	var taginfoUrl: String {
		if var comps = URLComponents(string: authURL),
		   let parts = comps.host?.split(separator: ".")
		{
			let suffix = parts.dropFirst()
			let newParts = ["taginfo"] + suffix
			comps.host = newParts.joined(separator: ".")
			if let url = comps.url {
				return url.absoluteString
			}
		}
		// This won't work but there's nothing we can do about it
		return authURL
	}

	static func serverNameCanonicalized(_ hostname: String) -> String {
		var hostname = hostname
		hostname = hostname.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

		if hostname.hasPrefix("http://") || hostname.hasPrefix("https://") {
			// great
		} else {
			hostname = "https://" + hostname
		}

		while hostname.hasSuffix("/") {
			hostname = String(hostname.dropLast())
		}
		hostname = hostname + "/"

		return hostname
	}

	static func serverForUrl(_ url: String) -> OsmServer {
		let url = OsmServer.serverNameCanonicalized(url)
		if let server = OsmServerList.first(where: { $0.apiURL == url }) {
			// it's one of our built-in servers
			return server
		}
		return OsmServer(apiUrl: url)
	}
}

let OsmServerList = [
	OsmServer(fullName: "OpenStreetMap",
	          apiHost: "api.openstreetmap.org",
	          authHost: "www.openstreetmap.org",
	          nominatimHost: "nominatim.openstreetmap.org",
	          client_id: "mzRn5Z-X0nSptHgA3o5g30HeaaljTXfv0GMOLhmwqeo"),

	OsmServer(fullName: "OSM Dev Server",
	          apiHost: "api06.dev.openstreetmap.org",
	          authHost: "master.apis.dev.openstreetmap.org",
	          nominatimHost: "nominatim.openstreetmap.org",
	          client_id: "SGsePsBukg7xPkIaqNIQlAgiAa3vjauIFkbcsPXB2Tg"),

	OsmServer(fullName: "OpenHistoricalMap",
	          apiHost: "www.openhistoricalmap.org",
	          authHost: "www.openhistoricalmap.org",
	          nominatimHost: "nominatim-api.openhistoricalmap.org",
	          client_id: "UnjOHLFzRNc1VKeQJYz2ptqJu_K8fj2hVSsGkTLFjC4"),

	OsmServer(fullName: "OpenGeoFiction",
	          apiHost: "opengeofiction.net",
	          authHost: "opengeofiction.net",
	          nominatimHost: "nominatim.opengeofiction.net",
	          client_id: "EwlSaN_GLSz6fhkncxU4GWtXG1NyEy2z63QER9ISGFA")
]
