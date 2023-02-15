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
final class QuestMarker: MapMarker {
	let ident: String
	let quest: QuestProtocol

	override var markerIdentifier: String {
		return ident
	}

	override var buttonLabel: MapMarkerButton.TextOrImage { quest.label }

	init?(object: OsmBaseObject, quest: QuestProtocol, ignorable: MapMarkerIgnoreListProtocol) {
		let ident = "quest-\(quest.ident)-\(object is OsmNode ? "n" : object is OsmWay ? "w" : "r")\(object.ident)"
		if ignorable.shouldIgnore(ident: ident) {
			return nil
		}
		let center = object.selectionPoint()
		self.quest = quest
		self.ident = ident
		super.init(lat: center.lat, lon: center.lon)
		self.object = object
		self.ignorable = ignorable
	}
}
