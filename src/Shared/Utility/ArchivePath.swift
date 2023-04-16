//
//  ArchivePath.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/13/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

enum ArchivePath {
	case gpxPoints
	case mapMarkerIgnoreList
	case osmDataArchive
	case tagInfo
	case customPresets
	case aerialProviers
	case sqlite(String)
	case webCache(String)

	func path() -> String {
		return url().path
	}

	func url() -> URL {
		switch self {
		case .gpxPoints:
			return Self.urlForName("gpxPoints",
			                       in: .documentDirectory,
			                       bundleID: false)
		case .mapMarkerIgnoreList:
			return Self.urlForName("mapMarkerIgnoreList",
			                       in: .libraryDirectory,
			                       bundleID: false)
		case .osmDataArchive:
			return Self.urlForFile(name: "OSM Downloaded Data.archive",
			                       in: .libraryDirectory,
			                       bundleID: true,
			                       upgrading: [.cachesDirectory])
		case .customPresets:
			return Self.urlForName("CustomPresetList.data",
			                       in: .libraryDirectory,
			                       bundleID: false)
		case .tagInfo:
			return Self.urlForName("tagInfo.plist",
			                       in: .libraryDirectory,
			                       bundleID: true)
		case .aerialProviers:
			return Self.urlForFile(name: "OSM Aerial Providers.json",
			                       in: .libraryDirectory,
			                       bundleID: true,
			                       upgrading: [.cachesDirectory])
		case let .sqlite(name):
			return Self.urlForFile(name: name,
			                       in: .libraryDirectory,
			                       bundleID: true,
			                       upgrading: [.cachesDirectory])
		case let .webCache(name):
			return Self.urlForName(name,
			                       in: .cachesDirectory,
			                       bundleID: true)
		}
	}

	private static func urlForName(_ name: String, in folder: FileManager.SearchPathDirectory, bundleID: Bool) -> URL {
		var url = try! FileManager.default.url(for: folder,
		                                       in: .userDomainMask,
		                                       appropriateFor: nil,
		                                       create: false)
		if bundleID {
			let bundleName = Bundle.main.infoDictionary!["CFBundleIdentifier"] as! String
			url = url.appendingPathComponent(bundleName, isDirectory: true)
		}
		url = url.appendingPathComponent(name, isDirectory: false)
		return url
	}

	private static func createFolderFor(file url: URL) {
		try? FileManager.default.createDirectory(atPath: url.deletingLastPathComponent().path,
		                                         withIntermediateDirectories: true,
		                                         attributes: nil)
	}

	// Compute the path to a file given. If the file only exists at a legacy location
	// them move the file to the new, correct location.
	private static func urlForFile(name: String,
	                               in preferred: FileManager.SearchPathDirectory,
	                               bundleID: Bool,
	                               upgrading legacyDirs: [FileManager.SearchPathDirectory]) -> URL
	{
		let preferredURL = urlForName(name, in: preferred, bundleID: bundleID)
		if FileManager.default.fileExists(atPath: preferredURL.path) {
			return preferredURL
		}
		Self.createFolderFor(file: preferredURL)
		for dir in legacyDirs {
			// If the file is at a secondary location then move it to the preferred location.
			let url = urlForName(name, in: dir, bundleID: bundleID)
			do {
				try FileManager.default.moveItem(at: url, to: preferredURL)
			} catch {
				if (error as NSError).domain == NSCocoaErrorDomain,
				   (error as NSError).code == NSFileWriteFileExistsError
				{
					// already have a copy, so delete this one
					try? FileManager.default.removeItem(at: url)
				}
			}
		}
		return preferredURL
	}
}
