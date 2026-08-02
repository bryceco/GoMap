//
//  OsmNote.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/26/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation
import KissXML

struct OsmNote {
	enum Error: LocalizedError {
		case parseError
		case updateError

		var errorDescription: String? {
			switch self {
			case .parseError: return NSLocalizedString("Could not parse note", comment: "")
			case .updateError: return NSLocalizedString("Update Error", comment: "")
			}
		}
	}

	struct Comment {
		let date: String
		let action: String
		let text: String
		let user: String

		var description: String { "\(action): \(text)" }
	}

	let noteId: Int64
	let status: String // "open", "closed", etc.
	let dateCreated: String
	let comments: [Comment]
	let latLon: LatLon

	/// For user-created notes not yet saved to the server
	init(latLon: LatLon) {
		self.noteId = 0
		self.status = ""
		self.dateCreated = ""
		self.comments = []
		self.latLon = latLon
	}

	/// Parse from a `<note>` XML element
	init?(noteXml noteElement: DDXMLElement) {
		guard let lat2 = noteElement.attribute(forName: "lat")?.stringValue,
		      let lon2 = noteElement.attribute(forName: "lon")?.stringValue,
		      let lat = Double(lat2),
		      let lon = Double(lon2)
		else { return nil }

		var noteId: Int64?
		var dateCreated: String?
		var status: String?
		var comments: [Comment] = []
		for child in noteElement.children ?? [] {
			guard let child = child as? DDXMLElement else { continue }
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
						guard let child = child as? DDXMLElement else { continue }
						if child.name == "date" {
							date = child.stringValue ?? ""
						} else if child.name == "user" {
							user = child.stringValue ?? ""
						} else if child.name == "action" {
							action = child.stringValue ?? ""
						} else if child.name == "text" {
							text = child.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
						}
					}
					comments.append(Comment(date: date, action: action, text: text, user: user))
				}
			}
		}
		guard let noteId = noteId,
		      let dateCreated = dateCreated,
		      let status = status
		else {
			return nil
		}

		self.noteId = noteId
		self.status = status
		self.dateCreated = dateCreated
		self.comments = comments
		self.latLon = LatLon(latitude: lat, longitude: lon)
	}

	// MARK: Downloading

	/// Download a single note by ID
	static func download(id: Int64) async throws -> OsmNote {
		let url = OSM_SERVER.apiURL.appendingPathComponent("api/0.6/notes/\(id)")
		let data = try await URLSession.shared.data(with: url)
		guard let xmlText = String(data: data, encoding: .utf8),
		      let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0),
		      let noteElement = try? xmlDoc.rootElement()?.nodes(forXPath: "./note").first as? DDXMLElement,
		      let note = OsmNote(noteXml: noteElement)
		else {
			throw Error.parseError
		}
		return note
	}

	enum UploadAction {
		case comment
		case close
	}

	/// Upload a new note or add/close a comment on an existing one, returning the updated note
	func upload(action: UploadAction, comment: String) async throws -> OsmNote {
		var relativeUrl: String
		let queryItems: [String: String]

		if comments.isEmpty {
			// Brand new note
			relativeUrl = "api/0.6/notes"
			queryItems = ["lat": "\(latLon.lat)",
			              "lon": "\(latLon.lon)",
			              "text": comment]
		} else if action == .close {
			relativeUrl = "api/0.6/notes/\(noteId)/close"
			queryItems = ["text": comment]
		} else {
			relativeUrl = "api/0.6/notes/\(noteId)/comment"
			queryItems = ["text": comment]
		}

		let postData = try await OSM_SERVER.putRequest(relativeUrl: relativeUrl,
		                                               queryItems: queryItems,
		                                               method: "POST",
		                                               xml: nil)
		guard let xmlText = String(data: postData, encoding: .utf8),
		      let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0),
		      let list = try? xmlDoc.rootElement()?.nodes(forXPath: "./note") as? [DDXMLElement],
		      let noteElement = list.first,
		      let updatedNote = OsmNote(noteXml: noteElement)
		else {
			throw Error.updateError
		}
		return updatedNote
	}

	/// Download all open notes within a bounding box
	static func download(inBbox box: OSMRect) async throws -> [OsmNote] {
		let bbox = "\(box.origin.x),\(box.origin.y),\(box.origin.x + box.size.width),\(box.origin.y + box.size.height)"
		let url = OSM_SERVER.apiURL.appendingPathComponent("api/0.6/notes")
			.appendingQueryItems(["closed": "0", "bbox": bbox])
		let data = try await URLSession.shared.data(with: url)
		guard let xmlText = String(data: data, encoding: .utf8),
		      let xmlDoc = try? DDXMLDocument(xmlString: xmlText, options: 0)
		else {
			return []
		}
		let noteElements = (try? xmlDoc.rootElement()?.nodes(forXPath: "./note")) ?? []
		return noteElements.compactMap { ($0 as? DDXMLElement).flatMap { OsmNote(noteXml: $0) } }
	}
}
