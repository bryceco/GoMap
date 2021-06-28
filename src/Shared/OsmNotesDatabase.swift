//
//  Notes.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation

private let FixMeList: [String] = ["fixme", "FIXME"] // there are many others but not frequently used

let STATUS_FIXME = "fixme"
let STATUS_KEEPRIGHT = "keepright"
let STATUS_WAYPOINT = "waypoint"

final class OsmNoteComment {
	private(set) var date = ""
	private(set) var action = ""
	private(set) var text = ""
	private(set) var user = ""

	init(noteXml noteElement: DDXMLElement) {
		for child in noteElement.children ?? [] {
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
	}

	init(fixmeObject object: OsmBaseObject, fixmeKey fixme: String) {
		date = object.timestamp
		user = object.user
		action = "fixme"
		let friendlyDescription = object.friendlyDescription()
		if let tags = object.tags[fixme] {
			text =
				"\(friendlyDescription) (\((object.isNode() != nil) ? "node" : (object.isWay() != nil) ? "way" : (object.isRelation() != nil) ? "relation" : "") \(object.ident): \(tags)"
		}
	}

	init(gpxWaypoint objectName: String, description: String) {
		date = ""
		user = ""
		action = "waypoint"
		text = "\(objectName): \(description)"
	}

	var description: String {
		return "\(action): \(text)"
	}
}

class MapMarker {
	let buttonId: Int // a unique value we assign to track note buttons. If > 0 this is the noteID, otherwise it is assigned by us.

	let lat: Double
	let lon: Double

	// for Notes this is the note ID, for fixme or Keep Right it is the OSM object ID, for GPX it is the waypoint ID
	let noteId: Int64

	let dateCreated: String // date created
	let status: String // open, closed, etc.
	private(set) var comments: [OsmNoteComment] = []

	// a unique identifier for a note across multiple downloads
	var key: String {
		fatalError()
	}

	private static var g_nextButtonID = 1
	static func NextButtonID() -> Int {
		g_nextButtonID += 1
		return g_nextButtonID
	}

	init(lat: Double,
	     lon: Double,
	     noteId: Int64,
	     dateCreated: String,
	     status: String,
	     comments: [OsmNoteComment])
	{
		buttonId = MapMarker.NextButtonID()
		self.lat = lat
		self.lon = lon
		self.noteId = noteId
		self.dateCreated = dateCreated
		self.status = status
		self.comments = comments
	}

	var description: String {
		var text = "Note \(noteId) - \(status):\n"
		for comment in comments {
			text += "  \(comment.description)\n"
		}
		return text
	}
}

// A regular OSM note
class OsmNote: MapMarker {
	override var key: String {
		return "note-\(noteId)"
	}

	/// A note newly created by user
	init(lat: Double, lon: Double) {
		super.init(lat: lat,
		           lon: lon,
		           noteId: 0,
		           dateCreated: "",
		           status: "",
		           comments: [])
	}

	/// Initialize based on OSM Notes query
	init?(noteXml noteElement: DDXMLElement) {
		guard let lat = noteElement.attribute(forName: "lat")?.stringValue,
		      let lon = noteElement.attribute(forName: "lon")?.stringValue,
		      let lat = Double(lat),
		      let lon = Double(lon)
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
					let comment = OsmNoteComment(noteXml: commentElement)
					comments.append(comment)
				}
			}
		}
		guard let noteId = noteId,
		      let dateCreated = dateCreated,
		      let status = status
		else { return nil }
		super.init(lat: lat,
		           lon: lon,
		           noteId: noteId,
		           dateCreated: dateCreated,
		           status: status,
		           comments: comments)
	}
}

// An OSM object containing a fixme= tag
class Fixme: MapMarker {
	override var key: String {
		return "fixme-\(noteId)"
	}

	/// Initialize from FIXME data
	init(fixmeObject object: OsmBaseObject, fixmeKey fixme: String) {
		let center = object.selectionPoint()
		let comment = OsmNoteComment(fixmeObject: object, fixmeKey: fixme)

		super.init(lat: center.lat,
		           lon: center.lon,
		           noteId: object.extendedIdentifier.rawValue,
		           dateCreated: object.timestamp,
		           status: STATUS_FIXME,
		           comments: [comment])
	}
}

// A keep-right entry
class KeepRight: MapMarker {
	override var key: String {
		return "keepright-\(noteId)"
	}

	/// Initialize based on KeepRight query
	init?(gpxWaypointXml waypointElement: DDXMLElement, status: String, namespace ns: String, mapData: OsmMapData) {
		//		<wpt lon="-122.2009985" lat="47.6753189">
		//		<name><![CDATA[website, http error]]></name>
		//		<desc><![CDATA[The URL (<a target="_blank" href="http://www.stjamesespresso.com/">http://www.stjamesespresso.com/</a>) cannot be opened (HTTP status code 301)]]></desc>
		//		<extensions>
		//								<schema>21</schema>
		//								<id>78427597</id>
		//								<error_type>411</error_type>
		//								<object_type>node</object_type>
		//								<object_id>2627663149</object_id>
		//		</extensions></wpt>

		guard let lon = waypointElement.attribute(forName: "lon")?.stringValue,
		      let lat = waypointElement.attribute(forName: "lat")?.stringValue,
		      let lon = Double(lon),
		      let lat = Double(lat)
		else { return nil }

		var description: String = ""
		var osmIdent: OsmIdentifier?
		var osmType: String?
		var noteId: Int64?

		for child in waypointElement.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			if child.name == "name" {
				// ignore for now
			} else if child.name == "desc" {
				description = child.stringValue ?? ""
			} else if child.name == "extensions" {
				for child2 in child.children ?? [] {
					guard let child2 = child2 as? DDXMLElement else {
						continue
					}
					if child2.name == "id",
					   let string = child2.stringValue,
					   let id = Int64(string)
					{
						noteId = id
					} else if child2.name == "object_id" {
						osmIdent = Int64(child2.stringValue ?? "") ?? 0
					} else if child2.name == "object_type" {
						osmType = child2.stringValue
					}
				}
			}
		}
		guard let osmIdent = osmIdent,
		      let osmType = osmType,
		      let noteId = noteId
		else { return nil }

		let object: OsmBaseObject?
		switch osmType {
		case "node":
			object = mapData.nodes[osmIdent]
		case "way":
			object = mapData.ways[osmIdent]
		case "relation":
			object = mapData.relations[osmIdent]
		default:
			object = nil
		}
		let objectName: String
		if let object = object {
			let friendlyDescription = object.friendlyDescription()
			objectName = "\(friendlyDescription) (\(osmType) \(osmIdent))"
		} else {
			objectName = "\(osmType) \(osmIdent)"
		}
		let comment = OsmNoteComment(gpxWaypoint: objectName, description: description)
		super.init(lat: lat,
		           lon: lon,
		           noteId: noteId,
		           dateCreated: "",
		           status: status,
		           comments: [comment])
	}
}

// A GPX waypoint
class WayPoint: MapMarker {
	override var key: String {
		return "waypoint-\(noteId)"
	}
}

final class OsmNotesDatabase: NSObject {
	private let workQueue = OperationQueue()
	private var keepRightIgnoreList: [Int: Bool]?
	private var noteForTag: [Int: MapMarker] = [:]	// return the note with the given button tag (tagId)
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

	func updateNotes(forRegion box: OSMRect, fixmeData mapData: OsmMapData, completion: @escaping () -> Void) {
		let url = OSM_API_URL +
			"api/0.6/notes?closed=0&bbox=\(box.origin.x),\(box.origin.y),\(box.origin.x + box.size.width),\(box.origin.y + box.size.height)"
		if let url1 = URL(string: url) {
			URLSession.shared.data(with: url1, completionHandler: { [self] result in
				guard case let .success(data) = result,
				      let xmlText = String(data: data, encoding: .utf8),
				      let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0)
				else { return }

				var newNotes: [OsmNote] = []
				for noteElement in (try? xmlDoc.rootElement()?.nodes(forXPath: "./note")) ?? [] {
					guard let noteElement = noteElement as? DDXMLElement else {
						continue
					}
					if let note = OsmNote(noteXml: noteElement) {
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
						for key in FixMeList {
							if obj.tags[key] != nil {
								let note = Fixme(fixmeObject: obj, fixmeKey: key)
								addOrUpdate(note)
								break
							}
						}
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
					if let note = KeepRight(gpxWaypointXml: waypointElement,
					                        status: STATUS_KEEPRIGHT,
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
			updateNotes(forRegion: bbox, fixmeData: mapData, completion: completion)
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

	override var description: String {
		var text = ""
		for (_, note) in noteForTag {
			text = note.description
		}
		return text
	}

	func update(
		_ note: OsmNote,
		close: Bool,
		comment: String,
		completion: @escaping (Result<OsmNote, Error>) -> Void)
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
			   let newNote = OsmNote(noteXml: noteElement)
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

	func note(forTag tag: Int) -> MapMarker? {
		return noteForTag[tag]
	}

	// MARK: Ignore list

	func ignoreList() -> [Int: Bool] {
		if keepRightIgnoreList == nil {
			let path = URL(fileURLWithPath: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
				.map(\.path).last ?? "").appendingPathComponent("keepRightIgnoreList").path
			keepRightIgnoreList = NSKeyedUnarchiver.unarchiveObject(withFile: path) as? [Int: Bool]
			if keepRightIgnoreList == nil {
				keepRightIgnoreList = [:]
			}
		}
		return keepRightIgnoreList!
	}

	func ignore(_ note: MapMarker) {
		var tempIgnoreList = ignoreList()
		tempIgnoreList[note.buttonId] = true

		let path = URL(fileURLWithPath: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
			.map(\.path).last ?? "").appendingPathComponent("keepRightIgnoreList").path
		if let keepRightIgnoreList = keepRightIgnoreList {
			NSKeyedArchiver.archiveRootObject(keepRightIgnoreList, toFile: path)
		}
	}

	func isIgnored(_ note: MapMarker) -> Bool {
		if ignoreList()[note.buttonId] != nil {
			return true
		}
		return false
	}
}
