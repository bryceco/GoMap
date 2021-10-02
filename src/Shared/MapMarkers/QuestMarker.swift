//
//  Quest.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit

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
	override var buttonIcon: UIImage? { quest.icon }

	init(object: OsmBaseObject, quest: QuestProtocol) {
		let center = object.selectionPoint()
		self.object = object
		self.quest = quest
		noteId = object.extendedIdentifier
		super.init(lat: center.lat, lon: center.lon)
	}
}
