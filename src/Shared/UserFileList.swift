//
//  GeoJSONList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/20/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

let geoJsonList = UserFileList(prefsKey: UserPrefs.shared.geoJsonFileList,
                               archiveKey: .geoJSONs)

class UserFileList {
	struct Entry {
		let url: URL
		var visible: Bool
	}

	let archiveKey: ArchivePath
	let prefsKey: Pref<[String: Bool]>

	private var list: [Entry] = []

	func visible() -> [URL] {
		return list.compactMap { $0.visible ? $0.url : nil }
	}

	init(prefsKey: Pref<[String: Bool]>, archiveKey: ArchivePath) {
		self.prefsKey = prefsKey
		self.archiveKey = archiveKey
		do {
			let prefDict = prefsKey.value ?? [:]
			let files = try FileManager.default.contentsOfDirectory(at: archiveKey.url(),
			                                                        includingPropertiesForKeys: nil)
			list = files.map {
				Entry(url: $0, visible: prefDict[$0.lastPathComponent] ?? true)
			}
		} catch {
			print("\(error)")
		}
	}

	private func savePrefs() {
		let prefDict = list.reduce(into: [String: Bool](), { $0[$1.url.lastPathComponent] = $1.visible })
		prefsKey.value = prefDict
	}

	var count: Int {
		return list.count
	}

	subscript(index: Int) -> Entry {
		return list[index]
	}

	func toggleVisible(_ index: Int) {
		guard index >= 0, index < list.count else {
			return
		}
		list[index].visible = !list[index].visible
		savePrefs()
	}

	func remove(_ index: Int) {
		guard index >= 0, index < list.count else {
			return
		}
		let url = list[index].url
		list.remove(at: index)
		try? FileManager.default.removeItem(at: url)
		savePrefs()
	}

	func add(name: String, data: Data) throws {
		let url = archiveKey.url().appendingPathComponent(name)
		try data.write(to: url)
		list.removeAll(where: { $0.url.lastPathComponent == url.lastPathComponent })
		list.append(Entry(url: url, visible: true))
		savePrefs()
	}

	func add(url sourceURL: URL) throws {
		let name = sourceURL.lastPathComponent
		do {
			let data = try Data(contentsOf: sourceURL)
			try add(name: name, data: data)
		} catch {
			guard sourceURL.startAccessingSecurityScopedResource() else {
				throw error
			}
			defer {
				sourceURL.stopAccessingSecurityScopedResource()
			}
			let data = try Data(contentsOf: sourceURL)
			try add(name: name, data: data)
		}
	}

	func move(from: Int, to: Int) {
		let item = list.remove(at: from)
		list.insert(item, at: to)
		savePrefs()
	}
}
