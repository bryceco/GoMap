//
//  Quest.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

protocol QuestProtocol {
	var title: String { get }
	var tagKey: String { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
}

class QuestHighwaySurface: QuestProtocol {
	var title: String { "Highway surface" }
	var tagKey: String { "surface" }
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

enum QuestList {
	static let list: [QuestProtocol] = [
		QuestHighwaySurface()
	]
	static func QuestsForObject(_ object: OsmBaseObject) -> [QuestProtocol] {
		return list.compactMap({ $0.appliesTo(object) ? $0 : nil })
	}
}

// An OSM object for a quest
class QuestMarker: MapMarker {
	let noteId: OsmExtendedIdentifier
	let quest: QuestProtocol
	weak var object: OsmBaseObject?

	override var key: String {
		return "quest-\(noteId)"
	}

	override func shouldHide() -> Bool {
		guard let object = object else { return true }
		return !quest.appliesTo(object)
	}

	override var buttonLabel: String { "Q" }

	init(object: OsmBaseObject, quest: QuestProtocol) {
		let center = object.selectionPoint()
		let comment = OsmNoteComment(date: object.timestamp,
		                             action: "quest",
		                             text: quest.title,
		                             user: object.user)
		self.object = object
		self.quest = quest
		noteId = object.extendedIdentifier
		super.init(lat: center.lat,
		           lon: center.lon,
		           dateCreated: object.timestamp,
		           comments: [comment])
	}
}
