//
//  FixmeMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

// An OSM object containing a fixme= tag
final class FixmeMarker: MapMarker {
	let fixmeID: OsmExtendedIdentifier

	override var markerIdentifier: String {
		return "fixme-\(fixmeID)"
	}

	/// If the object contains a fixme then returns the fixme value, else nil
	static func fixmeTag(_ object: OsmBaseObject) -> String? {
		guard let tag = object.tags.first(where: { OsmTags.isFixme($0.key) }) else {
			return nil
		}
		return tag.value
	}

	func shouldHide() -> Bool {
		guard let object = object else { return true }
		return FixmeMarker.fixmeTag(object) == nil
	}

	/// Initialize from FIXME data
	init(object: OsmBaseObject, text: String) {
		let center = object.selectionPoint()
		fixmeID = object.extendedIdentifier
		super.init(latLon: center)
		self.object = object
	}

	/// Same light blue as relation member highlighting in EditorMapLayer.
	private static let relationMemberColor = UIColor(red: 66 / 255.0,
	                                                 green: 188 / 255.0,
	                                                 blue: 244 / 255.0,
	                                                 alpha: 1.0)
	private var isRelationMember: Bool {
		guard let object else { return false }
		return (object is OsmRelation) || !object.parentRelations.isEmpty
	}

	override var buttonLabel: String { "F" }
	override var buttonColor: UIColor {
		if isRelationMember {
			return Self.relationMemberColor
		}
		return .blue
	}

	override func handleButtonPress(in mainView: MainViewController, markerView: MapMarkersView) {
		if mainView.mapView.isHidden {
			// show the fixme text
			guard let object = object else { return }
			let text = FixmeMarker.fixmeTag(object) ?? ""
			let alert = AlertPopup(title: "\(object.friendlyDescription())",
			                       message: text)
			alert.addAction(title: "OK", handler: nil)
			mainView.present(alert, animated: true)
		} else {
			// open tag editor
			mainView.mapView.presentTagEditor(nil)
		}
	}
}
