//
//  QuestList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/23/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit

protocol QuestProtocol {
	var name: String { get }
	var title: String { get }
	var tagKey: String { get }
	var icon: UIImage? { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
}

class QuestHighwaySurface: QuestProtocol {
	var name: String { "QuestHighwaySurface" }
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
	let name: String
	let title: String
	let tagKey: String
	let icon: UIImage?
	func appliesTo(_ object: OsmBaseObject) -> Bool {
		return filter(object)
	}

	private let filter: QuestElementFilter
	init(name: String, title: String, tagKey: String, icon: UIImage?, filter: @escaping QuestElementFilter) {
		self.name = name
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
		let jsonPath = Bundle.main.path(forResource: "Quests", ofType: "json")!
		let jsonData = try! NSData(contentsOfFile: jsonPath) as Data
		let json = try! JSONSerialization.jsonObject(with: jsonData, options: [])
		let topDict = json as! [String: [String: Any]]
		var list: [QuestProtocol] = []

		let iconPath = "quest_icons/"
		for (name, dict) in topDict {
			if let titleKey = dict["title"] as? String,
			   let icon = dict["icon"] as? String,
			   let filter = dict["filter"] as? String,
			   let wiki = dict["wiki"] as? String,
			   let iconPath = Bundle.main.path(forResource: iconPath + icon, ofType: "png"),
			   let icon2 = UIImage(contentsOfFile: iconPath)
			{
				// deduce the tag key
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

				// convert title key to localized string
				let title = Bundle.main.localizedString(forKey: titleKey, value: nil, table: "quest")

				let filterParser = QuestFilterParser(filter)
				do {
					let filter2 = try filterParser.parseFilter()
					let quest = QuestDefinition(name: name,
					                            title: title,
					                            tagKey: tagKey!,
					                            icon: icon2,
					                            filter: filter2)
					list.append(quest)
				} catch {
					print("Filter parse error in \(name):")
					print("Filter = \"\(filter)\"")
					print("Error = \(error)")
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
