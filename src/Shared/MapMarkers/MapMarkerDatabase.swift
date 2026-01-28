//
//  MapMarkerDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation

final class MapMarkerDatabase: MapMarkerIgnoreListProtocol {
	private var pendingUpdateTask: Task<Void, Never>?
	private var markerForIdentifier: [String: MapMarker] = [:] // map the marker key (unique string) to a marker
	private var ignoreList: MapMarkerIgnoreList
	weak var mapData: OsmMapData!

	init() {
		ignoreList = MapMarkerIgnoreList()
	}

	var allMapMarkers: AnySequence<MapMarker> { AnySequence(markerForIdentifier.values) }

	func removeAll() {
		pendingUpdateTask?.cancel()
		markerForIdentifier.removeAll()
	}

	func refreshMarkersFor(object: OsmBaseObject) -> [MapMarker] {
		// Remove all markers that reference the object
		let remove = markerForIdentifier.compactMap { k, v in v.object === object ? k : nil }
		for k in remove {
			markerForIdentifier.removeValue(forKey: k)
		}
		if object.deleted {
			return []
		}
		// Build a new list of markers that reference the object
		var list = [MapMarker]()
		if AppDelegate.shared.mainView.viewState.overlayMask.contains(.QUESTS) {
			for quest in QuestList.shared.questsForObject(object) {
				if let marker = QuestMarker(object: object, quest: quest, ignorable: self) {
					addOrUpdate(marker: marker)
					list.append(marker)
				}
			}
		}
		if AppDelegate.shared.mainView.viewState.overlayMask.contains(.NOTES) {
			if let fixme = FixmeMarker.fixmeTag(object) {
				let marker = FixmeMarker(object: object, text: fixme)
				addOrUpdate(marker: marker)
				list.append(marker)
			}
		}
		return list
	}

	// MARK: Ignorable

	func shouldIgnore(ident: String) -> Bool {
		return ignoreList.shouldIgnore(ident: ident)
	}

	func shouldIgnore(marker: MapMarker) -> Bool {
		return ignoreList.shouldIgnore(marker: marker)
	}

	func ignore(marker: MapMarker, reason: IgnoreReason) {
		markerForIdentifier.removeValue(forKey: marker.markerIdentifier)
		ignoreList.ignore(marker: marker, reason: reason)
	}

	/// This is called when we get a new marker.
	func addOrUpdate(marker newMarker: MapMarker) {
		if let oldMarker = markerForIdentifier[newMarker.markerIdentifier] {
			// This marker is already in our database, so reuse it's button
			newMarker.reuseButtonFrom(oldMarker)
		}
		markerForIdentifier[newMarker.markerIdentifier] = newMarker
	}

	// MARK: update markers

	struct MapMarkerSet: OptionSet {
		let rawValue: Int
		static let notes = MapMarkerSet(rawValue: 1 << 0)
		static let fixme = MapMarkerSet(rawValue: 1 << 1)
		static let quest = MapMarkerSet(rawValue: 1 << 2)
		static let gpx = MapMarkerSet(rawValue: 1 << 3)
		static let geojson = MapMarkerSet(rawValue: 1 << 4)
	}

	func removeMarkers(where predicate: (MapMarker) -> Bool) {
		let remove = markerForIdentifier.compactMap { key, marker in predicate(marker) ? key : nil }
		for key in remove {
			markerForIdentifier.removeValue(forKey: key)
		}
	}

	// External callers should use the "withDelay" variant of this
	private func updateMarkers(forRegion box: OSMRect,
	                           mapData: OsmMapData,
	                           including: MapMarkerSet,
	                           completion: @escaping () -> Void)
	{
		if including.contains(.fixme) {
			removeMarkers(where: { ($0 as? FixmeMarker)?.shouldHide() ?? false })
			updateFixmeMarkers(forRegion: box, mapData: mapData)
		} else {
			removeMarkers(where: { $0 is FixmeMarker })
		}
		if including.contains(.quest) {
			updateQuestMarkers(forRegion: box, mapData: mapData)
		} else {
			removeMarkers(where: { $0 is QuestMarker })
		}
		if including.contains(.gpx) {
			updateGpxWaypointMarkers()
		} else {
			removeMarkers(where: { $0 is WayPointMarker })
		}
		if including.contains(.geojson) {
			updateGeoJSONMarkers(forRegion: box)
		} else {
			removeMarkers(where: { $0 is GeoJsonMarker })
		}

		if including.contains(.notes) {
			removeMarkers(where: { ($0 as? OsmNoteMarker)?.shouldHide() ?? false })
			updateNoteMarkers(forRegion: box, completion: completion)
			return // don't call completion until async finishes
		} else {
			removeMarkers(where: { $0 is OsmNoteMarker })
		}
		completion()
	}

	func updateRegion(
		withDelay delay: TimeInterval,
		including: MapMarkerSet,
		completion: @escaping () -> Void)
	{
		// Schedule work to be done in a short while, but if we're called before then
		// cancel that operation and schedule a new one.
		pendingUpdateTask?.cancel()
		pendingUpdateTask = Task { @MainActor in
			// Suspend for delay (in nanoseconds)
			let delayNs = UInt64((delay + 0.25) * 1000_000000)
			try? await Task.sleep(nanoseconds: delayNs)

			guard
				// Check for cancellation before proceeding
				!Task.isCancelled
			else {
				return
			}
			// Don't update excessively large regions
			let bbox = AppDelegate.shared.mainView.viewPort.boundingLatLonForScreen()
			guard bbox.size.width * bbox.size.height <= 0.25 else { return }

			await MainActor.run {
				self.updateMarkers(forRegion: bbox, mapData: mapData, including: including, completion: completion)
			}
		}
	}

	func mapMarker(forButtonId buttonId: Int) -> MapMarker? {
		return markerForIdentifier.values.first(where: { $0.buttonId == buttonId })
	}

	// MARK: object selection

	func didSelectObject(_ object: OsmBaseObject?) {
		for marker in markerForIdentifier.values {
			if let button = marker.button {
				button.isHighlighted = object != nil && object == marker.object
			}
		}
	}
}

extension MapMarkerDatabase {

	// MARK: marker type-specific update functions

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
				if let marker = QuestMarker(object: obj, quest: quest, ignorable: self) {
					self.addOrUpdate(marker: marker)
				}
			}
		})
	}

	func updateGpxWaypointMarkers() {
		for track in AppState.shared.gpxTracks.allTracks() {
			for point in track.wayPoints {
				let marker = WayPointMarker(with: point)
				addOrUpdate(marker: marker)
			}
		}
	}

	func updateGeoJSONMarkers(forRegion box: OSMRect) {
		let visible = AppDelegate.shared.mainView.mapLayersView.dataOverlayLayer.geojsonData()
		for feature in visible {
			if case let .point(latLon) = feature.geom.geometryPoints,
			   box.containsPoint(OSMPoint(latLon)),
			   let properties = feature.properties
			{
				let marker = GeoJsonMarker(with: latLon, properties: properties)
				addOrUpdate(marker: marker)
			}
		}
	}

	func updateKeepRightMarkers(forRegion box: OSMRect, mapData: OsmMapData, completion: @escaping () -> Void) {
		let template =
			"https://keepright.at/export.php?format=gpx&ch=0,30,40,70,90,100,110,120,130,150,160,180,191,192,193,194,195,196,197,198,201,202,203,204,205,206,207,208,210,220,231,232,270,281,282,283,284,285,291,292,293,294,295,296,297,298,311,312,313,320,350,370,380,401,402,411,412,413&left=%f&bottom=%f&right=%f&top=%f"
		let url = String(
			format: template,
			box.origin.x,
			box.origin.y,
			box.origin.x + box.size.width,
			box.origin.y + box.size.height)
		guard let url1 = URL(string: url) else { return }
		Task {
			if let data = try? await URLSession.shared.data(with: url1),
			   let gpxTrack = try? GpxTrack(xmlData: data)
			{
				await MainActor.run {
					for point in gpxTrack.wayPoints {
						if let note = KeepRightMarker(gpxWaypoint: point, mapData: mapData, ignorable: self) {
							addOrUpdate(marker: note)
						}
					}
					completion()
				}
			}
		}
	}

	func updateNoteMarkers(forRegion box: OSMRect, completion: @escaping () -> Void) {
		Task {
			let bbox = "\(box.origin.x),\(box.origin.y),\(box.origin.x + box.size.width),\(box.origin.y + box.size.height)"
			let url = OSM_SERVER.apiURL.appendingPathComponent("api/0.6/notes")
				.appendingQueryItems(["closed": "0",
				                      "bbox": "\(bbox)"])
			guard
				let data = try? await URLSession.shared.data(with: url),
				let xmlText = String(data: data, encoding: .utf8),
				let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0)
			else {
				return
			}

			let notes = (try? xmlDoc.rootElement()?.nodes(forXPath: "./note")) ?? []
			let newNotes: [OsmNoteMarker] = notes.compactMap({ noteElement in
				guard let noteElement = noteElement as? DDXMLElement,
				      let note = OsmNoteMarker(noteXml: noteElement)
				else {
					return nil
				}
				return note
			})
			await MainActor.run {
				// add downloaded notes
				for note in newNotes {
					addOrUpdate(marker: note)
				}
				completion()
			}
		}
	}

	func upload(note: OsmNoteMarker,
	            close: Bool,
	            comment: String) async throws -> OsmNoteMarker
	{
		var url = URL(string: "api/0.6/notes")!
		let queryItems: [String: String]

		if note.comments.count == 0 {
			// brand new note
			queryItems = ["lat": "\(note.latLon.lat)",
			              "lon": "\(note.latLon.lon)",
			              "text": comment]
		} else {
			// existing note
			if close {
				url = url.appendingPathComponent("\(note.noteId)/close")
				queryItems = ["text": comment]
			} else {
				url = url.appendingPathComponent("\(note.noteId)/comment")
				queryItems = ["text": comment]
			}
		}

		let postData = try await OSM_SERVER.putRequest(relativeUrl: url.relativePath,
		                                               queryItems: queryItems,
		                                               method: "POST",
		                                               xml: nil)
		guard let xmlText = String(data: postData, encoding: .utf8),
		      let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0),
		      let list = try? xmlDoc.rootElement()?.nodes(forXPath: "./note") as? [DDXMLElement],
		      let noteElement = list.first,
		      let newNote = OsmNoteMarker(noteXml: noteElement)
		else {
			throw NSError(domain: "OsmNotesDatabase",
			              code: 1,
			              userInfo: [NSLocalizedDescriptionKey: "Update Error"])
		}
		addOrUpdate(marker: newNote)
		return newNote
	}
}
