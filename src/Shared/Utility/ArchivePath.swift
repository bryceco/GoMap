//
//  ArchivePath.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/13/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

class ArchivePath {
	class func urlForName(_ name: String, in folder: FileManager.SearchPathDirectory, bundleID: Bool) -> URL {
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

	private class func createFolderFor(file url: URL) {
		try? FileManager.default.createDirectory(atPath: url.deletingLastPathComponent().path,
		                                         withIntermediateDirectories: true,
		                                         attributes: nil)
	}

	// Compute the path to a file given. If the file only exists at a legacy location
	// them move the file to the new, correct location.
	class func urlForFile(name: String,
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
