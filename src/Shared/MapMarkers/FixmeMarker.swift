//
//  Fixme.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

// An OSM object containing a fixme= tag
class FixmeMarker: MapMarker {
	let fixmeID: OsmExtendedIdentifier

	override var markerIdentifier: String {
		return "fixme-\(fixmeID)"
	}

	/// If the object contains a fixme then returns the fixme value, else nil
	static func fixmeTag(_ object: OsmBaseObject) -> String? {
		if let tag = object.tags.first(where: { $0.key.caseInsensitiveCompare("fixme") == .orderedSame }) {
			return tag.value
		}
		return nil
	}

	override func shouldHide() -> Bool {
		guard let object = object else { return true }
		return FixmeMarker.fixmeTag(object) == nil
	}

	override var buttonLabel: String { "F" }

	/// Initialize from FIXME data
	init(object: OsmBaseObject, text: String) {
		let center = object.selectionPoint()
		fixmeID = object.extendedIdentifier
		super.init(lat: center.lat,
		           lon: center.lon)
		self.object = object
	}
}
