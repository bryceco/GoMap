//
//  MapMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class MapMarker {
	let buttonId: Int // a unique value we assign to track marker buttons.
	let lat: Double
	let lon: Double
	weak var object: OsmBaseObject?
	weak var ignorable: MapMarkerIgnoreListProtocol?

	var button: UIButton? {
		willSet {
			if newValue == nil,
			   let button = button
			{
				button.removeFromSuperview()
			}
		}
	}

	// a unique identifier for a marker across multiple downloads
	var markerIdentifier: String {
		fatalError()
	}

	deinit {
		button?.removeFromSuperview()
	}

	private static var nextButtonID = (1...).makeIterator()

	init(lat: Double,
	     lon: Double)
	{
		buttonId = Self.nextButtonID.next()!
		self.lat = lat
		self.lon = lon
	}

	var buttonLabel: MapMarkerButton.TextOrImage { .text("?") }

	func makeButton() -> UIButton {
		let button: MapView.MapViewButton
		if self is QuestMarker {
			button = MapMarkerButton(withLabel: buttonLabel)
		} else {
			button = MapView.MapViewButton(type: .custom)
			button.layer.backgroundColor = UIColor.blue.cgColor
			button.layer.borderColor = UIColor.white.cgColor
			switch buttonLabel {
			case let .image(icon):
				// icon button
				button.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
				button.layer.cornerRadius = button.bounds.width / 2
				button.setImage(icon, for: .normal)
				button.layer.borderColor = UIColor.white.cgColor
				button.layer.borderWidth = 2.0
			case let .text(text):
				// text button
				button.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
				button.layer.cornerRadius = 5
				button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
				button.titleLabel?.textColor = UIColor.white
				button.titleLabel?.textAlignment = .center
				button.setTitle(text, for: .normal)
			}
		}
		self.button = button
		return button
	}
}
