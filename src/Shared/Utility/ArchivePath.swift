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
	case aerialProviers
	case customPresets // deprecated, these are stored in UserDefaults now
	case geoJSONs
	case gpxPoints
	case mapMarkerIgnoreList
	case osmDataArchive
	case sqlite(String)
	case tagInfo
	case webCache(String)

	func path() -> String {
		return url().path
	}

	func url() -> URL {
		switch self {
		case .aerialProviers:
			return Self.urlFor(file: "OSM Aerial Providers.json",
			                   in: .libraryDirectory,
			                   bundleID: true,
			                   upgrading: [.cachesDirectory])
		case .customPresets:
			return Self.urlFor(file: "CustomPresetList.data",
			                   in: .libraryDirectory,
			                   bundleID: false)
		case .geoJSONs:
			return Self.urlFor(folder: "geoJSON",
			                   in: .documentDirectory,
			                   bundleID: false)
		case .gpxPoints:
#if DEBUG
			// This is a work in progress. We'd like to get the iCloud Documents directory here.
			// Not sure it is even possible.
			DispatchQueue.main.async {
				MetadataClass.shared.ubiquitousUrlForName("gpxPoints", in: .documentDirectory, callback: { _ in })
			}
#endif
			return Self.urlFor(folder: "gpxPoints",
			                   in: .documentDirectory,
			                   bundleID: false)
		case .mapMarkerIgnoreList:
			return Self.urlFor(file: "mapMarkerIgnoreList",
			                   in: .libraryDirectory,
			                   bundleID: false)
		case .osmDataArchive:
			return Self.urlFor(file: "OSM Downloaded Data.archive",
			                   in: .libraryDirectory,
			                   bundleID: true,
			                   upgrading: [.cachesDirectory])
		case let .sqlite(name):
			assert(name != "")
			return Self.urlFor(file: name,
			                   in: .libraryDirectory,
			                   bundleID: true,
			                   upgrading: [.cachesDirectory])
		case .tagInfo:
			return Self.urlFor(file: "tagInfo.plist",
			                   in: .libraryDirectory,
			                   bundleID: true)
		case let .webCache(name):
			assert(name != "")
			return Self.urlFor(folder: name,
			                   in: .cachesDirectory,
			                   bundleID: true)
		}
	}
}

private extension ArchivePath {
	private static func urlFor(name: String,
	                           isFolder: Bool,
	                           in folder: FileManager.SearchPathDirectory,
	                           bundleID: Bool) -> URL
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
		if isFolder {
			do {
				try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			} catch {
				print("\(error)")
			}
		}
		return url
	}

	private static func urlFor(file name: String,
	                           in folder: FileManager.SearchPathDirectory,
	                           bundleID: Bool) -> URL
	{
		return Self.urlFor(name: name,
		                   isFolder: false,
		                   in: folder,
		                   bundleID: bundleID)
	}

	private static func urlFor(folder name: String,
	                           in folder: FileManager.SearchPathDirectory,
	                           bundleID: Bool) -> URL
	{
		return Self.urlFor(name: name,
		                   isFolder: true,
		                   in: folder,
		                   bundleID: bundleID)
	}

	// Compute the path to a file given. If the file only exists at a legacy location
	// them move the file to the new, correct location.
	private static func urlFor(file name: String,
	                           in preferred: FileManager.SearchPathDirectory,
	                           bundleID: Bool,
	                           upgrading legacyDirs: [FileManager.SearchPathDirectory]) -> URL
	{
		let preferredURL = urlFor(file: name, in: preferred, bundleID: bundleID)
		if FileManager.default.fileExists(atPath: preferredURL.path) {
			return preferredURL
		}
		try? FileManager.default.createDirectory(at: preferredURL.deletingLastPathComponent(),
		                                         withIntermediateDirectories: true)
		for legacyDir in legacyDirs {
			// If the file is at a secondary location then move it to the preferred location.
			let url = urlFor(file: name, in: legacyDir, bundleID: bundleID)
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

class MetadataClass {
	let metadataQuery = NSMetadataQuery()

	init() {}
	static let shared = MetadataClass()
	func ubiquitousUrlForName(_ name: String,
	                          in folder: FileManager.SearchPathDirectory,
	                          callback: @escaping (URL?) -> Void)
	{
		metadataQuery.notificationBatchingInterval = 1
		metadataQuery.searchScopes = [] // [NSMetadataQueryUbiquitousDataScope, NSMetadataQueryUbiquitousDocumentsScope]
		metadataQuery.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.txt")
//		metadataQuery.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(handleQueryNotification(_:)),
		                                       name: NSNotification.Name.NSMetadataQueryDidStartGathering,
		                                       object: metadataQuery)
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(handleQueryNotification(_:)),
		                                       name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
		                                       object: metadataQuery)
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(handleQueryNotification(_:)),
		                                       name: NSNotification.Name.NSMetadataQueryDidUpdate,
		                                       object: metadataQuery)
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(handleQueryNotification(_:)),
		                                       name: NSNotification.Name.NSMetadataQueryGatheringProgress,
		                                       object: metadataQuery)

		NotificationCenter.default.addObserver(
			forName: .NSMetadataQueryDidUpdate,
			object: nil,
			queue: .main,
			using: { _ in
				print("QUery results updated (self.query?.resultCount)")
			})
		NotificationCenter.default.addObserver(
			forName: .NSMetadataQueryDidFinishGathering,
			object: nil,
			queue: .main,
			using: { _ in
				print("Got results (self.query?.results)")
			})
		metadataQuery.enableUpdates()
		metadataQuery.start()

		/*
		 DispatchQueue.global(qos: .default).async {
		 	// let token = FileManager.default.ubiquityIdentityToken
		 	let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)

		 	guard var url = url else { return }
		 	print("\(url)")
		 	do {
		 		var list = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
		 		print("\(list)")
		 		url = url.appendingPathComponent("Documents")
		 		list = try FileManager.default.contentsOfDirectory(at: list[0], includingPropertiesForKeys: nil)
		 		print("\(list)")
		 	} catch {
		 		print("\(error)")
		 	}
		 }
		  */
	}

	@objc func handleQueryNotification(_ notification: Any?) {
		/*
		 let notification = notification as! NSNotification
		 let query = notification.object as! NSMetadataQuery
		 print("Metadata query: \(query)")
		  */
	}
}
