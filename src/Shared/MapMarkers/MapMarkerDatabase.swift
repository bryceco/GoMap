//
//  MapMarkerDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation

@MainActor final class MapMarkerDatabase: MapMarkerIgnoreListProtocol {
	private var pendingUpdateTask: Task<Void, Never>?
	private var markerForIdentifier: [String: MapMarker] = [:] // map the marker key (unique string) to a marker
	private var ignoreList: MapMarkerIgnoreList
	weak var mapData: OsmMapData!
	var progress: MapViewProgress?

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

	func ignore(marker: MapMarker, reason: MapMarkerIgnoreReason) {
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
	                           isLargeArea: Bool) async
	{
		// Fixme markers
		if including.contains(.fixme),
			!isLargeArea
		{
			removeMarkers(where: {
				guard let fixme = $0 as? FixmeMarker else { return false }
				return fixme.object == nil || fixme.shouldHide()
			})
			updateFixmeMarkers(forRegion: box, mapData: mapData)
		} else {
			removeMarkers(where: { $0 is FixmeMarker })
		}

		// Quest markers
		if including.contains(.quest),
		   !isLargeArea
		{
			// Remove any quest markers whose OSM object was deallocated since last update
			removeMarkers(where: {
				guard let quest = $0 as? QuestMarker else { return false }
				return quest.object == nil
			})
			updateQuestMarkers(forRegion: box, mapData: mapData)
		} else {
			removeMarkers(where: { $0 is QuestMarker })
		}

		// Gpx markers
		if including.contains(.gpx) {
			if including == .gpx {
				// if we deleted a gpx track we get called to refresh markers, but
				// we don't remove old markers normally. But if we're precisely
				// requesting an update for .gpx then do a full refresh.
				removeMarkers(where: { $0 is WayPointMarker })
			}
			updateGpxWaypointMarkers()
		} else {
			removeMarkers(where: { $0 is WayPointMarker })
		}

		// Geojson waypoint markers
		if including.contains(.geojson) {
			updateGeoJSONMarkers(forRegion: box)
		} else {
			removeMarkers(where: { $0 is GeoJsonMarker })
		}

		// Notes markers
		if including.contains(.notes),
		   !isLargeArea
		{
			removeMarkers(where: { ($0 as? OsmNoteMarker)?.shouldHide() ?? false })
			await updateNoteMarkers(forRegion: box)
		} else {
			removeMarkers(where: { $0 is OsmNoteMarker })
		}
	}

	func updateRegion(withDelay delay: TimeInterval,
	                  including: MapMarkerSet,
	                  completion: @escaping () -> Void)
	{
		// Schedule work to be done in a short while, but if we're called before then
		// cancel that operation and schedule a new one.
		pendingUpdateTask?.cancel()
		let task = Task { @MainActor in
			// Suspend for delay (in nanoseconds)
			let delayNs = UInt64((delay + 0.25) * 1000_000000)
			try? await Task.sleep(nanoseconds: delayNs)

			guard
				// Check for cancellation before proceeding
				!Task.isCancelled
			else {
				return
			}
			let bbox = AppDelegate.shared.mainView.viewPort.boundingLatLonForScreen()
			let isLargeArea = bbox.size.width * bbox.size.height > 0.25
			await self.updateMarkers(forRegion: bbox,
									 mapData: mapData,
									 including: including,
									 isLargeArea: isLargeArea)
			completion()
		}
		pendingUpdateTask = task
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

	func updateNoteMarkers(forRegion box: OSMRect) async {
		progress?.progressIncrement(1)
		defer { progress?.progressDecrement() }
		let notes = (try? await OsmNote.download(inBbox: box)) ?? []
		for note in notes {
			addOrUpdate(marker: OsmNoteMarker(note: note))
		}
	}
}
