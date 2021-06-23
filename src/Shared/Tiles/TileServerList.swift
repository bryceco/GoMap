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
	private var _recentlyUsed: [TileServer] = []
	private(set) var lastDownloadDate: Date? {
		get { UserDefaults.standard.object(forKey: "lastImageryDownloadDate") as? Date }
		set { UserDefaults.standard.set(newValue, forKey: "lastImageryDownloadDate") }
	}

	init() {
		fetchOsmLabAerials({ [self] in
			// if a non-builtin aerial service is current then we need to select it once the list is loaded
			load()
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

	private func addPoints(_ points: [[NSNumber]], to path: CGMutablePath) {
		var first = true
		for pt in points {
			if pt.count != 2 {
				continue
			}
			let lon = CGFloat(pt[0].doubleValue)
			let lat = CGFloat(pt[1].doubleValue)
			let cgPoint = CGPoint(x: lon, y: lat)
			if first {
				path.move(to: cgPoint)
				first = false
			} else {
				path.addLine(to: cgPoint)
			}
		}
		path.closeSubpath()
	}

	private func processOsmLabAerialsList(_ featureArray: [Any]?, isGeoJSON: Bool) -> [TileServer] {
		let categories = [
			"photo": true,
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
			let category = properties["category"] as? String
			if categories[category ?? ""] == nil {
				if identifier == "OpenTopoMap" {
					// okay
				} else {
					// NSLog(@"category %@ - %@",category,identifier);
					continue
				}
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
			guard var url = properties["url"] as? String,
			      url.hasPrefix("http:") || url.hasPrefix("https:")
			else {
				// invalid url
				print("Aerial: bad url: \(name)")
				continue
			}

			let propExtent = properties["extent"] as? [String: Any] ?? [:]

			let maxZoom = ((isGeoJSON ? properties : propExtent)["max_zoom"] as? NSNumber)?.intValue ?? 21
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

			var polygonPoints: [Any]?
			var isMultiPolygon = false // a GeoJSON multipolygon, which has an extra layer of nesting
			if isGeoJSON {
				if let geometry = entry["geometry"] as? [String: Any] {
					polygonPoints = geometry["coordinates"] as? [Any]
					isMultiPolygon = (geometry["type"] as? String ?? "") == "MultiPolygon"
				}
			} else {
				polygonPoints = propExtent["polygon"] as? [Any]
			}

			var polygon: CGPath?
			if let polygonPoints = polygonPoints {
				let path = CGMutablePath()
				if isMultiPolygon {
					if let polygonPoints = polygonPoints as? [[[[NSNumber]]]] {
						for outer in polygonPoints {
							for loop in outer {
								addPoints(loop, to: path)
							}
						}
					}
				} else {
					if let polygonPoints = polygonPoints as? [[[NSNumber]]] {
						for loop in polygonPoints {
							addPoints(loop, to: path)
						}
					}
				}
				polygon = path.copy()
			}

			var attribIcon: UIImage?
			var httpIcon = false
			if attribIconString.count > 0 {
				let prefixList = ["data:image/png;base64,", "data:image/png:base64,", "png:base64,"]
				for prefix in prefixList {
					if attribIconString.hasPrefix(prefix) {
						attribIconString.removeFirst(prefix.count)
						if let decodedData = Data(base64Encoded: attribIconString, options: []) {
							attribIcon = UIImage(data: decodedData)
						}
						if attribIcon == nil {
							print("bad icon decode: \(attribIconString)")
						}
						break
					}
				}
				if attribIcon == nil {
					if attribIconString.hasPrefix("http") {
						httpIcon = true
					} else {
						print("Aerial: unsupported icon format in \(name): \(attribIconString)")
					}
				}
			}

			// support for {apikey}
			if url.contains("{apikey}") {
				var apikey: String = ""
				if url.contains(".thunderforest.com/") {
					apikey =
						"be3dc024e3924c22beb5f841d098a8a3" // Please don't use in other apps. Sign up for a free account at Thunderforest.com insead.
				} else {
					continue
				}
				url = url.replacingOccurrences(of: "{apikey}", with: apikey)
			}

			let service = TileServer(withName: name,
			                         identifier: identifier,
			                         url: url,
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
		externalAerials = externalAerials.sorted(by: { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending })
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

	private func fetchOsmLabAerials(_ completion: @escaping () -> Void) {
		// get cached data
		var cachedData = NSData(contentsOfFile: pathToExternalAerialsCache()) as Data?
		if let data = cachedData {
			var delta = CACurrentMediaTime()
			let externalAerials = processOsmLabAerialsData(data)
			delta = CACurrentMediaTime() - delta
			print("TileServerList decode time = \(delta)")
			downloadedList = externalAerials
			completion()

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
			let urlString = "https://josm.openstreetmap.de/maps?format=geojson"
			// NSString * urlString = @"https://osmlab.github.io/editor-layer-index/imagery.geojson";
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
								completion()
							})
						}
					}
				})
			}
		}
	}

	private func load() {
		let list = UserDefaults.standard.object(forKey: CUSTOMAERIALLIST_KEY) as? [[String: Any]] ?? []
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
		for service in [
			TileServer.maxarPremiumAerial,
			TileServer.maxarStandardAerial
		] {
			dict[service.identifier] = service
		}

		// fetch and decode recently used list
		let recentIdentiers: [String] = UserDefaults.standard.object(forKey: RECENTLY_USED_KEY) as? [String] ?? []
		_recentlyUsed = recentIdentiers.compactMap({ dict[$0] })

		let currentIdentifier: String = (UserDefaults.standard.object(forKey: CUSTOMAERIALSELECTION_KEY) as? String) ??
			TileServer.defaultServer
		currentServer = dict[currentIdentifier] ?? dict[TileServer.defaultServer] ?? builtinServers()[0]
	}

	func save() {
		let defaults = UserDefaults.standard
		let a = userDefinedList.map({ $0.dictionary() })
		defaults.set(a, forKey: CUSTOMAERIALLIST_KEY)
		defaults.set(currentServer.identifier, forKey: CUSTOMAERIALSELECTION_KEY)

		var recents: [Any] = []
		for service in _recentlyUsed {
			recents.append(service.identifier)
		}
		defaults.set(recents, forKey: RECENTLY_USED_KEY)
	}

	func services(forRegion rect: OSMRect) -> [TileServer] {
		// find imagery relavent to the viewport
		let center = CGPoint(x: rect.origin.x + rect.size.width / 2, y: rect.origin.y + rect.size.height / 2)
		var result: [TileServer] = []
		for service in downloadedList {
			if service.polygon == nil || (service.polygon?.contains(center, using: .winding) ?? false) {
				result.append(service)
			}
		}
		result.append(TileServer.maxarPremiumAerial)
		result.append(TileServer.maxarStandardAerial)

		result = result.sorted(by: { $0.name < $1.name })
		return result
	}

	var currentServer = TileServer.bingAerial {
		didSet {
			// update recently used
			let MAX_ITEMS = 6
			_recentlyUsed.removeAll { $0 === currentServer }
			_recentlyUsed.insert(currentServer, at: 0)

			while _recentlyUsed.count > MAX_ITEMS {
				_recentlyUsed.removeLast()
			}
		}
	}

	func recentlyUsed() -> [TileServer] {
		return _recentlyUsed
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
		let s = userDefinedList[index]
		userDefinedList.remove(at: index)
		if s === currentServer {
			currentServer = builtinServers()[0]
		}
		_recentlyUsed.removeAll { $0 as AnyObject === s as AnyObject }
	}
}
