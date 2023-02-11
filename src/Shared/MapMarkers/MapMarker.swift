//
//  MapMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit

class MapMarker {
	let buttonId: Int // a unique value we assign to track marker buttons.
	let lat: Double
	let lon: Double
	weak var object: OsmBaseObject?
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

	func shouldHide() -> Bool {
		return false
	}

	var buttonLabel: String { fatalError() }
	var buttonIcon: UIImage? { nil }

	func makeButton() -> UIButton {
		let button: MapView.MapViewButton
		if self is QuestMarker {
			button = MapMarkerButton(withIcon: buttonIcon!)
		} else {
			button = MapView.MapViewButton(type: .custom)
			button.layer.backgroundColor = UIColor.blue.cgColor
			button.layer.borderColor = UIColor.white.cgColor
			if let icon = buttonIcon {
				// icon button
				button.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
				button.layer.cornerRadius = button.bounds.width / 2
				button.setImage(icon, for: .normal)
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
