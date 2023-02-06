//
//  QuestMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/5/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import Foundation
import UIKit

// An OSM object for a quest
class QuestMarker: MapMarker {
	let objectId: OsmExtendedIdentifier
	let quest: QuestProtocol
	weak var object: OsmBaseObject?

	override var markerIdentifier: String {
		return "quest-\(objectId)"
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
		objectId = object.extendedIdentifier
		super.init(lat: center.lat, lon: center.lon)
	}
}
