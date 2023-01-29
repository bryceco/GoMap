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

	private func processOsmLabAerialsList(_ featureArray: [Any]?, isGeoJSON: Bool) -> [TileServer] {
		let categories = [
			"photo": true,
			"historicphoto": true,
			"elevation": true
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
		for entry in featureArray ?? [] {
			guard let entry = entry as? [String: Any] else {
				continue
			}

			if isGeoJSON {
				let type = entry["type"] as? String ?? "<undefined>"
				if type != "Feature" {
					print("Aerial: skipping type \(type)")
					continue
				}
			}
			guard let properties: [String: Any] = isGeoJSON ? entry["properties"] as? [String: Any] : entry
			else { continue }

			guard let name = properties["name"] as? String else { continue }
			if name.hasPrefix("Maxar ") {
				// we special case their imagery because they require a special key
				continue
			}

			guard let identifier = properties["id"] as? String else { continue }

			if let category = properties["category"] as? String,
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
			let startDateString = properties["start_date"] as? String
			let endDateString = properties["end_date"] as? String
			let endDate = TileServer.date(from: endDateString)
			if let endDate = endDate,
			   endDate.timeIntervalSinceNow < -20 * 365.0 * 24 * 60 * 60
			{
				continue
			}
			guard let type = properties["type"] as? String else {
				print("Aerial: missing properties: \(name)")
				continue
			}
			let projections = properties["available_projections"] as? [String]
			guard let url = properties["url"] as? String,
			      url.hasPrefix("http:") || url.hasPrefix("https:")
			else {
				// invalid url
				print("Aerial: bad url: \(name)")
				continue
			}

			let propExtent = properties["extent"] as? [String: Any] ?? [:]

			let maxZoom = ((isGeoJSON ? properties : propExtent)["max_zoom"] as? NSNumber)?.intValue ?? 0
			var attribIconString = properties["icon"] as? String ?? ""

			let attribDict = properties["attribution"] as? [String: Any] ?? [:]
			let attribString = attribDict["text"] as? String ?? ""
			let attribUrl = attribDict["url"] as? String ?? ""
			let overlay = (properties["overlay"] as? NSNumber)?.intValue ?? 0
			if let supported = supportedTypes[type],
			   supported == true
			{
				// great
			} else {
				// print("Aerial: unsupported type \(type): \(name)")
				continue
			}
			if overlay != 0 {
				// we don@"t support overlays yet
				continue
			}

			// we only support some types of WMS projections
			var projection: String?
			if type == "wms" {
				projection = projections?.first(where: { supportedProjections.contains($0) })
				if projection == nil {
					continue
				}
			}

			var polygon: CGPath?
			if isGeoJSON {
				if let geometry = entry["geometry"] as? [String: Any] {
					polygon = (try! GeoJSON(geometry: geometry)).cgPath
				}
			} else {
				if let coordinates = propExtent["polygon"] as? [Any] {
					let geometry: [String: Any] = ["type": "Polygon",
					                               "coordinates": coordinates]
					polygon = (try! GeoJSON(geometry: geometry)).cgPath
				}
			}

			var attribIcon: UIImage?
			var httpIcon = false
			if attribIconString.count > 0 {
				if attribIconString.hasPrefix("http") {
					httpIcon = true
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

			let best = properties["best"] != nil

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

			if httpIcon {
				service.loadIcon(fromWeb: attribIconString)
			}
		}
		return externalAerials
	}

	private func processOsmLabAerialsData(_ data: Data?) -> [TileServer] {
		guard let data = data,
		      data.count > 0
		else { return [] }

		let json = try? JSONSerialization.jsonObject(with: data, options: [])
		if let json = json as? [Any] {
			// unversioned (old ELI) variety
			return processOsmLabAerialsList(json, isGeoJSON: false)
		}
		if let json = json as? [String: Any] {
			if let meta = json["meta"] as? [String: Any] {
				// new ELI variety
				guard let formatVersion = meta["format_version"] as? String,
				      formatVersion == "1.0",
				      let metaType = json["type"] as? String,
				      metaType == "FeatureCollection"
				else { return [] }
			} else {
				// josm variety
			}
			let features = json["features"] as? [Any]
			return processOsmLabAerialsList(features, isGeoJSON: true)
		}
		return []
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
