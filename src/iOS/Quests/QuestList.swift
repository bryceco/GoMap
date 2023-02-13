//
//  QuestList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

class QuestList {
	static let shared = QuestList()

	private(set) var list: [QuestProtocol]
	private(set) var userQuests: [QuestUserDefition] = []
	private var enabled: [String: Bool] = [:]

	init() {
		do {
			let addBuildingType = QuestDefinition(
				ident: "BuildingType",
				title: "Add Building Type",
				icon: UIImage(named: "ic_quest_building")!,
				presetKey: "building",
				appliesToObject: { obj in
					obj.tags["building"] == "yes"
				},
				acceptsValue: { _ in true })

			let addSidewalkSurface = try QuestDefinition(
				ident: "SidewalkSurface",
				title: "Add Sidewalk Surface",
				icon: UIImage(named: "ic_quest_sidewalk")!,
				presetKey: "surface",
				includeFeatures: ["highway/footway/sidewalk"],
				excludeFeatures: [])

			let addPhoneNumber = try QuestDefinition(
				ident: "TelephoneNumber",
				title: "Add Telephone Number",
				icon: UIImage(named: "ic_quest_check_shop")!,
				presetKey: "phone",
				includeFeatures: [],
				excludeFeatures: [],
				accepts: { text in
					text.unicodeScalars.compactMap { CharacterSet.decimalDigits.contains($0) ? true : nil }.count > 5
				})

			let addOpeningHours = try QuestDefinition(
				ident: "OpeningHours",
				title: "Add Opening Hours",
				icon: UIImage(named: "ic_quest_check_shop")!,
				presetKey: "opening_hours",
				includeFeatures: [String](),
				excludeFeatures: [])

			list = [
				addBuildingType,
				addSidewalkSurface,
				addPhoneNumber,
				addOpeningHours
			]
		} catch {
			print("Quest initialization error: \(error)")
			list = []
		}
		loadPrefs()
		list += userQuests.compactMap { try? QuestDefinition(userQuest: $0) }
	}

	func loadPrefs() {
		enabled = UserDefaults.standard.object(forKey: "QuestTypeEnabledDict") as? [String: Bool] ?? [:]
		if let data = UserDefaults.standard.object(forKey: "QuestUserDefinedList") as! Data? {
			userQuests = try! JSONDecoder().decode([QuestUserDefition].self, from: data)
		}
	}

	func savePrefs() {
		UserDefaults.standard.set(enabled, forKey: "QuestTypeEnabledDict")
		let encoded = try! JSONEncoder().encode(userQuests)
		UserDefaults.standard.set(encoded, forKey: "QuestUserDefinedList")
	}

	func addQuest(_ quest: QuestUserDefition) throws {
		let questDef = try QuestDefinition(userQuest: quest)
		userQuests.append(quest)
		userQuests.sort(by: { a, b in a.title < b.title })
		list.append(questDef)
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
		return userQuests.contains(where: { $0.title == quest.title })
	}
}
