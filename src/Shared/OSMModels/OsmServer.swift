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
		AppDelegate.shared.mapView.editorLayer.mapData.resetServer(OSM_SERVER)
		AppDelegate.shared.userName = nil
	}
}

struct OsmServer {
	let fullName: String // friendly name of the server
	let serverURL: String // e.g. www.openstreetmap.com
	let apiURL: String // e.g. api.openstreetmap.com
	let oAuth2: OAuth2?
	let nominatimUrl: String
	let osmchaUrl: String?

	init(fullName: String,
	     serverHost: String,
	     apiHost: String,
	     nominatimHost: String,
	     osmchaHost: String?,
	     oAuth_client_id: String)
	{
		self.fullName = fullName
		apiURL = "https://" + apiHost + "/"
		serverURL = "https://" + serverHost + "/"
		oAuth2 = OAuth2(serverURL: URL(string: serverURL)!,
		                client_id: oAuth_client_id)
		nominatimUrl = "https://" + nominatimHost + "/"
		if let osmchaHost = osmchaHost {
			osmchaUrl = "https://" + osmchaHost + "/"
		} else {
			osmchaUrl = nil
		}
	}

	init(apiUrl: String) {
		fullName = ""
		apiURL = apiUrl
		serverURL = ""
		oAuth2 = nil
		nominatimUrl = ""
		osmchaUrl = nil
	}

	var taginfoUrl: URL {
		if var comps = URLComponents(string: serverURL),
		   let parts = comps.host?.split(separator: ".")
		{
			let suffix = parts.dropFirst()
			let newParts = ["taginfo"] + suffix
			comps.host = newParts.joined(separator: ".")
			if let url = comps.url {
				return url
			}
		}
		// This won't work but there's nothing we can do about it
		return URL(string: serverURL)!
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
	          serverHost: "www.openstreetmap.org",
	          apiHost: "api.openstreetmap.org",
	          nominatimHost: "nominatim.openstreetmap.org",
	          osmchaHost: "osmcha.org",
	          oAuth_client_id: "mzRn5Z-X0nSptHgA3o5g30HeaaljTXfv0GMOLhmwqeo"),

	OsmServer(fullName: "OSM Dev Server",
	          serverHost: "master.apis.dev.openstreetmap.org",
	          apiHost: "api06.dev.openstreetmap.org",
	          nominatimHost: "nominatim.openstreetmap.org",
	          osmchaHost: nil,
	          oAuth_client_id: "SGsePsBukg7xPkIaqNIQlAgiAa3vjauIFkbcsPXB2Tg"),

	OsmServer(fullName: "OpenHistoricalMap",
	          serverHost: "www.openhistoricalmap.org",
	          apiHost: "www.openhistoricalmap.org",
	          nominatimHost: "nominatim-api.openhistoricalmap.org",
	          osmchaHost: "osmcha.openhistoricalmap.org",
	          oAuth_client_id: "UnjOHLFzRNc1VKeQJYz2ptqJu_K8fj2hVSsGkTLFjC4"),

	OsmServer(fullName: "OpenGeoFiction",
	          serverHost: "opengeofiction.net",
	          apiHost: "opengeofiction.net",
	          nominatimHost: "nominatim.opengeofiction.net",
	          osmchaHost: nil,
	          oAuth_client_id: "EwlSaN_GLSz6fhkncxU4GWtXG1NyEy2z63QER9ISGFA")
]
