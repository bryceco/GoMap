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

private var g_nextTagID = 1

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

final class OsmNote {
	let lat: Double
	let lon: Double
	let tagId: Int // a unique value we assign to track note buttons. If > 0 this is the noteID, otherwise it is assigned by us.

	private(set) var noteId: Int64 =
		0 // for Notes this is the note ID, for fixme or Keep Right it is the OSM object ID, for GPX it is the waypoint ID
	private(set) var created = ""
	private(set) var status = ""
	private(set) var comments: [OsmNoteComment] = []

	var isFixme: Bool {
		return status == STATUS_FIXME
	}

	var isKeepRight: Bool {
		return status == STATUS_KEEPRIGHT
	}

	var isWaypoint: Bool {
		return status == STATUS_WAYPOINT
	}

	var key: String {
		if isFixme {
			return "fixme-\(noteId)"
		}
		if isWaypoint {
			return "waypoint-\(noteId)"
		}
		if isKeepRight {
			return "keepright-\(noteId)"
		}
		return "note-\(noteId)"
	} // a unique identifier for a note across multiple downloads

	init(lat: Double, lon: Double) {
		tagId = g_nextTagID
		g_nextTagID += 1

		self.lat = lat
		self.lon = lon
	}

	init?(noteXml noteElement: DDXMLElement?) {
		tagId = g_nextTagID
		g_nextTagID += 1

		lat = Double(noteElement?.attribute(forName: "lat")?.stringValue ?? "") ?? 0.0
		lon = Double(noteElement?.attribute(forName: "lon")?.stringValue ?? "") ?? 0.0
		for child in noteElement?.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			if child.name == "id" {
				noteId = Int64(child.stringValue ?? "0") ?? 0
			} else if child.name == "date_created" {
				created = child.stringValue ?? ""
			} else if child.name == "status" {
				status = child.stringValue ?? ""
			} else if child.name == "comments" {
				guard let children = child.children as? [DDXMLElement] else { return nil }
				for commentElement in children {
					let comment = OsmNoteComment(noteXml: commentElement)
					comments.append(comment)
				}
			}
		}
		if noteId == 0 { return nil }
	}

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

		tagId = g_nextTagID
		g_nextTagID += 1
		lon = Double(waypointElement.attribute(forName: "lon")?.stringValue ?? "") ?? 0.0
		lat = Double(waypointElement.attribute(forName: "lat")?.stringValue ?? "") ?? 0.0
		self.status = status

		var description: String = ""
		var osmIdent: OsmIdentifier?
		var osmType: String?

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
					if child2.name == "id" {
						noteId = Int64(child2.stringValue ?? "") ?? 0
					} else if child2.name == "object_id" {
						osmIdent = Int64(child2.stringValue ?? "") ?? 0
					} else if child2.name == "object_type" {
						osmType = child2.stringValue
					}
				}
			}
		}
		guard let osmIdent = osmIdent,
		      let osmType = osmType
		else { return nil }

		var object: OsmBaseObject?
		let type: OSM_TYPE

		switch osmType {
		case "node":
			type = OSM_TYPE._NODE
			object = mapData.nodes[osmIdent]
		case "way":
			type = OSM_TYPE._WAY
			object = mapData.ways[osmIdent]
		case "relation":
			type = OSM_TYPE._RELATION
			object = mapData.relations[osmIdent]
		default:
			return nil
		}
		let objectName: String
		if let object = object {
			let friendlyDescription = object.friendlyDescription()
			objectName = "\(friendlyDescription) (\(osmType) \(osmIdent))"
		} else {
			objectName = "\(osmType) \(osmIdent)"
		}
		noteId = OsmBaseObject.extendedIdentifierForType(type, identifier: osmIdent)
		let comment = OsmNoteComment(gpxWaypoint: objectName, description: description)
		comments = [comment]
	}

	init(fixmeObject object: OsmBaseObject, fixmeKey fixme: String) {
		let center = object.selectionPoint()
		tagId = g_nextTagID
		g_nextTagID += 1
		noteId = object.extendedIdentifier.rawValue
		lon = center.lon
		lat = center.lat
		created = object.timestamp
		status = STATUS_FIXME
		let comment = OsmNoteComment(fixmeObject: object, fixmeKey: fixme)
		comments = [comment]
	}

	var description: String {
		var text = "Note \(noteId) - \(status):\n"
		for comment in comments {
			text += "  \(comment.description)\n"
		}
		return text
	}
}

final class OsmNotesDatabase: NSObject {
	let workQueue = OperationQueue()
	var keepRightIgnoreList: [Int: Bool]?
	var noteForTag: [Int: OsmNote] = [:]
	var tagForKey: [String: Int] = [:]
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

	func addOrUpdate(_ newNote: OsmNote) {
		let key = newNote.key
		let oldTag = tagForKey[key]
		let newTag = newNote.tagId
		if let oldTag = oldTag {
			// remove any existing tag with the same key
			noteForTag.removeValue(forKey: oldTag)
		}
		tagForKey[key] = newTag
		noteForTag[newTag] = newNote
	}

#if false

	func update(_ object: OsmBaseObject?) {
		let ident = NSNumber(value: object?.extendedIdentifier)
		dict.removeValue(forKey: ident)

		for key in FixMeList ?? [] {
			guard let key = key as? String else {
				continue
			}
			let fixme = object?.tags[key] as? String
			if (fixme?.count ?? 0) > 0 {
				let note = OsmNote(fixmeObject: object, fixmeKey: key)
				dict[note.ident] = note
				break
			}
		}
	}

#endif

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
							if let fixme = obj.tags[key],
							   fixme.count > 0
							{
								let note = OsmNote(fixmeObject: obj, fixmeKey: key)
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
					if let note = OsmNote(gpxWaypointXml: waypointElement,
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

	func enumerateNotes(_ callback: @escaping (_ note: OsmNote) -> Void) {
		(noteForTag as NSDictionary?)?.enumerateKeysAndObjects({ _, note, _ in
			if let note = note as? OsmNote {
				callback(note)
			}
		})
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
		completion: @escaping (_ newNote: OsmNote?, _ errorMessage: String?) -> Void)
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

		mapData.putRequest(url: url, method: "POST", xml: nil) { [self] postData, postErrorMessage in
			if let postData = postData,
			   postErrorMessage == nil,
			   let xmlText = String(data: postData, encoding: .utf8),
			   let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0),
			   let list = try? xmlDoc.rootElement()?.nodes(forXPath: "./note") as? [DDXMLElement],
			   let noteElement = list.first,
			   let newNote = OsmNote(noteXml: noteElement)
			{
				addOrUpdate(newNote)
				completion(newNote, nil)
			} else {
				completion(nil, postErrorMessage ?? "Update Error")
			}
		}
	}

	func note(forTag tag: Int) -> OsmNote? {
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

	func ignore(_ note: OsmNote) {
		var tempIgnoreList = ignoreList()
		tempIgnoreList[note.tagId] = true

		let path = URL(fileURLWithPath: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
			.map(\.path).last ?? "").appendingPathComponent("keepRightIgnoreList").path
		if let keepRightIgnoreList = keepRightIgnoreList {
			NSKeyedArchiver.archiveRootObject(keepRightIgnoreList, toFile: path)
		}
	}

	func isIgnored(_ note: OsmNote) -> Bool {
		if ignoreList()[note.tagId] != nil {
			return true
		}
		return false
	}
}
