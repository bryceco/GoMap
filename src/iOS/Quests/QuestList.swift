//
//  QuestList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class QuestList {
	static let shared = QuestList()
	private let builtinList: [QuestProtocol]
	private(set) var list: [QuestProtocol]
	private(set) var userQuests: [QuestUserDefition] = []
	private var enabled: [String: Bool] = [:]

	init() {
		do {
			let addBuildingType = QuestDefinition(
				ident: "BuildingType",
				title: "Add Building Type",
				label: .image(UIImage(named: "ic_quest_building")!),
				presetKey: "building",
				appliesToObject: { obj in
					obj.tags["building"] == "yes"
				},
				acceptsValue: { _ in true })

			let addSidewalkSurface = try QuestDefinition(
				ident: "SidewalkSurface",
				title: "Add Sidewalk Surface",
				label: .image(UIImage(named: "ic_quest_sidewalk")!),
				presetKey: "surface",
				includeFeatures: ["highway/footway/sidewalk"],
				excludeFeatures: [])

			let addPhoneNumber = try QuestDefinition(
				ident: "TelephoneNumber",
				title: "Add Telephone Number",
				label: .image(UIImage(named: "ic_quest_phone")!),
				presetKey: "phone",
				includeFeatures: [],
				excludeFeatures: [],
				accepts: { text in
					text.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }).count > 5
				})

			let addOpeningHours = try QuestDefinition(
				ident: "OpeningHours",
				title: "Add Opening Hours",
				label: .image(UIImage(named: "ic_quest_opening_hours")!),
				presetKey: "opening_hours",
				includeFeatures: [String](),
				excludeFeatures: [])

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
		loadPrefs()
		list += userQuests.compactMap { try? QuestDefinition(userQuest: $0) }
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
		if let data = UserDefaults.standard.object(forKey: "QuestUserDefinedList") as! Data? {
			userQuests = (try? JSONDecoder().decode([QuestUserDefition].self, from: data)) ?? []
		}
	}

	func savePrefs() {
		UserDefaults.standard.set(enabled, forKey: "QuestTypeEnabledDict")
		let encoded = try! JSONEncoder().encode(userQuests)
		UserDefaults.standard.set(encoded, forKey: "QuestUserDefinedList")
	}

	func addUserQuest(_ quest: QuestUserDefition, replacing previous: QuestUserDefition?) throws {
		let questDef = try QuestDefinition(userQuest: quest)

		// If they renamed a quest then remove the old version
		if let previous = previous {
			userQuests.removeAll(where: { $0.title == previous.title })
			list.removeAll(where: { $0.title == previous.title })
		}

		// If they gave a new quest the same name as an existing quest then replace the other quest
		userQuests.removeAll(where: { $0.title == quest.title })
		list.removeAll(where: { $0.title == quest.title })

		userQuests.append(quest)
		list.append(questDef)

		userQuests.sort(by: { a, b in a.title < b.title })
		sortList()
		savePrefs()
	}

	func remove(at index: Int) {
		let item = list.remove(at: index)
		userQuests.removeAll(where: { $0.title == item.title })
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
			let decoder = JSONDecoder()
			let data = Data(text.utf8)
			let decoded = try decoder.decode([QuestUserDefition].self, from: data)
			for quest in decoded {
				try self.addUserQuest(quest, replacing: nil)
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
