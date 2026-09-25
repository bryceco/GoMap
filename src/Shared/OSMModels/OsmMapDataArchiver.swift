//
//  OsmMapDataArchiver.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/29/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

enum MapDataError: LocalizedError {
	case archiveDoesNotExist
	case archiveCannotBeRead // I/O error
	case archiveCannotBeDecoded // NSKeyedUnarchiver problem

	public var errorDescription: String? {
		switch self {
		case .archiveDoesNotExist: return "MapDataError.archiveDoesNotExist"
		case .archiveCannotBeRead: return "MapDataError.archiveCannotBeRead"
		case .archiveCannotBeDecoded: return "MapDataError.archiveCannotBeDecoded"
		}
	}
}

class OsmMapDataArchiver: NSObject, NSKeyedUnarchiverDelegate {
	func saveArchive(mapData: OsmMapData) -> Bool {
		let archiver = NSKeyedArchiver(requiringSecureCoding: true)
		archiver.encode(mapData, forKey: "OsmMapData")
		archiver.finishEncoding()
		do {
			let url = OsmMapData.pathToArchiveFile()
			try archiver.encodedData.write(to: url, options: [.atomic])
			return true
		} catch {
			return false
		}
	}

	func loadArchive() throws -> OsmMapData {
		var url = OsmMapData.pathToArchiveFile()
		if (try? url.checkResourceIsReachable()) != true {
			// No current-format archive, so fall back to the previous format.
			url = ArchivePath.osmDataArchiveV1.url()
		}
		if (try? url.checkResourceIsReachable()) != true {
			print("Archive file doesn't exist")
			throw MapDataError.archiveDoesNotExist
		}
		guard
			let data = try? Data(contentsOf: url),
			let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
		else {
			print("Archive file doesn't exist")
			throw MapDataError.archiveCannotBeRead
		}
		unarchiver.delegate = self

		guard let decode = unarchiver.decodeObject(of: [OsmMapData.self,
		                                                OsmNode.self,
		                                                OsmWay.self,
		                                                OsmRelation.self,
		                                                OsmMember.self,
		                                                QuadMap.self,
		                                                QuadBox.self,
		                                                MyUndoManager.self,
		                                                UndoAction.self,
		                                                NSDictionary.self,
		                                                NSMutableData.self,
		                                                NSArray.self,
		                                                NSString.self,
		                                                NSNumber.self],
		                                           forKey: "OsmMapData") as? OsmMapData
		else {
			print("Couldn't decode archive file")
			if let error = unarchiver.error {
				print("\(error)")
				throw error
			}
			throw MapDataError.archiveCannotBeDecoded
		}
		return decode
	}

	/// Delete previous-format archives (and old per-version backups).
	/// Call only once all edits have been uploaded, since until then they are
	/// the user's only copy if the app is downgraded.
	static func removeLegacyArchives() {
		let legacy = ArchivePath.osmDataArchiveV1.url()
		try? FileManager.default.removeItem(at: legacy)
	}

	func unarchiver(
		_ unarchiver: NSKeyedUnarchiver,
		cannotDecodeObjectOfClassName name: String,
		originalClasses classNames: [String]) -> AnyClass?
	{
		print("OsmMapDataArchiver: unknown class '\(name)' during unarchive")
		if name == "UndoAction" {
			// Returning nil causes the unarchiver to substitute nil for the unknown object.
			// This gracefully discards stale undo/redo data when upgrading from an older archive format.
			return nil
		}
		fatalError()
	}

	func unarchiver(_ unarchiver: NSKeyedUnarchiver, willReplace object: Any, with newObject: Any) {
		DLog("replacing \(object) -> \(newObject)")
	}
}
