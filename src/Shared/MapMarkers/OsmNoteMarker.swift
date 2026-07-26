//
//  OsmNoteMarker.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

// A regular OSM note displayed as a map marker
final class OsmNoteMarker: MapMarker {
	private(set) var note: OsmNote

	var noteId: Int64 { note.noteId }
	var status: String { note.status }
	var dateCreated: String { note.dateCreated }
	var comments: [OsmNote.Comment] { note.comments }

	override var markerIdentifier: String { "note-\(noteId)" }
	override var buttonLabel: String { "N" }

	func shouldHide() -> Bool { status == "closed" }

	/// A note newly created by the user (not yet saved to server)
	override init(latLon: LatLon) {
		note = OsmNote(latLon: latLon)
		super.init(latLon: latLon)
	}

	/// Initialize from a downloaded OsmNote
	init(note: OsmNote) {
		self.note = note
		super.init(latLon: note.latLon)
	}

	override func handleButtonPress(in mainView: MainViewController, markerView: MapMarkersView) {
		mainView.performSegue(withIdentifier: "NotesSegue", sender: self)
	}
}
