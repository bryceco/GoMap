//
//  MapMarkerDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation

final class MapMarkerDatabase: NSObject {
	private let workQueue = OperationQueue()
	private var _keepRightIgnoreList: [Int: Bool]? // FIXME: Use UserDefaults for storage so this becomes non-optional
	private var noteForTag: [Int: MapMarker] = [:] // return the note with the given button tag (tagId)
	private var tagForKey: [String: Int] = [:]
	weak var mapData: OsmMapData!

	override init() {
		super.init()
		workQueue.maxConcurrentOperationCount = 1
	}

	func reset() {
		workQueue.cancelAllOperations()
		noteForTag.removeAll()
		tagForKey.removeAll()
	}

	/// This is called when we download a new note. If it is an update to an existing note then
	/// we need to delete the reference to the previous tag, so the button can be replaced.
	func addOrUpdate(_ newNote: MapMarker) {
		let key = newNote.key
		let newTag = newNote.buttonId
		if let oldTag = tagForKey[key] {
			// remove any existing tag with the same key
			noteForTag.removeValue(forKey: oldTag)
		}
		tagForKey[key] = newTag
		noteForTag[newTag] = newNote
	}

	func updateMarkers(forRegion box: OSMRect, fixmeData mapData: OsmMapData, completion: @escaping () -> Void) {
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
						addOrUpdate(note)
					}

					// add from FIXME=yes tags
					mapData.enumerateObjects(inRegion: box, block: { [self] obj in
						if let fixme = FixmeMarker.fixmeTag(obj) {
							let marker = FixmeMarker(object: obj, text: fixme)
							self.addOrUpdate(marker)
						}

#if DEBUG
						for quest in QuestList.shared.questsForObject(obj) {
							let marker = QuestMarker(object: obj, quest: quest)
							self.addOrUpdate(marker)
						}
#endif
					})

					completion()
				})
			})
		}
	}

	func update(withGpxWaypoints xmlText: String, mapData: OsmMapData, completion: @escaping () -> Void) {
		guard let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0)
		else {
			return
		}

		DispatchQueue.main.async(execute: { [self] in

			if let namespace1 = DDXMLElement.namespace(
				withName: "ns1",
				stringValue: "http://www.topografix.com/GPX/1/0") as? DDXMLElement
			{
				xmlDoc.rootElement()?.addNamespace(namespace1)
			}
			if let namespace2 = DDXMLElement.namespace(
				withName: "ns2",
				stringValue: "http://www.topografix.com/GPX/1/1") as? DDXMLElement
			{
				xmlDoc.rootElement()?.addNamespace(namespace2)
			}
			for ns in ["ns1:", "ns2:", ""] {
				let path = "./\(ns)gpx/\(ns)wpt"

				guard let a: [DDXMLNode] = try? xmlDoc.nodes(forXPath: path) as? [DDXMLElement]
				else {
					continue
				}

				for waypointElement in a {
					guard let waypointElement = waypointElement as? DDXMLElement else {
						continue
					}
					if let note = KeepRightMarker(gpxWaypointXml: waypointElement,
					                              namespace: ns,
					                              mapData: mapData)
					{
						addOrUpdate(note)
					}
				}
			}
			completion()
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
			   let xmlText = String(data: data, encoding: .utf8)
			{
				update(withGpxWaypoints: xmlText, mapData: mapData, completion: completion)
			}
		})
	}

	func updateRegion(
		_ bbox: OSMRect,
		withDelay delay: CGFloat,
		fixmeData mapData: OsmMapData,
		completion: @escaping () -> Void)
	{
		workQueue.cancelAllOperations()
		workQueue.addOperation({
			usleep(UInt32(1000 * (delay + 0.25)))
		})
		workQueue.addOperation({ [self] in
			updateMarkers(forRegion: bbox, fixmeData: mapData, completion: completion)
#if false
			updateKeepRight(forRegion: bbox, mapData: mapData, completion: completion)
#endif
		})
	}

	func enumerateNotes(_ callback: (_ note: MapMarker) -> Void) {
		for note in noteForTag.values {
			callback(note)
		}
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
				addOrUpdate(newNote)
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
		return noteForTag[tag]
	}

	// MARK: Ignore list

	// FIXME: change this to just use non-optional _keepRightIgnoreList
	func ignoreList() -> [Int: Bool] {
		if _keepRightIgnoreList == nil {
			let path = URL(fileURLWithPath: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
				.map(\.path).last ?? "").appendingPathComponent("keepRightIgnoreList").path
			_keepRightIgnoreList = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? [Int: Bool]
			if _keepRightIgnoreList == nil {
				_keepRightIgnoreList = [:]
			}
		}
		return _keepRightIgnoreList!
	}

	func ignore(_ note: MapMarker) {
		if _keepRightIgnoreList == nil {
			_keepRightIgnoreList = [:]
		}
		_keepRightIgnoreList![note.buttonId] = true

		let path = URL(fileURLWithPath: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
			.map(\.path).last ?? "").appendingPathComponent("keepRightIgnoreList").path
		NSKeyedArchiver.archiveRootObject(_keepRightIgnoreList!, toFile: path)
	}

	func isIgnored(_ note: MapMarker) -> Bool {
		if ignoreList()[note.buttonId] != nil {
			return true
		}
		return false
	}
}
