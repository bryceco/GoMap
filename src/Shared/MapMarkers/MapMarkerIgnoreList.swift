//
//  MapMarkerIgnoreList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/15/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

enum MapMarkerIgnoreReason: Codable {
	case userRequest
	case userRequestUntil(Date)
}

protocol MapMarkerIgnoreListProtocol: AnyObject {
	func shouldIgnore(ident: String) -> Bool
	func shouldIgnore(marker: MapMarker) -> Bool
	func ignore(marker: MapMarker, reason: MapMarkerIgnoreReason)
}

final class MapMarkerIgnoreList: MapMarkerIgnoreListProtocol, Codable {
	private typealias IgnoreDict = [String: MapMarkerIgnoreReason]

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

	func ignore(marker: MapMarker, reason: MapMarkerIgnoreReason) {
		ignoreList[marker.markerIdentifier] = reason
		writeIgnoreList()
		marker.button?.removeFromSuperview()
		marker.button = nil
	}

	private func readIgnoreList() -> [String: MapMarkerIgnoreReason] {
		let path = ArchivePath.mapMarkerIgnoreList.url()
		guard let data = try? Data(contentsOf: path) else {
			return [:]
		}
		var list: IgnoreDict

		// try to read as JSON
		if let json = try? JSONDecoder().decode(IgnoreDict.self, from: data) {
			list = json
		} else {
			// Legacy: read as archive
			do {
				let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
				list = unarchiver.decodeDecodable(IgnoreDict.self, forKey: NSKeyedArchiveRootObjectKey) ?? [:]
			} catch {
				return [:]
			}
		}

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
	}

	private func writeIgnoreList() {
		do {
			let path = ArchivePath.mapMarkerIgnoreList.url()
			let jsonData = try JSONEncoder().encode(ignoreList)
			try jsonData.write(to: path)
		} catch {
			print("\(error)")
		}
	}
}
