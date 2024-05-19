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
	case customPresets // deprecated, these are stored in UserDefaults now
	case aerialProviers
	case sqlite(String)
	case webCache(String)

	func path() -> String {
		return url().path
	}

	func url() -> URL {
		switch self {
		case .gpxPoints:
#if DEBUG
			// This is a work in progress. We'd like to get the iCloud Documents directory here.
			// Not sure it is even possible.
			DispatchQueue.main.async {
				MetadataClass.shared.ubiquitousUrlForName("gpxPoints", in: .documentDirectory, callback: { _ in })
			}
#endif
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
}

private extension ArchivePath {
	private static func urlForName(_ name: String, in folder: FileManager.SearchPathDirectory, bundleID: Bool) -> URL {
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
