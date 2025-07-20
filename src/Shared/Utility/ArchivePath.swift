//
//  ArchivePath.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/13/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

// Provides a centralized place to keep track of locations of various resources.
enum ArchivePath {
	// folders
	case appDataFolder
	case geoJSONs
	case gpxPoints
	case webCache(String)

	// files
	case aerialProviers
	case legacyCustomPresets // deprecated, these are stored in UserDefaults now
	case mapMarkerIgnoreList
	case osmDataArchive
	case sqlite(String)
	case tagInfo

	func path() -> String {
		return url().path
	}

	func urlWith(name: String,
	             in folder: FileManager.SearchPathDirectory,
	             bundleID: Bool = false) -> URL
	{
		var url = try! FileManager.default.url(for: folder,
		                                       in: .userDomainMask,
		                                       appropriateFor: nil,
		                                       create: false)
		if bundleID {
			let bundleName = Bundle.main.bundleIdentifier!
			url = url.appendingPathComponent(bundleName, isDirectory: true)
		}
		url = url.appendingPathComponent(name, isDirectory: false)
		return url
	}

	func urlWith(name: String,
	             in folder: URL,
	             legacy: [URL]) -> URL
	{
		let preferredURL = folder.appendingPathComponent(name, isDirectory: false)
		if FileManager.default.fileExists(atPath: preferredURL.path) {
			return preferredURL
		}
		try? FileManager.default.createDirectory(at: preferredURL.deletingLastPathComponent(),
		                                         withIntermediateDirectories: true)
		for legacyURL in legacy {
			// If the file is at a secondary location then move it to the preferred location.
			do {
				try FileManager.default.moveItem(at: legacyURL, to: preferredURL)
			} catch {
				if (error as NSError).domain == NSCocoaErrorDomain,
				   (error as NSError).code == NSFileWriteFileExistsError
				{
					// already have a copy, so delete this one
					try? FileManager.default.removeItem(at: legacyURL)
				}
			}
		}
		return preferredURL
	}

	func folderURL(_ url: URL) -> URL {
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
		return url
	}

	func url() -> URL {
		switch self {
		case .appDataFolder:
			// a folder under Documents that contains edits and downloaded OSM data
			return folderURL(urlWith(name: "appData", in: .documentDirectory))

		case .geoJSONs:
			return folderURL(urlWith(name: "geoJSON", in: .documentDirectory))

		case .gpxPoints:
			return folderURL(urlWith(name: "gpxPoints", in: .documentDirectory))

		case let .webCache(name):
			assert(name != "")
			return folderURL(urlWith(name: name,
			                         in: .cachesDirectory,
			                         bundleID: true))

			//
			// Folder paths are above here, file paths are below
			//

		case .aerialProviers:
			return urlWith(name: "Aerial Providers.json",
			               in: Self.appDataFolder.url(),
			               legacy: [
			               	urlWith(name: "OSM Aerial Providers.json", in: .libraryDirectory, bundleID: true),
			               	urlWith(name: "OSM Aerial Providers.json", in: .cachesDirectory, bundleID: true)
			               ])

		case .legacyCustomPresets:
			return urlWith(name: "CustomPresetList.data",
			               in: Self.appDataFolder.url(),
			               legacy: [
			               	urlWith(name: "CustomPresetList.data", in: .libraryDirectory)
			               ])

		case .mapMarkerIgnoreList:
			return urlWith(name: "mapMarkerIgnoreList.json",
			               in: Self.appDataFolder.url(),
			               legacy: [
			               	urlWith(name: "mapMarkerIgnoreList", in: .libraryDirectory)
			               ])

		case .osmDataArchive:
			return urlWith(name: "user_edits.archive",
			               in: Self.appDataFolder.url(),
			               legacy: [
			               	urlWith(name: "OSM Downloaded Data.archive", in: .libraryDirectory, bundleID: true),
			               	urlWith(name: "OSM Downloaded Data.archive", in: .cachesDirectory, bundleID: true)
			               ])

		case let .sqlite(name):
			assert(name != "")
			return urlWith(name: name,
			               in: Self.appDataFolder.url(),
			               legacy: [
			               	urlWith(name: name, in: .libraryDirectory, bundleID: true),
			               	urlWith(name: name, in: .cachesDirectory, bundleID: true)
			               ])

		case .tagInfo:
			return urlWith(name: "tagInfo_cache.plist",
			               in: Self.appDataFolder.url(),
			               legacy: [
			               	urlWith(name: "tagInfo.plist", in: .libraryDirectory, bundleID: true)
			               ])
		}
	}
}
