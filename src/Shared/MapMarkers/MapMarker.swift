//
//  MapMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

// A marker that is displayed above the map. This could be:
// * Quest
// * FIXME
// * Notes
// * GPX Waypoint
// * GeoJSON point
// * KeepRight

class MapMarker {
	private(set) var buttonId: Int // a unique value we assign to track marker buttons.
	let latLon: LatLon
	weak var object: OsmBaseObject?
	weak var ignorable: MapMarkerIgnoreListProtocol?
	var button: UIButton?

	// a unique identifier for a marker across multiple downloads
	var markerIdentifier: String {
		fatalError()
	}

	deinit {
		button?.removeFromSuperview()
	}

	func reuseButtonFrom(_ other: MapMarker) {
		button = other.button
		buttonId = other.buttonId
		other.button = nil // nullify it so it doesn't get removed on deinit
	}

	private static var nextButtonID = (1...).makeIterator()

	init(latLon: LatLon) {
		buttonId = Self.nextButtonID.next()!
		self.latLon = latLon
	}

	var buttonLabel: String { "?" }

	func makeButton() -> UIButton {
		let button: MapView.MapViewButton
		if self is QuestMarker {
			button = MapPinButton(withLabel: buttonLabel)
		} else {
			button = MapView.MapViewButton(type: .custom)
			button.layer.backgroundColor = UIColor.blue.cgColor
			button.layer.borderColor = UIColor.white.cgColor
			if buttonLabel.count > 1 {
				// icon button
				button.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
				button.layer.cornerRadius = button.bounds.width / 2
				button.setImage(UIImage(named: buttonLabel), for: .normal)
				button.layer.borderColor = UIColor.white.cgColor
				button.layer.borderWidth = 2.0
			} else {
				// text button
				button.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
				button.layer.cornerRadius = 5
				button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
				button.titleLabel?.textColor = UIColor.white
				button.titleLabel?.textAlignment = .center
				button.setTitle(buttonLabel, for: .normal)
			}
		}
		self.button = button
		return button
	}
}
