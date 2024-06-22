//
//  TileServer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

private let BingIdentifier = "BingIdentifier"

private let BING_MAPS_KEY: String = [
	"ApunJH62",
	"__wQs1qE32KV",
	"rf6Fmncn",
	"7OZj6gWg_wtr27",
	"DQLDCkwkx",
	"Gl4RsItKW4Fkk"
].reduce("", { r, x in r + x })

/// A provider of tile imagery, such as Bing or Mapbox
final class TileServer: Equatable, Codable {
	private static let iconCache: PersistentWebCache<UIImage> = {
		let cache = PersistentWebCache<UIImage>(name: "AerialServiceIconCache",
		                                        memorySize: 10000,
		                                        daysToKeep: 90.0)
		return cache
	}()

	let name: String
	let identifier: String
	let url: String
	let best: Bool
	let overlay: Bool
	let apiKey: String
	let maxZoom: Int
	let roundZoomUp: Bool
	let startDate: String?
	let endDate: String?
	let wmsProjection: String
	let geoJSON: GeoJSONGeometry?
	let attributionString: String
	let attributionIconString: String?
	let attributionUrl: String
	let placeholderImage: Data?
	let isVector: Bool

	enum CodingKeys: String, CodingKey {
		case name
		case identifier
		case url
		case best
		case overlay
		case apiKey
		case maxZoom
		case roundZoomUp
		case startDate
		case endDate
		case wmsProjection
		case geoJSON
		case attributionString
		case attributionIconString
		case attributionUrl
	}

	static let supportedProjections = [
		"EPSG:3857", // Google Maps and OpenStreetMap
		"EPSG:4326", // like 3857 but lat/lon in reverse order (sometimes)
		"EPSG:900913", // alias for 3857
		"EPSG:3587", // added as typo of 3785
		"EPSG:54004",
		"EPSG:41001",
		"EPSG:102113", // alias for 3857
		"EPSG:102100", // alias for 3857
		"EPSG:3785" // alias for 3857
	]

	convenience init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let name = try container.decode(String.self, forKey: .name)
		let identifier = try container.decode(String.self, forKey: .identifier)
		let url = try container.decode(String.self, forKey: .url)
		let best = try container.decode(Bool.self, forKey: .best)
		let overlay = try container.decode(Bool.self, forKey: .overlay)
		let apiKey = try container.decode(String.self, forKey: .apiKey)
		let maxZoom = try container.decode(Int.self, forKey: .maxZoom)
		let roundZoomUp = try container.decode(Bool.self, forKey: .roundZoomUp)
		let startDate = try container.decode(String?.self, forKey: .startDate)
		let endDate = try container.decode(String?.self, forKey: .endDate)
		let wmsProjection = try container.decode(String.self, forKey: .wmsProjection)
		let geoJSON = try container.decode(GeoJSONGeometry?.self, forKey: .geoJSON)
		let attributionString = try container.decode(String.self, forKey: .attributionString)
		let attributionIconString = try container.decode(String?.self, forKey: .attributionIconString)
		let attributionUrl = try container.decode(String.self, forKey: .attributionUrl)
		let isVector = false

		self.init(withName: name, identifier: identifier, url: url, best: best, overlay: overlay,
		          apiKey: apiKey, maxZoom: maxZoom, roundUp: roundZoomUp, startDate: startDate, endDate: endDate,
		          wmsProjection: wmsProjection, geoJSON: geoJSON,
		          attribString: attributionString, attribIconString: attributionIconString, attribUrl: attributionUrl,
		          isVector: isVector)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encode(identifier, forKey: .identifier)
		try container.encode(url, forKey: .url)
		try container.encode(best, forKey: .best)
		try container.encode(apiKey, forKey: .apiKey)
		try container.encode(maxZoom, forKey: .maxZoom)
		try container.encode(roundZoomUp, forKey: .roundZoomUp)
		try container.encode(startDate, forKey: .startDate)
		try container.encode(endDate, forKey: .endDate)
		try container.encode(wmsProjection, forKey: .wmsProjection)
		try container.encode(geoJSON, forKey: .geoJSON)
		try container.encode(attributionString, forKey: .attributionString)
		try container.encode(attributionUrl, forKey: .attributionUrl)
		try container.encode(attributionIconString, forKey: .attributionIconString)
	}

	init(
		withName name: String,
		identifier: String,
		url: String,
		best: Bool,
		overlay: Bool,
		apiKey: String,
		maxZoom: Int,
		roundUp: Bool,
		startDate: String?,
		endDate: String?,
		wmsProjection projection: String?,
		geoJSON: GeoJSONGeometry?,
		attribString: String,
		attribIconString: String?,
		attribUrl: String,
		isVector: Bool)
	{
		// normalize URLs
		var url = url
		url = url.replacingOccurrences(of: "{ty}", with: "{-y}")
		url = url.replacingOccurrences(of: "{zoom}", with: "{z}")

		self.name = name
		self.identifier = identifier
		self.url = url
		self.best = best
		self.overlay = overlay
		self.apiKey = apiKey
		wmsProjection = projection ?? ""
		attributionString = attribString.count != 0 ? attribString : name
		attributionIconString = attribIconString
		attributionUrl = attribUrl

		self.maxZoom = maxZoom > 0 ? maxZoom : 21
		roundZoomUp = roundUp
		self.startDate = startDate
		self.endDate = endDate
		self.geoJSON = geoJSON
		self.isVector = isVector

		placeholderImage = TileServer.getPlaceholderImage(forIdentifier: identifier)
	}

	static func ==(lhs: TileServer, rhs: TileServer) -> Bool {
		return lhs.identifier == rhs.identifier
	}

	func isBingAerial() -> Bool {
		return self === Self.bingAerial
	}

	func isMaxar() -> Bool {
		return self === Self.maxarPremiumAerial
	}

	func daysToCache() -> Double {
		if self === Self.mapnik {
			return 7.0
		} else {
			return 90.0
		}
	}

	func coversLocation(_ point: LatLon) -> Bool {
		return geoJSON?.contains(point) ?? true
	}

	func isGlobalImagery() -> Bool {
		return geoJSON == nil
	}

	static let dateFormatterList: [DateFormatter] = {
		let formatterYYYYMMDD = DateFormatter()
		formatterYYYYMMDD.dateFormat = "yyyy-MM-dd"
		formatterYYYYMMDD.timeZone = TimeZone(secondsFromGMT: 0)

		let formatterYYYYMM = DateFormatter()
		formatterYYYYMM.dateFormat = "yyyy-MM"
		formatterYYYYMM.timeZone = TimeZone(secondsFromGMT: 0)

		let formatterYYYY = DateFormatter()
		formatterYYYY.dateFormat = "yyyy"
		formatterYYYY.timeZone = TimeZone(secondsFromGMT: 0)

		return [
			formatterYYYYMMDD,
			formatterYYYYMM,
			formatterYYYY
		]
	}()

	class func date(from string: String?) -> Date? {
		guard let string = string else {
			return nil
		}
		for formatter in dateFormatterList {
			if let date = formatter.date(from: string) {
				return date
			}
		}
		return nil
	}

	static let none = TileServer(
		withName: "<none>",
		identifier: "",
		url: "",
		best: false,
		overlay: false,
		apiKey: "",
		maxZoom: 0,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: false)

	static let maxarPremiumAerial = TileServer(
		withName: "Maxar Premium Aerial",
		identifier: "Maxar-Premium",
		url: MaxarPremiumUrl,
		best: false,
		overlay: false,
		apiKey: "",
		maxZoom: 21,
		roundUp: true,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "Maxar Premium",
		attribIconString: "https://osmlab.github.io/editor-layer-index/sources/world/Maxar.png",
		attribUrl: "https://wiki.openstreetmap.org/wiki/DigitalGlobe",
		isVector: false)

	static let mapnik = TileServer(
		withName: "Mapnik",
		identifier: "MapnikIdentifier",
		url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
		best: true,
		overlay: false,
		apiKey: "",
		maxZoom: 19,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: false)

	static let humanitarian = TileServer(
		withName: "Humanitarian",
		identifier: "HotOSMIdentifier",
		url: "http://{switch:a,b,c}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
		best: false,
		overlay: false,
		apiKey: "",
		maxZoom: 20,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: false)

	static let americana = TileServer(
		withName: "Americana",
		identifier: "AmericanaIdentifier",
		url: "https://zelonewolf.github.io/openstreetmap-americana/style.json",
		best: false,
		overlay: false,
		apiKey: "",
		maxZoom: 20,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: true)

	static let openHistoricalMap = TileServer(
		withName: "OpenHistoricalMap",
		identifier: "OpenHistoricalMapIdentifier",
		url: "https://openhistoricalmap.github.io/map-styles/main/main.json",
		best: false,
		overlay: false,
		apiKey: "",
		maxZoom: 20,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: true)

	static let mapboxLocator = TileServer(
		withName: "Mapbox Locator",
		identifier: "MapboxLocatorIdentifier",
		url: "https://api.mapbox.com/styles/v1/openstreetmap/ckasmteyi1tda1ipfis6wqhuq/tiles/256/{zoom}/{x}/{y}?access_token={apikey}",
		best: false,
		overlay: false,
		apiKey: MapboxLocatorToken,
		maxZoom: 20,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: false)

	static let noName = TileServer(
		withName: "Unnamed Roads",
		identifier: "Unnamed Roads",
		url: "https://tile{switch:2,3}.poole.ch/noname/{zoom}/{x}/{y}.png",
		best: false,
		overlay: true,
		apiKey: "",
		maxZoom: 25,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: false)

	static let openGeoFiction = TileServer(
		withName: "OpenGeoFiction",
		identifier: "OpenGeoFictionIdentifier",
		url: "https://tiles04.rent-a-planet.com/ogf-carto/{z}/{x}/{y}.png",
		best: false,
		overlay: false,
		apiKey: "",
		maxZoom: 20,
		roundUp: false,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: nil,
		attribUrl: "",
		isVector: false)

	private static let builtinBingAerial = TileServer(
		withName: "Bing Aerial",
		identifier: BingIdentifier,
		url: "https://ecn.{switch:t0,t1,t2,t3}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=10618&key={apikey}",
		best: false,
		overlay: false,
		apiKey: BING_MAPS_KEY,
		maxZoom: 21,
		roundUp: true,
		startDate: nil,
		endDate: nil,
		wmsProjection: nil,
		geoJSON: nil,
		attribString: "",
		attribIconString: "bing-logo-white",
		attribUrl: "",
		isVector: false)

	private static var dynamicBingAerial: TileServer?

	class var bingAerial: TileServer {
		if let bing = Self.dynamicBingAerial {
			return bing
		}
		return builtinBingAerial
	}

	static func fetchDynamicBingServer(_ callback: ((Result<TileServer, Error>) -> Void)?) {
		struct Welcome: Decodable {
			let brandLogoUri: String
			let resourceSets: [ResourceSet]
			let statusCode: Int
		}
		struct ResourceSet: Decodable {
			let resources: [Resource]
		}
		struct Resource: Decodable {
			let __type: String
			let imageUrl: String
			let imageUrlSubdomains: [String]
			let zoomMax, zoomMin: Int
		}
		let url = "https://dev.virtualearth.net/REST/v1/Imagery/Metadata/Aerial?include=ImageryProviders&key=" +
			BING_MAPS_KEY
		guard let url = URL(string: url) else { return }
		URLSession.shared.data(with: url, completionHandler: { result in
			DispatchQueue.main.async(execute: {
				switch result {
				case let .success(data):
					do {
						let json = try JSONDecoder().decode(Welcome.self, from: data)
						guard
							json.statusCode == 200,
							let resource = json.resourceSets.first?.resources.first
						else {
							callback?(.failure(NSError(domain: "TileServer", code: 1)))
							return
						}

						let subdomains = resource.imageUrlSubdomains.joined(separator: ",")
						var imageUrl = resource.imageUrl
						imageUrl = imageUrl.replacingOccurrences(of: "http://",
						                                         with: "https://")
						imageUrl = imageUrl.replacingOccurrences(of: "{subdomain}",
						                                         with: "{switch:\(subdomains)}")
						imageUrl = imageUrl.replacingOccurrences(of: "{quadkey}",
						                                         with: "{u}")
						imageUrl += "&key={apikey}"
						let bing = TileServer(withName: Self.builtinBingAerial.name,
						                      identifier: Self.builtinBingAerial.identifier,
						                      url: imageUrl,
						                      best: false,
						                      overlay: false,
						                      apiKey: BING_MAPS_KEY,
						                      maxZoom: resource.zoomMax,
						                      roundUp: Self.builtinBingAerial.roundZoomUp,
						                      startDate: Self.builtinBingAerial.startDate,
						                      endDate: Self.builtinBingAerial.endDate,
						                      wmsProjection: Self.builtinBingAerial.wmsProjection,
						                      geoJSON: Self.builtinBingAerial.geoJSON,
						                      attribString: Self.builtinBingAerial.attributionString,
						                      attribIconString: json.brandLogoUri,
						                      attribUrl: Self.builtinBingAerial.attributionUrl,
						                      isVector: false)
						Self.dynamicBingAerial = bing
						callback?(.success(bing))
					} catch {
						print("\(error)")
						callback?(.failure(error))
					}
				case let .failure(error):
					callback?(.failure(error))
				}
			})
		})
	}

	func dictionary() -> [String: Any] {
		return [
			"name": name,
			"url": url,
			"zoom": NSNumber(value: maxZoom),
			"roundUp": NSNumber(value: roundZoomUp),
			"projection": wmsProjection
		]
	}

	convenience init(withDictionary dict: [String: Any]) {
		var url = dict["url"] as! String

		// convert a saved aerial that uses a subdomain list to the new format
		if let subdomains = dict["subdomains"] as? [String] {
			if subdomains.count > 0 {
				var s = subdomains.joined(separator: ",")
				s = String(format: "{switch:\(s)}")
				url = url.replacingOccurrences(of: "{t}", with: s)
			}
		}

		var projection = dict["projection"] as? String
		if (projection?.count ?? 0) == 0 {
			projection = nil
		}

		self.init(withName: dict["name"] as! String,
		          identifier: url,
		          url: url,
		          best: false,
		          overlay: false,
		          apiKey: "",
		          maxZoom: (dict["zoom"] as? NSNumber)?.intValue ?? 0,
		          roundUp: (dict["roundUp"] as? NSNumber)?.boolValue ?? false,
		          startDate: nil, endDate: nil,
		          wmsProjection: projection,
		          geoJSON: nil,
		          attribString: "",
		          attribIconString: nil,
		          attribUrl: "",
		          isVector: false)
	}

	var metadataUrl: String? {
		if isBingAerial() {
			return "https://dev.virtualearth.net/REST/V1/Imagery/Metadata/Aerial/%f,%f?zl=%d&include=ImageryProviders&key=" +
				BING_MAPS_KEY
		}
		return nil
	}

	private static func getPlaceholderImage(forIdentifier ident: String) -> Data? {
		let name: String
		switch ident {
		case BingIdentifier:
			name = "BingPlaceholderImage"
		case "EsriWorldImagery":
			name = "EsriPlaceholderImage"
		default:
			return nil
		}
		if let path = Bundle.main.path(forResource: name, ofType: "png") ??
			Bundle.main.path(forResource: name, ofType: "jpg"),
			let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
			data.count > 0
		{
			return data
		}
		return nil
	}

	func isPlaceholderImage(_ data: Data) -> Bool {
		return placeholderImage?.elementsEqual(data) ?? false
	}

	static func scaleAttribution(icon: UIImage, toHeight height: CGFloat) -> UIImage {
		guard abs(icon.size.height - height) > 0.1 else {
			return icon
		}
		let scale = icon.size.height / height
		var size = icon.size
		size.height /= scale
		size.width /= scale
		UIGraphicsBeginImageContext(size)
		icon.draw(in: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
		let imageCopy = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()
		return imageCopy ?? icon
	}

	private var _attributionIcon: UIImage?
	func attributionIcon(height: CGFloat, completion: (() -> Void)?) -> UIImage? {
		if let icon = _attributionIcon {
			return icon
		}
		guard let attributionIconString = attributionIconString,
		      attributionIconString != ""
		else {
			return nil
		}
		if attributionIconString.hasPrefix("http") {
			guard let completion = completion else {
				return nil
			}
			let url = attributionIconString
			if let icon = TileServer.iconCache.object(withKey: identifier,
			                                          fallbackURL: { URL(string: url) },
			                                          objectForData: { UIImage(data: $0) },
			                                          completion: {
			                                          	if let image = try? $0.get() {
			                                          		self._attributionIcon = Self.scaleAttribution(
			                                          			icon: image,
			                                          			toHeight: height)
			                                          	}
			                                          	completion()
			                                          })
			{
				_attributionIcon = Self.scaleAttribution(icon: icon, toHeight: height)
				return icon
			}
			return nil
		}

		if let range = attributionIconString.range(of: ",") {
			let format = String(attributionIconString.prefix(upTo: range.lowerBound))
			let supported = ["data:image/png;base64": true,
			                 "png:base64": true,
			                 "data:image/svg+xml;base64": false]
			guard supported[format] == true else {
				print("Aerial: unsupported icon format in \(identifier): \(format)")
				return nil
			}
			let string = String(attributionIconString.dropFirst(format.count + 1))
			if let decodedData = Data(base64Encoded: string, options: []),
			   let icon = UIImage(data: decodedData)
			{
				_attributionIcon = Self.scaleAttribution(icon: icon, toHeight: height)
			}
			if _attributionIcon == nil {
				print("bad icon decode: \(attributionIconString)")
			}
			return _attributionIcon
		}

		if let icon = UIImage(named: attributionIconString) {
			_attributionIcon = icon
			return icon
		}

		print("Aerial: unsupported icon format in \(identifier): \(attributionIconString)")
		return nil
	}

	var description: String {
		return name
	}

	private static func TileToWMSCoords(_ tx: Int, _ ty: Int, _ z: Int, _ projection: String) -> OSMPoint {
		let zoomSize = Double(1 << z)
		let lon = Double(tx) / zoomSize * .pi * 2 - .pi
		let lat = atan(sinh(.pi * (1 - Double(2 * ty) / zoomSize)))
		var loc: OSMPoint
		if projection == "EPSG:4326" {
			loc = OSMPoint(x: lon * 180 / .pi, y: lat * 180 / .pi)
		} else {
			// EPSG:3857 and others
			loc = OSMPoint(x: lon, y: log(tan((.pi / 2 + lat) / 2))) // mercatorRaw
			loc = Mult(loc, 20_037508.34 / .pi)
		}
		return loc
	}

	func url(forZoom zoom: Int, tileX: Int, tileY: Int) -> URL? {
		var url = self.url

		// handle switch in URL
		if let begin = url.range(of: "{switch:"),
		   let end = url[begin.upperBound...].range(of: "}")
		{
			let list = url[begin.upperBound..<end.lowerBound].components(separatedBy: ",")
			if list.count > 0 {
				let t = list[(tileX + tileY) % list.count]
				url.replaceSubrange(begin.lowerBound..<end.upperBound, with: t)
			}
		}

		if !wmsProjection.isEmpty {
			// WMS
			let minXmaxY = Self.TileToWMSCoords(tileX, tileY, zoom, wmsProjection)
			let maxXminY = Self.TileToWMSCoords(tileX + 1, tileY + 1, zoom, wmsProjection)
			let bbox: String
			if wmsProjection == "EPSG:4326", url.lowercased().contains("crs={proj}") {
				// reverse lat/lon for EPSG:4326 when WMS version is 1.3 (WMS 1.1 uses srs=epsg:4326 instead
				bbox = "\(maxXminY.y),\(minXmaxY.x),\(minXmaxY.y),\(maxXminY.x)" // lat,lon
			} else {
				bbox = "\(minXmaxY.x),\(maxXminY.y),\(maxXminY.x),\(minXmaxY.y)" // lon,lat
			}

			url = url.replacingOccurrences(of: "{width}", with: "256")
			url = url.replacingOccurrences(of: "{height}", with: "256")
			url = url.replacingOccurrences(of: "{proj}", with: wmsProjection)
			url = url.replacingOccurrences(of: "{bbox}", with: bbox)
			url = url.replacingOccurrences(of: "{wkid}",
			                               with: wmsProjection.replacingOccurrences(of: "EPSG:", with: ""))
			url = url.replacingOccurrences(of: "{w}", with: "\(minXmaxY.x)")
			url = url.replacingOccurrences(of: "{s}", with: "\(maxXminY.y)")
			url = url.replacingOccurrences(of: "{n}", with: "\(maxXminY.x)")
			url = url.replacingOccurrences(of: "{e}", with: "\(minXmaxY.y)")
		} else {
			// TMS
			let u = TileToQuadKey(x: tileX, y: tileY, z: zoom)
			let x = "\(tileX)"
			let y = "\(tileY)"
			let negY = "\((1 << zoom) - tileY - 1)"
			let z = "\(zoom)"

			url = url.replacingOccurrences(of: "{u}", with: u)
			url = url.replacingOccurrences(of: "{x}", with: x)
			url = url.replacingOccurrences(of: "{y}", with: y)
			url = url.replacingOccurrences(of: "{-y}", with: negY)
			url = url.replacingOccurrences(of: "{z}", with: z)
		}
		// retina screen
		let retina = UIScreen.main.scale > 1 ? "@2x" : ""
		url = url.replacingOccurrences(of: "{@2x}", with: retina)

		// apikey
		url = url.replacingOccurrences(of: "{apikey}", with: apiKey)

		// expand spaces
		url = url.replacingOccurrences(of: " ", with: "%20")

		return URL(string: url)
	}
}
