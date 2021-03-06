//
//  Notes.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/31/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation

let STATUS_FIXME = "fixme"
let STATUS_KEEPRIGHT = "keepright"
let STATUS_WAYPOINT = "waypoint"

final class OsmNoteComment {
	let date: String
	let action: String
	let text: String
	let user: String

	init(date: String, action: String, text: String, user: String) {
		self.date = date
		self.action = action
		self.text = text
		self.user = user
	}

	init(gpxWaypoint description: String) {
		date = ""
		user = ""
		action = "waypoint"
		text = "\(description)"
	}

	init(keepRight objectName: String, description: String) {
		date = ""
		user = ""
		action = "keepright"
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

	let dateCreated: String // date created
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
	     dateCreated: String,
	     comments: [OsmNoteComment])
	{
		buttonId = MapMarker.NextButtonID()
		self.lat = lat
		self.lon = lon
		self.dateCreated = dateCreated
		self.comments = comments
	}

	func shouldHide() -> Bool {
		return false
	}

	var buttonLabel: String { fatalError() }
}

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

// An OSM object containing a fixme= tag
class Fixme: MapMarker {
	let noteId: OsmExtendedIdentifier
	weak var object: OsmBaseObject?

	override var key: String {
		return "fixme-\(noteId)"
	}

	/// If the object contains a fixme then returns the fixme value, else nil
	static func fixmeTag(_ object: OsmBaseObject) -> String? {
		if let tag = object.tags.first(where: { $0.key.caseInsensitiveCompare("fixme") == .orderedSame }) {
			return tag.value
		}
		return nil
	}

	override func shouldHide() -> Bool {
		guard let object = object else { return true }
		return Fixme.fixmeTag(object) == nil
	}

	override var buttonLabel: String { "F" }

	/// Initialize from FIXME data
	init(object: OsmBaseObject, text: String) {
		let center = object.selectionPoint()
		let comment = OsmNoteComment(date: object.timestamp,
		                             action: "fixme",
		                             text: text,
		                             user: object.user)

		self.object = object
		noteId = object.extendedIdentifier
		super.init(lat: center.lat,
		           lon: center.lon,
		           dateCreated: object.timestamp,
		           comments: [comment])
	}
}

// A GPX waypoint
class WayPoint: MapMarker {
	/// Initialize based on KeepRight query
	static func parseXML(gpxWaypointXml waypointElement: DDXMLElement, namespace ns: String)
		-> (lon: Double, lat: Double, desc: String, extensions: [DDXMLNode])?
	{
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
		var extensions: [DDXMLNode] = []

		for child in waypointElement.children ?? [] {
			guard let child = child as? DDXMLElement else {
				continue
			}
			if child.name == "name" {
				// ignore for now
			} else if child.name == "desc" {
				description = child.stringValue ?? ""
			} else if child.name == "extensions",
			          let children = child.children
			{
				extensions = children
			}
		}
		return (lon, lat, description, extensions)
	}

	/// Initialize based on KeepRight query
	init?(gpxWaypointXml waypointElement: DDXMLElement, status: String, namespace ns: String, mapData: OsmMapData) {
		guard let (lon, lat, desc, _) = Self.parseXML(gpxWaypointXml: waypointElement, namespace: ns)
		else { return nil }

		let comment = OsmNoteComment(gpxWaypoint: desc)
		super.init(lat: lat,
		           lon: lon,
		           dateCreated: "",
		           comments: [comment])
	}

	override var key: String {
		fatalError() // return "waypoint-()"
	}

	override var buttonLabel: String { "W" }
}

// A keep-right entry. These use XML just like a GPS waypoint, but with an extension to define OSM data.
class KeepRight: MapMarker {
	let noteId: Int
	let objectId: OsmExtendedIdentifier

	override var key: String {
		return "keepright-\(noteId)"
	}

	override var buttonLabel: String { "R" }

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

		guard let (lon, lat, desc, extensions) = WayPoint.parseXML(gpxWaypointXml: waypointElement, namespace: ns)
		else { return nil }

		var osmIdent: OsmIdentifier?
		var osmType: String?
		var noteId: Int?
		for child2 in extensions {
			guard let child2 = child2 as? DDXMLElement else {
				continue
			}
			if child2.name == "id",
			   let string = child2.stringValue,
			   let id = Int(string)
			{
				noteId = id
			} else if child2.name == "object_id" {
				osmIdent = Int64(child2.stringValue ?? "") ?? 0
			} else if child2.name == "object_type" {
				osmType = child2.stringValue
			}
		}
		guard let osmIdent = osmIdent,
		      let osmType = osmType,
		      let noteId = noteId
		else { return nil }

		guard let type = try? OSM_TYPE(string: osmType) else { return nil }
		let objectId = OsmExtendedIdentifier(type, osmIdent)

		let objectName: String
		if let object = mapData.object(withExtendedIdentifier: objectId) {
			let friendlyDescription = object.friendlyDescription()
			objectName = "\(friendlyDescription) (\(osmType) \(osmIdent))"
		} else {
			objectName = "\(osmType) \(osmIdent)"
		}
		let comment = OsmNoteComment(keepRight: objectName, description: desc)
		self.noteId = noteId
		self.objectId = objectId
		super.init(lat: lat,
		           lon: lon,
		           dateCreated: "",
		           comments: [comment])
	}
}

final class OsmNotesDatabase: NSObject {
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
						if let fixme = Fixme.fixmeTag(obj) {
							let note = Fixme(object: obj, text: fixme)
							addOrUpdate(note)
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
