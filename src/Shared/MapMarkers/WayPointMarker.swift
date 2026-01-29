//
//  WayPointMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

// A GPX waypoint
final class WayPointMarker: MapMarker {
	let description: NSAttributedString

	init(with latLon: LatLon, description: NSAttributedString) {
		self.description = description
		super.init(latLon: latLon)
	}

	static func attributedString(for string: String) -> NSAttributedString {
		if let data = string.data(using: .utf8),
		   let attr = try? NSAttributedString(data: data,
		                                      options: [.documentType: NSAttributedString.DocumentType.html,
		                                                .characterEncoding: String.Encoding.utf8.rawValue],
		                                      documentAttributes: nil)
		{
			return attr
		} else {
			return NSAttributedString(string: string)
		}
	}

	convenience init(with gpxPoint: GpxPoint) {
		let name = Self.attributedString(for: gpxPoint.name)
		let desc = Self.attributedString(for: gpxPoint.desc)
		let message = [name, desc].compactMap { $0.string == "" ? nil : $0 }.joined(by: "\n\n")
		self.init(with: gpxPoint.latLon, description: message)
	}

	override var markerIdentifier: String {
		return "waypoint-\(latLon.lat),\(latLon.lon)"
	}

	override var buttonLabel: String { "W" }

	override func handleButtonPress(in mainView: MainViewController, markerView: MapMarkersView) {
		let title = "Waypoint"
		let alert = AlertPopup(title: title, message: self.description)
		mainView.present(alert, animated: true)
	}
}
