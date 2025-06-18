//
//  CustomAerial.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/21/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

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

	private var recentlyUsedList = MostRecentlyUsed<String>(maxCount: 6,
	                                                        userPrefsKey: UserPrefs.shared.recentAerialsList)
	private(set) var lastDownloadDate: Date? {
		get { UserPrefs.shared.lastImageryDownloadDate.value }
		set { UserPrefs.shared.lastImageryDownloadDate.value = newValue }
	}

	var onChange: (() -> Void)?

	init() {
		Task {
			// fetch the URL of the Bing server in the background
			try? await TileServer.fetchDynamicBingServer()
		}

		fetchOsmLabAerials({ isAsync in
			// This completion might be called twice: first when the cached version loads
			// and then again when an update is downloaded from the internet
			self.load()
			if isAsync {
				self.onChange?()
			}
		})

		UserPrefs.shared.customAerialList.onChangePerform { _ in
			// This occurs if a user added imagery on a different device and it shared to us via iCloud
			self.load()
			self.onChange?()
		}
	}

	func builtinServers() -> [TileServer] {
		return [
			TileServer.bingAerial
		]
	}

	func userDefinedServices() -> [TileServer] {
		return userDefinedList
	}

	func serviceWithIdentifier(_ identifier: String) -> TileServer? {
		return downloadedList.first(where: { identifier == $0.identifier })
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
		let startTime = CACurrentMediaTime()
		var cachedData = NSData(contentsOfFile: pathToExternalAerialsCache()) as Data?
		let readTime = CACurrentMediaTime()
		if let data = cachedData {
			let externalAerials = Self.processOsmLabAerialsData(data)
			print("TileServerList read = \(readTime - startTime), " +
				"decode = \(CACurrentMediaTime() - readTime)")

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
			Task {
				// download newer version periodically
				// let urlString = "https://josm.openstreetmap.de/maps?format=geojson"
				let urlString = "https://osmlab.github.io/editor-layer-index/imagery.geojson"
				guard let downloadUrl = URL(string: urlString),
				      let data = try? await URLSession.shared.data(with: downloadUrl)
				else {
					return
				}
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
					await MainActor.run {
						updateDownloadList(with: externalAerials)
						completion(true)
					}
				}
			}
		}
	}

	func allServices() -> [TileServer] {
		return builtinServers() + downloadedList + userDefinedList
	}

	func allServicesDict() -> [String: TileServer] {
		// build a dictionary of all known sources
		return allServices().reduce(into: [:], { $0[$1.identifier] = $1 })
	}

	private func load() {
		let list = UserPrefs.shared.customAerialList.value ?? []
		userDefinedList = list.map({ TileServer(withDictionary: $0) })

		// build a dictionary of all known sources
		let dict = allServicesDict()

		let currentIdentifier = UserPrefs.shared.currentAerialSelection.value
			?? TileServer.bingAerial.identifier
		currentServer = dict[currentIdentifier] ?? dict[TileServer.bingAerial.identifier] ?? builtinServers()[0]
	}

	func save() {
		let a = userDefinedList.map({ $0.dictionary() })
		UserPrefs.shared.customAerialList.value = a
		UserPrefs.shared.currentAerialSelection.value = currentServer.identifier
	}

	func allServices(at latLon: LatLon, overlay: Bool) -> [TileServer] {
		// find imagery relavent to the viewport
		var result: [TileServer] = []
		for service in downloadedList {
			if service.overlay == overlay,
			   service.coversLocation(latLon)
			{
				result.append(service)
			}
		}

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
			recentlyUsedList.updateWith(currentServer.identifier)
		}
	}

	func recentlyUsed() -> [TileServer] {
		let dict = allServicesDict()
		return recentlyUsedList.items.compactMap { dict[$0] }
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
		recentlyUsedList.remove(service.identifier)
	}
}
