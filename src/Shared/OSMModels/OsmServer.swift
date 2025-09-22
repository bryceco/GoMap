//
//  OsmServer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/26/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

// "https://api.openstreetmap.org/"
var OSM_SERVER: OsmServer = {
	// This initialization is ugly because we want to force fetchCapabilities() to be called
	let server = {
		guard let serverUrl = UserPrefs.shared.osmServerUrl.value else {
			return OsmServerList.first!
		}
		return OsmServer.serverForUrl(serverUrl)
	}()
	Task.detached {
		await server.fetchCapabilities()
	}
	return server
}() {
	didSet {
		if oldValue.apiURL == OSM_SERVER.apiURL {
			return
		}
		UserPrefs.shared.osmServerUrl.value = OSM_SERVER.apiURL
		AppDelegate.shared.mapView.editorLayer.mapData.resetServer(OSM_SERVER)
		AppDelegate.shared.userName = nil
		Task.detached {
			await OSM_SERVER.fetchCapabilities()
		}
	}
}

class OsmServer {
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
		                basePath: "oauth2",
		                authPath: "authorize",
		                client_id: oAuth_client_id,
		                scope: "read_prefs write_prefs read_gpx write_gpx write_notes write_api")
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
		return URL(string: serverURL) ?? URL(string: "https://example.com/error")!
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

	// Capabilities

	struct Capabilities: Codable {
		let policy: Policy
		let api: API
		let copyright, version: String
		let license, attribution: String
		let generator: String
	}

	struct API: Codable {
		let status: Status
		let area: Area
		let tracepoints: Tracepoints
		let waynodes: Area
		let changesets: Changesets
		let notes: Notes
		let timeout: Timeout
		let version: Version
		let relationmembers, noteArea: Area

		enum CodingKeys: String, CodingKey {
			case status, area, tracepoints, waynodes, changesets, notes, timeout, version, relationmembers
			case noteArea = "note_area"
		}
	}

	struct Area: Codable {
		let maximum: Double
	}

	struct Changesets: Codable {
		let maximumElements, defaultQueryLimit, maximumQueryLimit: Int

		enum CodingKeys: String, CodingKey {
			case maximumElements = "maximum_elements"
			case defaultQueryLimit = "default_query_limit"
			case maximumQueryLimit = "maximum_query_limit"
		}
	}

	struct Notes: Codable {
		let defaultQueryLimit, maximumQueryLimit: Int

		enum CodingKeys: String, CodingKey {
			case defaultQueryLimit = "default_query_limit"
			case maximumQueryLimit = "maximum_query_limit"
		}
	}

	struct Status: Codable {
		let api, database, gpx: String
	}

	struct Timeout: Codable {
		let seconds: Int
	}

	struct Tracepoints: Codable {
		let perPage: Int

		enum CodingKeys: String, CodingKey {
			case perPage = "per_page"
		}
	}

	struct Version: Codable {
		let minimum, maximum: String
	}

	struct Policy: Codable {
		let imagery: Imagery
	}

	struct Imagery: Codable {
		let blacklist: [Blacklist]
	}

	struct Blacklist: Codable {
		let regex: String
	}

	var capabilities: Capabilities?
	var bannedUrls: [NSRegularExpression] = []

	func fetchCapabilities() async {
		do {
			let url = URL(string: apiURL + "api/0.6/capabilities.json")!
			let data = try await URLSession.shared.data(with: url)
			let decoder = JSONDecoder()
			capabilities = try decoder.decode(Capabilities.self, from: data)
			bannedUrls = capabilities?.policy.imagery.blacklist.compactMap {
				let regex = $0.regex.replacingOccurrences(of: "\\\\", with: "\\")
				return try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
			} ?? []
		} catch {
			print("\(fullName) capabilities: \(error.localizedDescription)")
		}
	}

	func isBannedURL(_ url: String) -> Bool {
		let urlRange = NSRange(location: 0, length: url.utf16.count)
		return bannedUrls.contains(where: { regex in
			regex.firstMatch(in: url, options: [], range: urlRange) != nil
		})
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
