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

	let list: [QuestProtocol]
	var enabled: [String: Bool]

	init() {
		do {
			let addBuildingType = QuestDefinition(
				ident: "BuildingType",
				title: "Add Building Type",
				icon: UIImage(named: "ic_quest_building")!,
				presetField: PresetField(withJson: [
					"key": "building",
					"type": "combo"
				])!,
				appliesToGeometry: [.AREA, .NODE],
				appliesToObject: { obj in
					obj.tags["building"] == "yes"
				},
				acceptsValue: { _ in true })

			let addSidewalkSurface = try QuestDefinition(
				ident: "SidewalkSurface",
				title: "Add Sidewalk Surface",
				icon: UIImage(named: "ic_quest_sidewalk")!,
				presetField: "surface",
				appliesToGeometry: [.LINE],
				includeFeatures: ["highway/footway/sidewalk"],
				excludeFeatures: [])

			let addPhoneNumber = try QuestDefinition(
				ident: "TelephoneNumber",
				title: "Add Telephone Number",
				icon: UIImage(named: "ic_quest_check_shop")!,
				presetField: "phone",
				appliesToGeometry: [.NODE, .AREA],
				includeFeatures: [],
				excludeFeatures: [],
				accepts: { text in
					text.unicodeScalars.compactMap { CharacterSet.decimalDigits.contains($0) ? true : nil }.count > 5
				})
			let addOpeningHours = try QuestDefinition(
				ident: "OpeningHours",
				title: "Add Opening Hours",
				icon: UIImage(named: "ic_quest_check_shop")!,
				presetField: "opening_hours",
				appliesToGeometry: [.NODE, .AREA],
				includeFeatures: [],
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
		enabled = Self.loadPrefs()
	}

	static func loadPrefs() -> [String: Bool] {
		let prefs = UserDefaults.standard.object(forKey: "QuestTypeEnabledDict")
		return prefs as? [String: Bool] ?? [:]
	}

	func savePrefs() {
		UserDefaults.standard.set(enabled, forKey: "QuestTypeEnabledDict")
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
}
