//
//  TagInfo.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/20/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

class TagInfo {
	struct ResultType: Codable {
		let date: Date
		let result: [String]
	}

	typealias CacheType = [String: ResultType]
	private var taginfoCache: CacheType

	init() {
		taginfoCache = Self.load()
	}

	private static func pathToSaveFile() -> URL {
		let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).map(\.path).first!
		let file = URL(fileURLWithPath: dir).appendingPathComponent("tagInfo.plist")
		return file
	}

	private func save() {
		do {
			let path = Self.pathToSaveFile()
			let plistEncoder = PropertyListEncoder()
			plistEncoder.outputFormat = .binary
			let data = try plistEncoder.encode(taginfoCache)
			try data.write(to: path)
		} catch {
			print("\(error)")
		}
	}

	private class func load() -> CacheType {
		do {
			let path = pathToSaveFile()
			let plistEncoder = PropertyListDecoder()
			let data = try Data(contentsOf: path)
			return try plistEncoder.decode(CacheType.self, from: data)
		} catch {
			if (error as NSError).domain == NSCocoaErrorDomain,
			   (error as NSError).code == NSFileReadNoSuchFileError
			{
				// not found, so ignore
			} else {
				print("\(error)")
			}
			return [:]
		}
	}

	// search the taginfo database, return the data immediately if its cached,
	// and call the update function later if it isn't
	class func taginfoFor(key: String, searchKeys: Bool, update: @escaping ([String]) -> Void) {
		DispatchQueue.global(qos: .default).async(execute: {
			let cleanKey = searchKeys ? key.trimmingCharacters(in: CharacterSet(charactersIn: ":")) : key
			let abibase = "https://taginfo.openstreetmap.org/api/4"
			let urlText = searchKeys
				? "\(abibase)/keys/all?query=\(cleanKey)&page=1&rp=25&sortname=count_all&sortorder=desc"
				: "\(abibase)/key/values?key=\(cleanKey)&page=1&rp=25&sortname=count_all&sortorder=desc"
			guard let url = URL(string: urlText),
			      let rawData = try? Data(contentsOf: url)
			else { return }

			let json = try? JSONSerialization.jsonObject(with: rawData, options: []) as? [String: Any]
			let results = json?["data"] as? [[String: Any]] ?? []
			var resultList: [String] = []
			if searchKeys {
				for v in results {
					let inWiki = ((v["in_wiki"] as? NSNumber) ?? 0) == 1
					if !inWiki, (v["count_all"] as? NSNumber)?.intValue ?? 0 < 1000 {
						continue // it's a very uncommon value, so ignore it
					}
					if let k = v["key"] as? String,
					   k.hasPrefix(key),
					   k.count > key.count
					{
						resultList.append(k)
					}
				}
			} else {
				for v in results {
					let inWiki = ((v["in_wiki"] as? NSNumber) ?? 0) == 1
					if !inWiki, ((v["fraction"] as? NSNumber)?.doubleValue ?? 0.0) < 0.01 {
						continue // it's a very uncommon value, so ignore it
					}
					if let val = v["value"] as? String {
						resultList.append(val)
					}
				}
			}
			if resultList.count > 0 {
				DispatchQueue.main.async(execute: {
					update(resultList)
				})
			}
		})
	}

	// search the taginfo database, return the data immediately if its cached,
	// and call the update function later if it isn't
	func taginfoFor(key: String, searchKeys: Bool, update: (() -> Void)?) -> [String] {
		let cacheKey = key + (searchKeys ? ":K" : ":V")
		let cached = taginfoCache[cacheKey]
		let date = cached?.date ?? Date.distantPast

		// if no result or it's out of date then fetch it asynchronously
		if let update = update,
		   Date().timeIntervalSince(date) > 100 * 24 * 60 * 60
		{
			taginfoCache[cacheKey] = ResultType(date: Date(), result: []) // mark as in-transit
			Self.taginfoFor(key: key, searchKeys: searchKeys, update: { result in
				self.taginfoCache[cacheKey] = ResultType(date: Date(), result: result)
				self.save()
				update()
			})
		}
		return cached?.result ?? []
	}
}
