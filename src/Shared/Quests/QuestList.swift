//
//  QuestList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/23/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit

protocol QuestProtocol {
	var title: String { get }
	var tagKey: String { get }
	var icon: UIImage? { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
}

class QuestHighwaySurface: QuestProtocol {
	var title: String { "Highway surface" }
	var tagKey: String { "surface" }
	var icon: UIImage? { nil }

	func appliesTo(_ object: OsmBaseObject) -> Bool {
		if let way = object as? OsmWay,
		   way.tags["highway"] != nil,
		   way.tags["surface"] == nil
		{
			return true
		}
		return false
	}
}

class QuestDefinition: QuestProtocol {
	let title: String
	let tagKey: String
	let icon: UIImage?
	func appliesTo(_ object: OsmBaseObject) -> Bool {
		print("filter \(title)")
		return filter(object)
	}

	private let filter: QuestElementFilter
	init(title: String, tagKey: String, icon: UIImage?, filter: @escaping QuestElementFilter) {
		self.title = title
		self.tagKey = tagKey
		self.icon = icon
		self.filter = filter
	}
}

class QuestList {
	static let shared = QuestList()

	let list: [QuestProtocol]

	init() {
		let path = Bundle.main.path(forResource: "Quests", ofType: "json")!
		let data = try! NSData(contentsOfFile: path) as Data
		let json = try! JSONSerialization.jsonObject(with: data, options: [])
		let topDict = json as! [String: [String: Any]]
		var list: [QuestProtocol] = []
		for (name, dict) in topDict {
			if let desc = dict["description"] as? String,
			   let icon = dict["icon"] as? String,
			   let filter = dict["filter"] as? String,
			   let wiki = dict["wiki"] as? String,
			   let icon2 = UIImage(named: icon + ".png")
			{
				var tagKey = dict["key"] as? String
				if tagKey == nil {
					// try wiki
					if wiki.hasPrefix("Tag:") {
						// "Tag:emergency=fire_hydrant"
						var key = String(wiki.dropFirst(4))
						if let range = key.range(of: "=") {
							key = String(key[..<range.lowerBound])
						}
						tagKey = key
					} else if wiki.hasPrefix("Key:") {
						// "Key:leaf_type"
						tagKey = String(wiki.dropFirst(4))
					} else {
						print("Quest missing key: \(name)")
						continue
					}
				}

				let filterParser = QuestFilterParser(filter)
				do {
					let filter2 = try filterParser.parseFilter()
					let quest = QuestDefinition(title: desc,
					                            tagKey: tagKey!,
					                            icon: icon2,
					                            filter: filter2)
					list.append(quest)
				} catch {
					print("Filter parse error: \(error)")
				}
			} else {
				print("Bad quest entry: \(name)")
			}
		}
		self.list = list
	}

	func questsForObject(_ object: OsmBaseObject) -> [QuestProtocol] {
		return list.compactMap({ $0.appliesTo(object) ? $0 : nil })
	}
}
