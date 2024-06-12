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
		if let list = try? decoder.decode([QuestDefinitionWithFeatures].self, from: data) {
			self.list = list
			return
		}

		// FIXME: Silly to make a temporary version of the object then copy it
		let listCopy = try decoder.decode(QuestUserList.self, from: data)
		list = listCopy.list
	}

	convenience init(fromUserPrefsWith pref: Pref<Data>) {
		do {
			if let data = pref.value {
				try self.init(fromJsonData: data)
				return
			}
		} catch {}
		self.init()
	}

	static func userQuests(fromJsonData data: Data) throws -> [QuestDefinition]  {
		let decoder = JSONDecoder()

		// First try the old-fashioned way we did it
		if let list = try? decoder.decode([QuestDefinitionWithFeatures].self, from: data) {
			return list
		}

		// try importing as a single quest rather than a list
		if let quest = try? decoder.decode(QuestDefinitionWithFeatures.self, from: data) {
			return [quest]
		}
		if let quest = try? decoder.decode(QuestDefinitionWithFilters.self, from: data) {
			return [quest]
		}

		// import as a dictionary containing both feature and filter quest arrays
		return try decoder.decode(QuestUserList.self, from: data).list
	}

	func save(toUserPrefsWith pref: Pref<Data>) {
		let data = asJsonData()
		pref.value = data
	}

	func asJsonData() -> Data {
		return try! JSONEncoder().encode(self)
	}

	func asJsonString() -> String {
		return String(decoding: asJsonData(), as: UTF8.self)
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case featureQuestList
		case filterQuestList
	}

	init(from decoder: Decoder) throws {
		do {
			let values = try decoder.container(keyedBy: CodingKeys.self)
			let simple = try values.decode([QuestDefinitionWithFeatures].self, forKey: .featureQuestList)
			let advanced = try values.decode([QuestDefinitionWithFilters].self, forKey: .filterQuestList)
			list = simple + advanced
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		let simple = list.compactMap { $0 as? QuestDefinitionWithFeatures }
		let advanced = list.compactMap { $0 as? QuestDefinitionWithFilters }
		try container.encode(simple, forKey: .featureQuestList)
		try container.encode(advanced, forKey: .filterQuestList)
	}
}

class ResurveyQuest: QuestInstance {
	init(ageInYears: Double) {
		let ageInSeconds = ageInYears * 365.25 * 24 * 60 * 60
		let age = Date().addingTimeInterval(-ageInSeconds)
		let dateString = OsmBaseObject.rfc3339DateFormatter().string(from: age)

		guard let shopPredicate = try? QuestList.predicateForKey("phone", more: true)
		else {
			fatalError()
		}

		let predicate: (OsmBaseObject) -> Bool = { obj in
			if obj.timestamp >= dateString || obj.isModified() {
				return false
			}
			return shopPredicate(obj.tags)
		}

		super.init(ident: "__needsSurvey",
		           title: NSLocalizedString("Needs Survey", comment: "Quest for objects that aren't recently updated"),
		           label: "ic_quest_check",
		           editKeys: ["check_date", "name", "phone", "opening_hours"],
		           appliesToObject: predicate,
		           acceptsValue: { _ in true })
	}
}

class QuestList {
	static let shared = QuestList()
	private let builtinList: [QuestProtocol]
	private(set) var userQuests: QuestUserList
	private(set) var list: [QuestProtocol]
	private var enabled: [String: Bool] = [:]

	static func predicateForKey(_ key: String, more: Bool) throws -> ([String: String]) -> Bool {
		let featureStrings = try QuestDefinitionWithFeatures.featuresContaining(presetKey: key,
		                                                                        more: more)
		let features = featureStrings.compactMap { PresetsDatabase.shared.stdFeatures[$0] }
		let predicate = QuestDefinitionWithFeatures.predicateFor(features: features)
		return predicate
	}

	init() {
		do {
			// Build a predicate that matches features with phone numbers, which
			// we can use as a proxy for shops and amenities.
			let phoneFeaturesPredicate = try Self.predicateForKey("phone", more: false)

			let addBuildingType = QuestInstance(
				ident: "__BuildingType",
				title: NSLocalizedString("Add Building Type", comment: "A type of quest"),
				label: "ic_quest_building",
				editKeys: ["building"],
				appliesToObject: { obj in
					obj.tags["building"] == "yes"
				},
				acceptsValue: { _ in true })

			let addSidewalkSurface = QuestInstance(
				ident: "__SidewalkSurface",
				title: NSLocalizedString("Add Sidewalk Surface", comment: "A type of quest"),
				label: "ic_quest_sidewalk",
				editKeys: ["surface"],
				appliesToObject: { obj in
					guard let way = obj as? OsmWay else { return false }
					switch way.tags["highway"] {
					case "footway",
					     "path",
					     "pedestrian":
						break
					default:
						return false
					}
					switch obj.tags["surface"] {
					case nil, "paved", "unpaved":
						break
					default:
						return false
					}
					return true
				},
				acceptsValue: { _ in true })

			let addHighwaySurface = QuestInstance(
				ident: "__HighwaySurface",
				title: NSLocalizedString("Add Highway Surface", comment: "A type of quest"),
				label: "ic_quest_way_surface",
				editKeys: ["surface"],
				appliesToObject: { obj in
					guard let way = obj as? OsmWay else { return false }
					switch way.tags["highway"] {
					case "primary",
					     "secondary",
					     "tertiary",
					     "unclassified",
					     "residential",
					     "living_street",
					     "service",
					     "track":
						break
					default:
						return false
					}
					switch obj.tags["surface"] {
					case nil, "paved", "unpaved":
						break
					default:
						return false
					}
					return true
				},
				acceptsValue: { _ in true })

			let addSpeedLimit = QuestInstance(
				ident: "__SpeedLimit",
				title: NSLocalizedString("Add Speed Limit", comment: "A type of quest"),
				label: "ic_quest_max_speed",
				editKeys: ["maxspeed"],
				appliesToObject: { obj in
					guard let way = obj as? OsmWay,
					      way.tags["maxspeed"] == nil else { return false }
					switch way.tags["highway"] {
					case "motorway",
					     "trunk",
					     "primary",
					     "secondary",
					     "tertiary",
					     "unclassified",
					     "residential",
					     "living_street":
						return true
					default:
						return false
					}
				},
				acceptsValue: {
					let scanner = Scanner(string: $0)
					return scanner.scanInt(nil) || scanner.scanString("none", into: nil)
				})

			let addPhoneNumber = QuestInstance(
				ident: "__TelephoneNumber",
				title: NSLocalizedString("Add Telephone Number", comment: "A type of quest"),
				label: "ic_quest_phone",
				editKeys: ["phone"],
				appliesToObject: { (obj: OsmBaseObject) in
					let tags = obj.tags
					return phoneFeaturesPredicate(tags) &&
						tags["phone"] == nil &&
						tags["contact:phone"] == nil
				},
				acceptsValue: { text in
					text.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }).count > 5
				})

			let addParkingLotType = QuestInstance(
				ident: "__ParkingLotTYpe",
				title: NSLocalizedString("Add Parking Type", comment: "A type of quest"),
				label: "ic_quest_parking",
				editKeys: ["parking"],
				appliesToObject: { obj in
					obj.tags["amenity"] == "parking" && obj.tags["parking"] == nil
				},
				acceptsValue: { _ in
					true
				})

			let websitePredicate = try Self.predicateForKey("website", more: false)
			let addWebsite = QuestInstance(
				ident: "__Website",
				title: NSLocalizedString("Add Website", comment: "A type of quest"),
				label: "🌐",
				editKeys: ["website"],
				appliesToObject: { (obj: OsmBaseObject) in
					let tags = obj.tags
					return websitePredicate(tags) &&
						tags["website"] == nil &&
						tags["contact:website"] == nil
				},
				acceptsValue: { text in
					URL(string: text) != nil
				})

			let addOpeningHours = try QuestDefinitionWithFeatures(
				ident: "__OpeningHours",
				title: NSLocalizedString("Add Opening Hours", comment: "A type of quest"),
				label: "ic_quest_opening_hours",
				tagKey: "opening_hours",
				includeFeatures: []).makeQuestInstance()

			builtinList = [
				addBuildingType,
				addSidewalkSurface,
				addHighwaySurface,
				addPhoneNumber,
				addOpeningHours,
				addSpeedLimit,
				addWebsite,
				addParkingLotType,
				ResurveyQuest(ageInYears: 2.0)
			]
			// we want all built-in idents to be easily recognized and not collide with user defined quests:
			assert(!builtinList.contains(where: { $0.ident.prefix(2) != "__" }))
		} catch {
			print("Quest initialization error: \(error)")
			builtinList = []
		}
		list = builtinList
		userQuests = QuestUserList()
		loadPrefs()
		list += userQuests.list.compactMap { try? $0.makeQuestInstance() }
		sortList()

		UserPrefs.shared.questUserDefinedList.onChangePerform { pref in
			self.userQuests = QuestUserList(fromUserPrefsWith: pref)
		}
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
		enabled = UserPrefs.shared.questTypeEnabledDict.value ?? [:]
		userQuests = QuestUserList(fromUserPrefsWith: UserPrefs.shared.questUserDefinedList)
	}

	func savePrefs() {
		UserPrefs.shared.questTypeEnabledDict.value = enabled
		userQuests.save(toUserPrefsWith: UserPrefs.shared.questUserDefinedList)
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
		enabled.removeValue(forKey: item.ident)
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
		return quest.ident.prefix(2) != "__"
	}

	// MARK: Import/export

	func importQuests(fromText text: String) throws {
		let data = Data(text.utf8)
		do {
			let list = try QuestUserList(fromJsonData: data)
			for quest in list.list {
				try addUserQuest(quest, replacing: nil)
			}
		} catch {
			print("\(error)")
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
