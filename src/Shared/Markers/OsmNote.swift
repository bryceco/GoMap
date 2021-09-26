//
//  OsmNote.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

// A regular OSM note
class OsmNote: MapMarker {
	let status: String // open, closed, etc.
	let noteId: Int64

	override var key: String {
		return "note-\(noteId)"
	}

	override func shouldHide() -> Bool {
		return status == "closed"
	}

	override var buttonLabel: String { "N" }

	/// A note newly created by user
	init(lat: Double, lon: Double) {
		noteId = 0
		status = ""
		super.init(lat: lat,
		           lon: lon,
		           dateCreated: "",
		           comments: [])
	}

	/// Initialize based on OSM Notes query
	init?(noteXml noteElement: DDXMLElement) {
		guard let lat2 = noteElement.attribute(forName: "lat")?.stringValue,
		      let lon2 = noteElement.attribute(forName: "lon")?.stringValue,
		      let lat = Double(lat2),
		      let lon = Double(lon2)
		else { return nil }

		var noteId: Int64?
		var dateCreated: String?
		var status: String?
		var comments: [OsmNoteComment] = []
		for child in noteElement.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			if child.name == "id" {
				if let string = child.stringValue,
				   let id = Int64(string)
				{
					noteId = id
				}
			} else if child.name == "date_created" {
				dateCreated = child.stringValue
			} else if child.name == "status" {
				status = child.stringValue
			} else if child.name == "comments" {
				guard let children = child.children as? [DDXMLElement] else { return nil }
				for commentElement in children {
					var date = ""
					var user = ""
					var action = ""
					var text = ""
					for child in commentElement.children ?? [] {
						guard let child = child as? DDXMLElement else {
							continue
						}
						if child.name == "date" {
							date = child.stringValue ?? ""
						} else if child.name == "user" {
							user = child.stringValue ?? ""
						} else if child.name == "action" {
							action = child.stringValue ?? ""
						} else if child.name == "text" {
							text = child.stringValue?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
						}
					}
					let comment = OsmNoteComment(date: date, action: action, text: text, user: user)
					comments.append(comment)
				}
			}
		}
		guard let noteId = noteId,
		      let dateCreated = dateCreated,
		      let status = status
		else { return nil }

		self.noteId = noteId
		self.status = status
		super.init(lat: lat,
		           lon: lon,
		           dateCreated: dateCreated,
		           comments: comments)
	}
}
