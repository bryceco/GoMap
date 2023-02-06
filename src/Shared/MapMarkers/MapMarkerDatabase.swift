//
//  MapMarkerDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation

final class MapMarkerDatabase {
	private let workQueue = OperationQueue()
	private var markerForButtonId: [Int: MapMarker] = [:] // return the marker with the given button tag (tagId)
	private var buttonIdForMarkerIdentifier: [String: Int] = [:] // map the marker key (unique string) to a tag
	weak var mapData: OsmMapData!

	init() {
		workQueue.maxConcurrentOperationCount = 1
	}

	var allMapMarkers: AnySequence<MapMarker> { AnySequence(markerForButtonId.values) }

	func removeAll() {
		workQueue.cancelAllOperations()
		markerForButtonId.removeAll()
		buttonIdForMarkerIdentifier.removeAll()
	}

	/// This is called when we get a new marker. If it is an update to an existing marker then
	/// we need to delete the reference to the previous tag, so the button can be replaced.
	func addOrUpdate(marker newMarker: MapMarker) {
		if let buttonId = buttonIdForMarkerIdentifier[newMarker.markerIdentifier] {
			// remove any existing tag with the same markerIdentifier
			markerForButtonId.removeValue(forKey: buttonId)
		}
		buttonIdForMarkerIdentifier[newMarker.markerIdentifier] = newMarker.buttonId
		markerForButtonId[newMarker.buttonId] = newMarker
	}

	func updateNoteMarkers(forRegion box: OSMRect, completion: @escaping () -> Void) {
		let url = OSM_API_URL +
			"api/0.6/notes?closed=0&bbox=\(box.origin.x),\(box.origin.y),\(box.origin.x + box.size.width),\(box.origin.y + box.size.height)"
		if let url1 = URL(string: url) {
			URLSession.shared.data(with: url1, completionHandler: { [self] result in
				guard case let .success(data) = result,
				      let xmlText = String(data: data, encoding: .utf8),
				      let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0)
				else { return }

				var newNotes: [OsmNoteMarker] = []
				for noteElement in (try? xmlDoc.rootElement()?.nodes(forXPath: "./note")) ?? [] {
					guard let noteElement = noteElement as? DDXMLElement else {
						continue
					}
					if let note = OsmNoteMarker(noteXml: noteElement) {
						newNotes.append(note)
					}
				}

				DispatchQueue.main.async(execute: { [self] in
					// add downloaded notes
					for note in newNotes {
						addOrUpdate(marker: note)
					}

					completion()
				})
			})
		}
	}

	// add from FIXME=yes tags
	func updateFixmeMarkers(forRegion box: OSMRect, mapData: OsmMapData) {
		mapData.enumerateObjects(inRegion: box, block: { [self] obj in
			if let fixme = FixmeMarker.fixmeTag(obj) {
				let marker = FixmeMarker(object: obj, text: fixme)
				self.addOrUpdate(marker: marker)
			}
		})
	}

	func updateQuestMarkers(forRegion box: OSMRect, mapData: OsmMapData) {
		mapData.enumerateObjects(inRegion: box, block: { obj in
			for quest in QuestList.shared.questsForObject(obj) {
				let marker = QuestMarker(object: obj, quest: quest)
				self.addOrUpdate(marker: marker)
			}
		})
	}

	func updateGpxWaypoints() {
		DispatchQueue.main.async(execute: { [self] in
			for track in AppDelegate.shared.mapView.gpxLayer.allTracks() {
				for point in track.wayPoints {
					let note = WayPointMarker(with: point.latLon, description: point.name)
					addOrUpdate(marker: note)
				}
			}
		})
	}

	func updateKeepRight(forRegion box: OSMRect, mapData: OsmMapData, completion: @escaping () -> Void) {
		let template =
			"https://keepright.at/export.php?format=gpx&ch=0,30,40,70,90,100,110,120,130,150,160,180,191,192,193,194,195,196,197,198,201,202,203,204,205,206,207,208,210,220,231,232,270,281,282,283,284,285,291,292,293,294,295,296,297,298,311,312,313,320,350,370,380,401,402,411,412,413&left=%f&bottom=%f&right=%f&top=%f"
		let url = String(
			format: template,
			box.origin.x,
			box.origin.y,
			box.origin.x + box.size.width,
			box.origin.y + box.size.height)
		guard let url1 = URL(string: url) else { return }
		URLSession.shared.data(with: url1, completionHandler: { [self] result in
			if case let .success(data) = result,
			   let gpxTrack = try? GpxTrack(xmlData: data)
			{
				DispatchQueue.main.async(execute: { [self] in
					for point in gpxTrack.wayPoints {
						if let note = KeepRightMarker(gpxWaypoint: point, mapData: mapData) {
							addOrUpdate(marker: note)
						}
					}
					completion()
				})
			}
		})
	}

	struct MapMarkerSet: OptionSet {
		let rawValue: Int
		static let notes = MapMarkerSet(rawValue: 1 << 0)
		static let fixme = MapMarkerSet(rawValue: 1 << 1)
		static let quest = MapMarkerSet(rawValue: 1 << 2)
		static let gpx = MapMarkerSet(rawValue: 1 << 3)
	}

	func updateMarkers(
		forRegion box: OSMRect,
		mapData: OsmMapData,
		including: MapMarkerSet,
		completion: @escaping () -> Void)
	{
		if including.contains(.fixme) {
			updateFixmeMarkers(forRegion: box, mapData: mapData)
		}
		if including.contains(.quest) {
			updateQuestMarkers(forRegion: box, mapData: mapData)
		}
		if including.contains(.gpx) {
			updateGpxWaypoints()
		}
		if including.contains(.notes) {
			updateNoteMarkers(forRegion: box, completion: completion)
		} else {
			completion()
		}
	}

	func updateRegion(
		_ bbox: OSMRect,
		withDelay delay: CGFloat,
		mapData: OsmMapData,
		including: MapMarkerSet,
		completion: @escaping () -> Void)
	{
		// Schedule work to be done in a short while, but if we're called before then
		// cancel that operation and schedule a new one.
		workQueue.cancelAllOperations()
		workQueue.addOperation({
			usleep(UInt32(1000 * (delay + 0.25)))
		})
		workQueue.addOperation({ [self] in
			DispatchQueue.main.async {
				self.updateMarkers(forRegion: bbox, mapData: mapData, including: including, completion: completion)
			}
		})
	}

	func update(
		note: OsmNoteMarker,
		close: Bool,
		comment: String,
		completion: @escaping (Result<OsmNoteMarker, Error>) -> Void)
	{
		var allowedChars = CharacterSet.urlQueryAllowed
		allowedChars.remove(charactersIn: "+;&")
		let comment = comment.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? ""

		var url = OSM_API_URL + "api/0.6/notes"

		if note.comments.count == 0 {
			// brand new note
			url += "?lat=\(note.lat)&lon=\(note.lon)&text=\(comment)"
		} else {
			// existing note
			if close {
				url += "/\(note.noteId)/close?text=\(comment)"
			} else {
				url += "/\(note.noteId)/comment?text=\(comment)"
			}
		}

		mapData.putRequest(url: url, method: "POST", xml: nil, completion: { [self] result in
			if case let .success(postData) = result,
			   let xmlText = String(data: postData, encoding: .utf8),
			   let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0),
			   let list = try? xmlDoc.rootElement()?.nodes(forXPath: "./note") as? [DDXMLElement],
			   let noteElement = list.first,
			   let newNote = OsmNoteMarker(noteXml: noteElement)
			{
				addOrUpdate(marker: newNote)
				completion(.success(newNote))
			} else {
				if case let .failure(error) = result {
					completion(.failure(error))
				} else {
					completion(.failure(NSError(domain: "OsmNotesDatabase",
					                            code: 1,
					                            userInfo: [NSLocalizedDescriptionKey: "Update Error"])))
				}
			}
		})
	}

	func mapMarker(forTag tag: Int) -> MapMarker? {
		return markerForButtonId[tag]
	}
}
