//
//  FixmeMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// An OSM object containing a fixme= tag
final class FixmeMarker: MapMarker {
	/// Same light blue as relation member highlighting in EditorMapLayer.
	private static let relationMemberColor = UIColor(red: 66 / 255.0,
	                                                 green: 188 / 255.0,
	                                                 blue: 244 / 255.0,
	                                                 alpha: 1.0)
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

	override var buttonLabel: String { "F" }

	private var isRelationMember: Bool {
		guard let object = object else { return false }
		return !object.parentRelations.isEmpty
	}

	override func makeButton() -> UIButton {
		let button = super.makeButton()
		applyButtonStyle()
		return button
	}

	override func reuseButtonFrom(_ other: MapMarker) {
		super.reuseButtonFrom(other)
		applyButtonStyle()
	}

	private func applyButtonStyle() {
		guard let button = button else { return }
		let color = isRelationMember ? Self.relationMemberColor : .blue
		button.layer.backgroundColor = color.cgColor
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
