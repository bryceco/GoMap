//
//  QuestList.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

protocol QuestProtocol {
	var ident: String { get }
	var title: String { get }
	var tagKey: String { get }
	var icon: UIImage? { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
	func accepts(tagValue: String) -> Bool
}

struct QuestHighwaySurface: QuestProtocol {
	var ident: String { "QuestHighwaySurface" }
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

	func accepts(tagValue: String) -> Bool {
		return !tagValue.isEmpty
	}
}

typealias QuestElementFilter = (OsmBaseObject) -> Bool

struct QuestDefinition: QuestProtocol {
	let ident: String // Uniquely identify the quest
	let title: String // This provides additional instructions on what action to take
	let tagKey: String // This is the key that is being updated
	let icon: UIImage?
	func appliesTo(_ object: OsmBaseObject) -> Bool {
		return filter(object)
	}

	func accepts(tagValue: String) -> Bool {
		return accepts(tagValue)
	}

	private let filter: QuestElementFilter
	private let accepts: (String) -> Bool

	init(ident: String, title: String, tagKey: String, icon: UIImage,
	     filter: @escaping QuestElementFilter,
	     accepts: ((String) -> Bool)? = nil)
	{
		self.ident = ident
		self.title = title
		self.tagKey = tagKey
		self.icon = icon
		self.filter = filter
		self.accepts = accepts ?? { _ in true }
	}
}

class QuestList {
	static let shared = QuestList()

	let list: [QuestProtocol]
	var enabled: [String: Bool]

	static let poiList = [
		("shop", "convenience"),
		("amenity", "atm"),
		("shop", "hairdresser"),
		("shop", "beauty"),
		("shop", "florist"),
		("amenity", "pharmacy"),
		("shop", "clothes"),
		("shop", "shoes"),
		("amenity", "toilets"),
		("shop", "bakery"),
		("amenity", "restaurant"),
		("amenity", "cafe"),
		("amenity", "fast_food"),
		("amenity", "bar"),
		("amenity", "fuel"),
		("amenity", "car_wash")
	]
	static func isShop(_ obj: OsmBaseObject) -> Bool {
		if [GEOMETRY.AREA, GEOMETRY.NODE].contains(obj.geometry()),
		   Self.poiList.contains(where: { obj.tags[$0.0] == $0.1 })
		{
			return true
		}
		return false
	}

	init() {
		let addBuildingType = QuestDefinition(
			ident: "BuildingType",
			title: "Add Building Type",
			tagKey: "building",
			icon: UIImage(named: "ic_quest_building")!,
			filter: {
				$0.tags["building"] == "yes"
			})

		let addSidewalkSurface = QuestDefinition(
			ident: "SidewalkSurface",
			title: "Add Sidewalk Surface",
			tagKey: "surface",
			icon: UIImage(named: "ic_quest_sidewalk")!,
			filter: {
				if let tags = ($0 as? OsmWay)?.tags,
				   tags["highway"] == "footway",
				   tags["footway"] == "sidewalk",
				   tags["surface"] == nil
				{
					return true
				}
				return false
			})

#if false
		let addAddressNumber = QuestDefinition(
			ident: "AddressNumber",
			title: "Add Address Number",
			tagKey: "addr:housenumber",
			icon: UIImage(named: "")!,
			filter: { Self.isShop($0) && $0.tags["addr:housenumber"] == nil })

		let addAddressStreet = QuestDefinition(
			ident: "AddressStreet",
			title: "Add Address Street",
			tagKey: "addr:street",
			icon: UIImage(named: "")!,
			filter: { Self.isShop($0) && $0.tags["addr:street"] == nil })
#endif

		let addPhoneNumber = QuestDefinition(
			ident: "TelephoneNumber",
			title: "Add Telephone Number",
			tagKey: "phone",
			icon: UIImage(named: "ic_quest_check_shop")!,
			filter: { Self.isShop($0) &&
				$0.tags["phone"] ==
				nil && $0.tags["contact:phone"] == nil
			},
			accepts: { text in
				// need at least some number of digits
				let okay = text
					.unicodeScalars
					.compactMap({ CharacterSet.decimalDigits.contains($0) ? true : nil })
					.count > 5
				return okay
			})

		list = [
			addBuildingType,
			addSidewalkSurface,
			addPhoneNumber
//			addressNumber,
//			addressStreet
		]
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
