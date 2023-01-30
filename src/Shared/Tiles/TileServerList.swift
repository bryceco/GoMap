//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import UIKit

private let CUSTOMAERIALLIST_KEY = "AerialList"
private let CUSTOMAERIALSELECTION_KEY = "AerialListSelection"
private let RECENTLY_USED_KEY = "AerialListRecentlyUsed"


enum TypeCheckCast: Error {
	case invalidType
}

fileprivate func optional<T>(_ val:Any?) throws -> T? {
	guard let val = val else { return nil }
	guard let val = val as? T else { throw TypeCheckCast.invalidType }
	return val
}
fileprivate func nonOptional<T>(_ val:Any?) throws -> T {
	guard let val = val as? T else { throw TypeCheckCast.invalidType }
	return val
}

private struct Welcome {
	let json: [String: Any]
	var features: [Feature] { get throws { (try nonOptional(json["features"]) as [Any]).map { Feature(json: $0)! } } }
	var meta: Meta? { Meta(json: json["meta"]) }
	var type: String { get throws { try nonOptional( json["type"]) as String} }
	init(json: Any?) throws {
		guard let json = json as! [String: Any]? else { throw TypeCheckCast.invalidType }
		self.json = json
	}
}

private struct Feature {
	let json: [String: Any]
	var geometry: GeoJSON? { try? GeoJSON(geometry: json["geometry"] as? [String: Any]) }
	var properties: Properties { Properties(json: json["properties"])! }
	var type: String { json["type"] as! String }
	init?(json: Any?) {
		guard let json = json as! [String: Any]? else { return nil }
		self.json = json
	}
}

private struct Properties {
	let json: [String: Any]
	var attribution: Attribution? { Attribution(json: json["attribution"]) }
	var category: Category? {
		let cat = json["category"] as! String?; return cat != nil ? Category(rawValue: cat!) : nil
	}

	var icon: String? { json["icon"] as! String? }
	var id: String { json["id"] as! String }
	var max_zoom: Int? { (json["max_zoom"] as! NSNumber?)?.intValue }
	var name: String { json["name"] as! String }
	var start_date: String? { json["start_date"] as! String? }
	var end_date: String? { json["end_date"] as! String? }
	var type: PropertiesType { PropertiesType(rawValue: json["type"] as! String)! }
	var url: String { json["url"] as! String }
	var best: Bool? { json["best"] as! Bool? }
	var available_projections: [String]? { json["available_projections"] as! [String]? }
	var overlay: Bool? { (json["overlay"] as! NSNumber?)?.boolValue }
	var transparent: Bool? { json["transparent"] as! Bool? }
	init?(json: Any?) {
		guard let json = json as! [String: Any]? else { return nil }
		self.json = json
	}
}

private struct Attribution {
	let json: [String: Any]
	var attributionRequired: Bool? { json["attributionRequired"] as! Bool? }
	var text: String { json["text"] as! String }
	var url: String? { json["url"] as! String? }
	init?(json: Any?) {
		guard let json = json as! [String: Any]? else { return nil }
		self.json = json
	}
}

private enum Category: String {
	case elevation
	case historicmap
	case historicphoto
	case map
	case osmbasedmap
	case other
	case photo
	case qa
}

private enum PropertiesType: String {
	case bing
	case scanex
	case tms
	case wms
	case wms_endpoint
	case wmts
}

private struct Meta {
	let json: [String: Any]
	var format_version: String { json["format_version"] as! String }
	var generated: String { json["generated"] as! String }
	init?(json: Any?) {
		guard let json = json as! [String: Any]? else { return nil }
		self.json = json
	}
}

final class TileServerList {
	private var userDefinedList: [TileServer] = [] // user-defined tile servers
	private var downloadedList: [TileServer] = [] // downloaded on each launch
	private var recentlyUsedList = MostRecentlyUsed<TileServer>(maxCount: 6,
	                                                            userDefaultsKey: RECENTLY_USED_KEY,
	                                                            autoLoadSave: false)
	private(set) var lastDownloadDate: Date? {
		get { UserDefaults.standard.object(forKey: "lastImageryDownloadDate") as? Date }
		set { UserDefaults.standard.set(newValue, forKey: "lastImageryDownloadDate") }
	}

	var onChange: (() -> Void)?

	init() {
		TileServer.fetchDynamicBingServer(nil)

		fetchOsmLabAerials({ isAsync in
			// This completion might be called twice: first when the cached version loads
			// and then again when an update is downloaded from the internet
			self.load()
			if isAsync {
				self.onChange?()
			}
		})
	}

	func builtinServers() -> [TileServer] {
		return [
			TileServer.bingAerial
		]
	}

	func userDefinedServices() -> [TileServer] {
		return userDefinedList
	}

	private func pathToExternalAerialsCache() -> String {
		// get tile cache folder
		let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).map(\.path)
		if paths.count != 0 {
			let bundleName = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String
			let path = URL(fileURLWithPath: URL(fileURLWithPath: paths[0]).appendingPathComponent(bundleName ?? "")
				.path).appendingPathComponent("OSM Aerial Providers.json").path
			do {
				try FileManager.default.createDirectory(
					atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
					withIntermediateDirectories: true,
					attributes: nil)
			} catch {}
			return path
		}
		return ""
	}

	private func processOsmLabAerialsList(_ featureArray: [Feature]) throws -> [TileServer] {
		let categories: [Category: Bool] = [
			.photo: true,
			.historicphoto: true,
			.elevation: true
		]

		let supportedTypes = [
			"tms": true,
			"wms": true,
			"scanex": false,
			"wms_endpoint": false,
			"wmts": false,
			"bing": false
		]

		let supportedProjections = Set<String>(TileServer.supportedProjections)

		var externalAerials: [TileServer] = []
		for entry in featureArray {
			guard
				entry.type == "Feature"
			else {
				print("Aerial: skipping non-Feature")
				continue
			}

			let properties = entry.properties
			let name = properties.name
			if name.hasPrefix("Maxar ") {
				// we special case their imagery because they require a special key
				continue
			}

			let identifier = properties.id

			if let category = properties.category,
			   let supported = categories[category],
			   supported
			{
				// good
			} else if identifier == "OpenTopoMap" {
				// special exception for this one
			} else {
				// NSLog(@"category %@ - %@",category,identifier);
				continue
			}
			let startDateString = properties.start_date
			let endDateString = properties.end_date
			let endDate = TileServer.date(from: endDateString)
			if let endDate = endDate,
			   endDate.timeIntervalSinceNow < -20 * 365.0 * 24 * 60 * 60
			{
				continue
			}
			let url = properties.url
			guard
				url.hasPrefix("http:") || url.hasPrefix("https:")
			else {
				// invalid url
				print("Aerial: bad url: \(name)")
				continue
			}

			let maxZoom = properties.max_zoom ?? 0

			let type = properties.type
			if let supported = supportedTypes[type.rawValue],
			   supported == true
			{
				// great
			} else {
				// print("Aerial: unsupported type \(type): \(name)")
				continue
			}

			if properties.overlay ?? false {
				// we don@"t support overlays yet
				continue
			}

			// we only support some types of WMS projections
			var projection: String?
			if type == .wms {
				projection = properties.available_projections?.first(where: { supportedProjections.contains($0) })
				if projection == nil {
					continue
				}
			}

			var polygon: CGPath?
			if let geometry = entry.geometry {
				polygon = geometry.cgPath
			}

			let attribIconString = properties.icon
			var attribIconStringIsHttp = false
			var attribIcon: UIImage?
			let attribDict = properties.attribution
			let attribString = attribDict?.text ?? ""
			let attribUrl = attribDict?.url ?? ""
			if var attribIconString = attribIconString {
				if attribIconString.hasPrefix("http") {
					attribIconStringIsHttp = true
				} else if let range = attribIconString.range(of: ",") {
					let format = String(attribIconString.prefix(upTo: range.lowerBound))
					let supported = ["data:image/png;base64": true,
					                 "png:base64": true,
					                 "data:image/svg+xml;base64": false]
					if supported[format] == true {
						attribIconString.removeFirst(format.count + 1)
						if let decodedData = Data(base64Encoded: attribIconString, options: []) {
							attribIcon = UIImage(data: decodedData)
						}
						if attribIcon == nil {
							print("bad icon decode: \(attribIconString)")
						}
					} else {
						print("Aerial: unsupported icon format in \(identifier): \(format)")
					}
				} else {
					print("Aerial: unsupported icon format in \(identifier): \(attribIconString)")
				}
			}

			let best = properties.best ?? false

			// support for {apikey}
			var apikey = ""
			if url.contains(".thunderforest.com/") {
				// Please don't use in other apps. Sign up for a free account at Thunderforest.com insead.
				apikey = "be3dc024e3924c22beb5f841d098a8a3"
			}

			if url.contains("{apikey}"),
			   apikey == ""
			{
				continue
			}

			let service = TileServer(withName: name,
			                         identifier: identifier,
			                         url: url,
			                         best: best,
			                         apiKey: apikey,
			                         maxZoom: maxZoom,
			                         roundUp: true,
			                         startDate: startDateString,
			                         endDate: endDateString,
			                         wmsProjection: projection,
			                         polygon: polygon,
			                         attribString: attribString,
			                         attribIcon: attribIcon,
			                         attribUrl: attribUrl)

			externalAerials.append(service)

			if attribIconStringIsHttp {
				service.loadIcon(fromWeb: attribIconString!)
			}
		}
		return externalAerials
	}

	private func processOsmLabAerialsData(_ data: Data?) -> [TileServer] {
		guard let data = data,
		      data.count > 0
		else { return [] }

		do {

			let json = try JSONSerialization.jsonObject(with: data, options: [])
			let welcome = try Welcome(json: json)

			if let meta = welcome.meta {
				// new ELI variety
				guard meta.format_version == "1.0",
					 try welcome.type == "FeatureCollection"
				else { return [] }
			} else {
				// josm variety
			}
			let features = try welcome.features
			return try processOsmLabAerialsList(features)
		} catch {
			print("\(error)")
			return []
		}
	}

	private func fetchOsmLabAerials(_ completion: @escaping (_ isAsync: Bool) -> Void) {
		// get cached data
		var cachedData = NSData(contentsOfFile: pathToExternalAerialsCache()) as Data?
		if let data = cachedData {
			var delta = CACurrentMediaTime()
			let externalAerials = processOsmLabAerialsData(data)
			delta = CACurrentMediaTime() - delta
			print("TileServerList decode time = \(delta)")
			downloadedList = externalAerials
			completion(false)

			if externalAerials.count < 100 {
				// something went wrong, so we need to download
				cachedData = nil
			}
		}

		if let last = lastDownloadDate {
			if -last.timeIntervalSinceNow >= 60 * 60 * 24 * 7 {
				cachedData = nil
			}
		} else {
			cachedData = nil
		}

		if cachedData == nil {
			// download newer version periodically
			// let urlString = "https://josm.openstreetmap.de/maps?format=geojson"
			let urlString = "https://osmlab.github.io/editor-layer-index/imagery.geojson"
			if let downloadUrl = URL(string: urlString) {
				URLSession.shared.data(with: downloadUrl, completionHandler: { [self] result in
					if case let .success(data) = result {
						if data.count > 100000 {
							// if the data is large then only download again periodically
							self.lastDownloadDate = Date()
						}
						let externalAerials = processOsmLabAerialsData(data)
						if externalAerials.count > 100 {
							// cache download for next time
							let fileUrl = URL(fileURLWithPath: pathToExternalAerialsCache())
							try? data.write(to: fileUrl, options: .atomic)

							// notify caller of update
							DispatchQueue.main.async(execute: { [self] in
								downloadedList = externalAerials
								completion(true)
							})
						}
					}
				})
			}
		}
	}

	private func load() {
		let defaults = UserDefaults.standard
		let list = defaults.object(forKey: CUSTOMAERIALLIST_KEY) as? [[String: Any]] ?? []
		userDefinedList = list.map({ TileServer(withDictionary: $0) })

		// build a dictionary of all known sources
		var dict: [String: TileServer] = [:]
		for service in builtinServers() {
			dict[service.identifier] = service
		}
		for service in downloadedList {
			dict[service.identifier] = service
		}
		for service in userDefinedList {
			dict[service.identifier] = service
		}
		for service in [TileServer.maxarPremiumAerial] {
			dict[service.identifier] = service
		}

		// fetch and decode recently used list
		recentlyUsedList.load(withMapping: { dict[$0] })

		let currentIdentifier = (defaults.object(forKey: CUSTOMAERIALSELECTION_KEY) as? String)
			?? TileServer.defaultServer
		currentServer = dict[currentIdentifier] ?? dict[TileServer.defaultServer] ?? builtinServers()[0]
	}

	func save() {
		let defaults = UserDefaults.standard
		let a = userDefinedList.map({ $0.dictionary() })
		defaults.set(a, forKey: CUSTOMAERIALLIST_KEY)
		defaults.set(currentServer.identifier, forKey: CUSTOMAERIALSELECTION_KEY)

		recentlyUsedList.save(withMapping: { $0.identifier })
	}

	func allServices(at latLon: LatLon) -> [TileServer] {
		// find imagery relavent to the viewport
		var result: [TileServer] = []
		for service in downloadedList {
			if service.coversLocation(latLon) {
				result.append(service)
			}
		}
		result.append(TileServer.maxarPremiumAerial)

		result = result.sorted(by: {
			if $0.best, !$1.best {
				return true
			}
			if $1.best, !$0.best {
				return false
			}
			return $0.name.caseInsensitiveCompare($1.name) == .orderedAscending
		})
		return result
	}

	func bestService(at latLon: LatLon) -> TileServer? {
		for service in downloadedList {
			if service.best,
			   service.coversLocation(latLon)
			{
				return service
			}
		}
		return nil
	}

	var currentServer = TileServer.bingAerial {
		didSet {
			recentlyUsedList.updateWith(currentServer)
		}
	}

	func recentlyUsed() -> [TileServer] {
		return recentlyUsedList.items
	}

	func count() -> Int {
		return userDefinedList.count
	}

	func service(at index: Int) -> TileServer {
		return userDefinedList[index]
	}

	func addUserDefinedService(_ service: TileServer, at index: Int) {
		userDefinedList.insert(service, at: index)
	}

	func removeUserDefinedService(at index: Int) {
		if index >= userDefinedList.count {
			return
		}
		let service = userDefinedList[index]
		userDefinedList.remove(at: index)
		if service == currentServer {
			currentServer = builtinServers()[0]
		}
		recentlyUsedList.remove(service)
	}
}
