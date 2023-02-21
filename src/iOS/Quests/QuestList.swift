//
//  QuestList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

final class QuestUserList: Codable {
	var list: [QuestDefinition]

	// MARK: Initialize

	init() {
		list = []
	}

	convenience init(fromJsonData data: Data) throws {
		self.init()
		let decoder = JSONDecoder()
		// First try the old-fashioned way we did it
		if let list = try? decoder.decode([QuestDefinedWithPresetFeatures].self, from: data) {
			self.list = list
			return
		}
		// FIXME: Silly to make a temporary version of the object then copy it
		let listCopy = try decoder.decode(QuestUserList.self, from: data)
		list = listCopy.list
	}

	convenience init(fromUserDefaults defaults: UserDefaults, key: String) {
		do {
			if let data = defaults.object(forKey: key) as! Data? {
				try self.init(fromJsonData: data)
				return
			}
		} catch {}
		self.init()
	}

	func save(toUserDefaults defaults: UserDefaults, key: String) {
		let data = asJsonData()
		UserDefaults.standard.set(data, forKey: key)
	}

	func asJsonData() -> Data {
		return try! JSONEncoder().encode(self)
	}

	func asJsonString() -> String {
		return String(decoding: asJsonData(), as: UTF8.self)
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case simpleQuestList
		case advancedQuestList
	}

	init(from decoder: Decoder) throws {
		do {
			let values = try decoder.container(keyedBy: CodingKeys.self)
			let simple = try values.decode([QuestDefinedWithPresetFeatures].self, forKey: .simpleQuestList)
			let advanced = try values.decode([QuestDefinedFromFilters].self, forKey: .advancedQuestList)
			list = simple + advanced
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		let simple = list.compactMap { $0 as? QuestDefinedWithPresetFeatures }
		let advanced = list.compactMap { $0 as? QuestDefinedFromFilters }
		try container.encode(simple, forKey: .simpleQuestList)
		try container.encode(advanced, forKey: .advancedQuestList)
	}
}

class QuestList {
	static let shared = QuestList()
	private let builtinList: [QuestProtocol]
	private(set) var userQuests: QuestUserList
	private(set) var list: [QuestProtocol]
	private var enabled: [String: Bool] = [:]

	init() {
		do {
			let addBuildingType = QuestInstance(
				ident: "BuildingType",
				title: "Add Building Type",
				label: .image(UIImage(named: "ic_quest_building")!),
				presetKey: "building",
				appliesToObject: { obj in
					obj.tags["building"] == "yes"
				},
				acceptsValue: { _ in true })

			let addSidewalkSurface = try QuestInstanceWithFeatures(
				ident: "SidewalkSurface",
				title: "Add Sidewalk Surface",
				label: .image(UIImage(named: "ic_quest_sidewalk")!),
				presetKey: "surface",
				includeFeatures: ["highway/footway/sidewalk"])

			let addPhoneNumber = try QuestInstanceWithFeatures(
				ident: "TelephoneNumber",
				title: "Add Telephone Number",
				label: .image(UIImage(named: "ic_quest_phone")!),
				presetKey: "phone",
				includeFeatures: [],
				accepts: { text in
					text.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }).count > 5
				})

			let addOpeningHours = try QuestInstanceWithFeatures(
				ident: "OpeningHours",
				title: "Add Opening Hours",
				label: .image(UIImage(named: "ic_quest_opening_hours")!),
				presetKey: "opening_hours",
				includeFeatures: [String]())

			builtinList = [
				addBuildingType,
				addSidewalkSurface,
				addPhoneNumber,
				addOpeningHours
			]
		} catch {
			print("Quest initialization error: \(error)")
			builtinList = []
		}
		list = builtinList
		userQuests = QuestUserList()
		loadPrefs()
		list += userQuests.list.compactMap { try? $0.makeQuestInstance() }
		sortList()
	}

	func sortList() {
		list.sort(by: { a, b in
			let aUser = isUserQuest(a)
			let bUser = isUserQuest(b)
			if aUser != bUser {
				return bUser ? true : false
			}
			return a.title.compare(b.title, options: .caseInsensitive) == .orderedAscending
		})
	}

	func loadPrefs() {
		enabled = UserDefaults.standard.object(forKey: "QuestTypeEnabledDict") as? [String: Bool] ?? [:]
		userQuests = QuestUserList(fromUserDefaults: UserDefaults.standard, key: "QuestUserDefinedList")
	}

	func savePrefs() {
		UserDefaults.standard.set(enabled, forKey: "QuestTypeEnabledDict")
		userQuests.save(toUserDefaults: UserDefaults.standard, key: "QuestUserDefinedList")
	}

	func addUserQuest(_ quest: QuestDefinition,
	                  replacing previous: QuestDefinition?) throws
	{
		let questDef = try quest.makeQuestInstance()

		// If they renamed a quest then remove the old version
		if let previous = previous {
			userQuests.list.removeAll(where: { $0.title == previous.title })
			list.removeAll(where: { $0.title == previous.title })
		}

		// If they gave a new quest the same name as an existing quest then replace the other quest
		userQuests.list.removeAll(where: { $0.title == quest.title })
		list.removeAll(where: { $0.title == quest.title })

		userQuests.list.append(quest)
		list.append(questDef)

		userQuests.list.sort(by: { a, b in a.title < b.title })
		sortList()
		savePrefs()
	}

	func remove(at index: Int) {
		let item = list.remove(at: index)
		userQuests.list.removeAll(where: { $0.title == item.title })
		savePrefs()
	}

	func questsForObject(_ object: OsmBaseObject) -> [QuestProtocol] {
		return list.compactMap({ isEnabled($0) && $0.appliesTo(object) ? $0 : nil })
	}

	func setEnabled(_ quest: QuestProtocol, _ isEnabled: Bool) {
		enabled[quest.ident] = isEnabled
		savePrefs()
	}

	func isEnabled(_ quest: QuestProtocol) -> Bool {
		return enabled[quest.ident] ?? true
	}

	func isUserQuest(_ quest: QuestProtocol) -> Bool {
		return !builtinList.contains(where: { $0.ident == quest.ident })
	}

	// MARK: Import/export

	func importQuests(fromText text: String) throws {
		do {
			let data = Data(text.utf8)
			let list = try QuestUserList(fromJsonData: data)
			for quest in list.list {
				try addUserQuest(quest, replacing: nil)
			}
		} catch {
			throw error
		}
	}

	func exportQuests() throws -> String {
		do {
			let encoder = JSONEncoder()
			if #available(iOS 13.0, *) {
				encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
			} else {
				encoder.outputFormatting = [.prettyPrinted]
			}
			let data = try encoder.encode(QuestList.shared.userQuests)
			guard let text = String(data: data, encoding: .utf8) else {
				throw QuestError.noStringEquivalent
			}
			return text
		} catch {
			throw error
		}
	}
}
