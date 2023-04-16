//
//  MapMarkerIgnoreList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/15/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

enum IgnoreReason: Codable {
	case userRequest
	case userRequestUntil(Date)
}

protocol MapMarkerIgnoreListProtocol: AnyObject {
	func shouldIgnore(ident: String) -> Bool
	func shouldIgnore(marker: MapMarker) -> Bool
	func ignore(marker: MapMarker, reason: IgnoreReason)
}

final class MapMarkerIgnoreList: MapMarkerIgnoreListProtocol, Codable {
	private typealias IgnoreDict = [String: IgnoreReason]

	init() {
		ignoreList = readIgnoreList()
	}

	private var ignoreList: IgnoreDict = [:]

	func shouldIgnore(ident: String) -> Bool {
		return ignoreList[ident] != nil
	}

	func shouldIgnore(marker: MapMarker) -> Bool {
		return shouldIgnore(ident: marker.markerIdentifier)
	}

	func ignore(marker: MapMarker, reason: IgnoreReason) {
		ignoreList[marker.markerIdentifier] = reason
		writeIgnoreList()
		marker.button?.removeFromSuperview()
		marker.button = nil
	}

	private func readIgnoreList() -> [String: IgnoreReason] {
		do {
			let path = ArchivePath.mapMarkerIgnoreList.url()
			let data = try Data(contentsOf: path)
			let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
			var list = unarchiver.decodeDecodable(IgnoreDict.self, forKey: NSKeyedArchiveRootObjectKey) ?? [:]

			// filter out ignored items that expired
			let now = Date()
			list = list.filter({
				switch $0.value {
				case .userRequest:
					return true
				case let .userRequestUntil(date):
					return date > now
				}
			})
			return list
		} catch {
			if (error as NSError).code != NSFileReadNoSuchFileError {
				print("\(error)")
			}
			return [:]
		}
	}

	private func writeIgnoreList() {
		do {
			let archiver = NSKeyedArchiver(requiringSecureCoding: true)
			let path = ArchivePath.mapMarkerIgnoreList.url()
			try archiver.encodeEncodable(ignoreList, forKey: NSKeyedArchiveRootObjectKey)
			try archiver.encodedData.write(to: path)
		} catch {
			print("\(error)")
		}
	}
}
