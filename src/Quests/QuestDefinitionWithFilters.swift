//
//  QuestDefinitionWithFilters.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/21/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

/// A single key/value test in the legacy flat filter list. Quests saved before nested groups
/// existed store only this list; it is converted to a tree on load and never written again.
struct QuestDefinitionFilter: Codable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
	enum Relation: String, Codable {
		case equal = "="
		case notEqual = "≠"
	}

	enum Included: String, Codable {
		case include
		case exclude
	}

	private enum CodingKeys: String, CodingKey {
		case tagKey
		case tagValue
		case relation
		case included
	}

	let id = UUID() // This is used by SwiftUI
	var tagKey: String
	var tagValue: String
	var relation: Relation
	var included: Included

	var description: String {
		return "'\(tagKey)' \(relation.rawValue) '\(tagValue)' \(included.rawValue)"
	}

	var debugDescription: String {
		return description
	}
}

struct QuestDefinitionWithFilters: QuestDefinition {
	struct Geometries: Codable {
		var point: Bool
		var line: Bool
		var area: Bool
		var vertex: Bool

		init(point: Bool = false, line: Bool = false, area: Bool = false, vertex: Bool = false) {
			self.point = point
			self.line = line
			self.area = area
			self.vertex = vertex
		}

		func isEmpty() -> Bool {
			// all true or all false is treated identically
			return (point && line && vertex && area) ||
				(!point && !line && !vertex && !area)
		}
	}

	var title: String
	var label: String
	var editKeys: [String]
	/// The nested AND/OR tree of conditions an object must satisfy.
	var filterTree: QuestFilterGroup
	var geometry: Geometries

	init(title: String, label: String, editKeys: [String], filterTree: QuestFilterGroup, geometry: Geometries) {
		self.title = title
		self.label = label
		self.editKeys = editKeys
		self.filterTree = filterTree
		self.geometry = geometry
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case title
		case label
		case editKeys
		case tagKeys // old alias for editKeys
		case tagKey // old alias for editKeys
		case filters // legacy flat list, read but no longer written
		case filterTree
		case geometry
	}

	init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			let title = try container.decode(String.self, forKey: .title)
			let label = try container.decode(String.self, forKey: .label)
			// editKeys has been renamed several times:
			let editKeys: [String]
			if let string = try? container.decode(String.self, forKey: .tagKey) {
				editKeys = string.split(separator: ",").map { String($0) }
			} else if let tagKeys = try? container.decode([String].self, forKey: .tagKeys) {
				editKeys = tagKeys
			} else {
				editKeys = try container.decode([String].self, forKey: .editKeys)
			}

			// The tree is authoritative. Quests saved before it existed have only the flat list,
			// and a tree this version can't read (written by a newer version) falls back to the list too.
			let filterTree: QuestFilterGroup
			if container.contains(.filterTree) {
				do {
					filterTree = try container.decode(QuestFilterGroup.self, forKey: .filterTree)
				} catch {
					guard container.contains(.filters) else { throw error }
					print("Unreadable filterTree for quest '\(title)', using flat filters instead: \(error)")
					let filters = try container.decode([QuestDefinitionFilter].self, forKey: .filters)
					filterTree = QuestFilterGroup(filters: filters, editKeys: editKeys)
				}
			} else {
				let filters = try container.decode([QuestDefinitionFilter].self, forKey: .filters)
				filterTree = QuestFilterGroup(filters: filters, editKeys: editKeys)
			}

			self.title = title
			self.label = label
			self.editKeys = editKeys
			self.filterTree = filterTree
			geometry = (try? container.decode(Geometries.self, forKey: .geometry)) ?? Geometries()
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(title, forKey: .title)
		try container.encode(label, forKey: .label)
		try container.encode(editKeys, forKey: .editKeys)
		try container.encode(filterTree, forKey: .filterTree)
		try container.encode(geometry, forKey: .geometry)
	}

	// MARK: makeQuestInstance

	private static func makePredicateFor(geometry: Geometries) -> ((GEOMETRY) -> Bool)? {
		if geometry.isEmpty() {
			return nil
		}
		var list: [GEOMETRY] = []
		if geometry.point { list.append(.POINT) }
		if geometry.line { list.append(.LINE) }
		if geometry.area { list.append(.AREA) }
		if geometry.vertex { list.append(.VERTEX) }
		return { list.contains($0) }
	}

	func makeQuestInstance() throws -> QuestProtocol {
		if !QuestInstance.isImage(label: label),
		   !QuestInstance.isCharacter(label: label)
		{
			throw QuestError.illegalLabel(label)
		}
		if filterTree.children.isEmpty {
			throw QuestError.noFiltersDefined
		}

		let filterPred = try filterTree.makePredicate()
		let pred: (OsmBaseObject) -> Bool
		if let geomPred = Self.makePredicateFor(geometry: geometry) {
			pred = { geomPred($0.geometry()) && filterPred($0.tags) }
		} else {
			pred = { filterPred($0.tags) }
		}
		return QuestInstance(ident: title,
		                     title: title,
		                     label: label,
		                     editKeys: editKeys,
		                     appliesToObject: pred,
		                     acceptsValue: { _ in true })
	}
}
