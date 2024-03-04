//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import FastCodable
import UIKit

enum TypeCastError: Error {
	case invalidType
	case unexpectedNil
	case invalidEnum
}

final class TileServerList {
	private var userDefinedList: [TileServer] = [] // user-defined tile servers
	private var downloadedList: [TileServer] = []
	var mapboxLocator = TileServer.mapboxLocator

	private var recentlyUsedList = MostRecentlyUsed<TileServer>(maxCount: 6,
	                                                            userPrefsKey: .recentAerialsList,
	                                                            autoLoadSave: false)
	private(set) var lastDownloadDate: Date? {
		get { UserPrefs.shared.object(forKey: .lastImageryDownloadDate) as? Date }
		set { UserPrefs.shared.set(object: newValue, forKey: .lastImageryDownloadDate) }
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

		UserPrefs.shared.onChange(.customAerialList, callback: { _ in
			// This occurs if a user added imagery on a different device and it shared to us via iCloud
			self.load()
			self.onChange?()
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
		return ArchivePath.aerialProviers.path()
	}

	func updateDownloadList(with list: [TileServer]) {
		var list = list
		if let locatorIdx = list.indices.first(where: { list[$0].identifier == Self.MapBoxLocatorId }) {
			mapboxLocator = list[locatorIdx]
			list.remove(at: locatorIdx)
		}
		downloadedList = list
	}

	func fetchOsmLabAerials(_ completion: @escaping (_ isAsync: Bool) -> Void) {
		// get cached data
		var cachedData = NSData(contentsOfFile: pathToExternalAerialsCache()) as Data?
		if let data = cachedData {
			var delta = CACurrentMediaTime()
			let externalAerials = Self.processOsmLabAerialsData(data)
			delta = CACurrentMediaTime() - delta
			print("TileServerList decode time = \(delta)")

#if false && DEBUG
			// serialize to bplist
			do {
				let data2 = FastEncoder.encode(externalAerials)
				delta = CACurrentMediaTime()
				let list2 = try FastDecoder.decode([TileServer].self, from: data2)
				delta = CACurrentMediaTime() - delta
				print("t2 = \(delta)")
				if list2 == externalAerials {
					print("match")
				}
			} catch {
				print("\(error)")
			}
#endif

			updateDownloadList(with: externalAerials)
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
						let externalAerials = Self.processOsmLabAerialsData(data)
						if externalAerials.count > 100 {
							// cache download for next time
							let fileUrl = URL(fileURLWithPath: pathToExternalAerialsCache())
							try? data.write(to: fileUrl, options: .atomic)

							// notify caller of update
							DispatchQueue.main.async(execute: { [self] in
								updateDownloadList(with: externalAerials)
								completion(true)
							})
						}
					}
				})
			}
		}
	}

	private func load() {
		let list = UserPrefs.shared.object(forKey: .customAerialList) as? [[String: Any]] ?? []
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
		/*
		  MAXAR is unavailable for the foreseeable future
		 for service in [TileServer.maxarPremiumAerial] {
		 	dict[service.identifier] = service
		 }
		  */

		// fetch and decode recently used list
		recentlyUsedList.load(withMapping: { dict[$0] })

		let currentIdentifier = UserPrefs.shared.string(forKey: .currentAerialSelection)
			?? TileServer.defaultServer
		currentServer = dict[currentIdentifier] ?? dict[TileServer.defaultServer] ?? builtinServers()[0]
	}

	func save() {
		let a = userDefinedList.map({ $0.dictionary() })
		UserPrefs.shared.set(object: a, forKey: .customAerialList)
		UserPrefs.shared.set(currentServer.identifier, forKey: .currentAerialSelection)

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
		/*
		  MAXAR is unavailable for the foreseeable future
		 result.append(TileServer.maxarPremiumAerial)
		 */

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
