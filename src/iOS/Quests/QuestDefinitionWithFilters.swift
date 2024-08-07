//
//  QuestDefinitionWithFilters.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/21/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

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

	func makePredicate() -> (([String: String]) -> Bool) {
		switch relation {
		case .equal:
			switch tagValue {
			case "":
				return { $0[tagKey] == nil }
			case "*":
				return { $0[tagKey] != nil }
			default:
				return { $0[tagKey] == tagValue }
			}
		case .notEqual:
			switch tagValue {
			case "":
				return { $0[tagKey] != nil }
			case "*":
				return { $0[tagKey] == nil }
			default:
				return { $0[tagKey] != tagValue }
			}
		}
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
	var filters: [QuestDefinitionFilter]
	var geometry: Geometries

	init(title: String, label: String, editKeys: [String], filters: [QuestDefinitionFilter], geometry: Geometries) {
		self.title = title
		self.label = label
		self.editKeys = editKeys
		self.filters = filters
		self.geometry = geometry
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case title
		case label
		case editKeys
		case tagKeys // old alias for editKeys
		case tagKey // old alias for editKeys
		case filters
		case geometry
	}

	init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			title = try container.decode(String.self, forKey: .title)
			label = try container.decode(String.self, forKey: .label)
			// editKeys has been renamed several times:
			if let string = try? container.decode(String.self, forKey: .tagKey) {
				editKeys = string.split(separator: ",").map { String($0) }
			} else if let tagKeys = try? container.decode([String].self, forKey: .tagKeys) {
				editKeys = tagKeys
			} else {
				editKeys = try container.decode([String].self, forKey: .editKeys)
			}
			filters = try container.decode([QuestDefinitionFilter].self, forKey: .filters)
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
		try container.encode(filters, forKey: .filters)
		try container.encode(geometry, forKey: .geometry)
	}

	// MARK: makeQuestInstance

	/*
	 highway = primary
	 highway = secondary // gets ORed with previous
	 highway != lamp
	 highway != path		// gets ANDed with previous
	 */
	private typealias Predicate = ([String: String]) -> Bool
	private static func makeGroups(list: [QuestDefinitionFilter], editKeys: [String])
		-> [(predicate: Predicate, included: QuestDefinitionFilter.Included)]
	{
		var list = list
		var groups: [(Predicate, QuestDefinitionFilter.Included)] = []
		while let rule = list.popLast() {
			// collect all items that match first item for key and relation
			var pred = rule.makePredicate()

			while let otherIndex = list.indices.first(where: {
				let other = list[$0]
				// special case to detect situation where the user wants to edit any of several missing editKeys
				if editKeys.contains(rule.tagKey),
				   editKeys.contains(other.tagKey),
				   rule.relation == .equal,
				   other.relation == .equal,
				   rule.tagValue == "",
				   other.tagValue == "",
				   rule.included == .include,
				   other.included == .include
				{
					return true
				}
				return other.tagKey == rule.tagKey
					&& other.relation == rule.relation
					&& other.included == rule.included
			}) {
				let rhs = list[otherIndex].makePredicate()
				list.remove(at: otherIndex)
				let lhs = pred
				switch rule.relation {
				case .equal:
					pred = { tags in lhs(tags) || rhs(tags) }
				case .notEqual:
					pred = { tags in lhs(tags) && rhs(tags) }
				}
			}
			groups.append((pred, rule.included))
		}
		return groups
	}

	private static func makePredicateFor(filters: [QuestDefinitionFilter],
	                                     editKeys: [String]) throws -> (([String: String]) -> Bool)
	{
		if filters.contains(where: { $0.tagKey == "" }) {
			throw QuestError.emptyKeyString
		}
		if filters.first(where: { $0.included == .include }) == nil {
			throw QuestError.noFiltersDefined
		}

		// handle filters
		var groups = makeGroups(list: filters, editKeys: editKeys)

		let group = groups.popLast()!
		let p = group.predicate
		var pred = group.included == .include ? p : { !p($0) }

		while let rhsGroup = groups.popLast() {
			let lhs = pred
			let rhs = rhsGroup.predicate
			if rhsGroup.included == .include {
				pred = { lhs($0) && rhs($0) }
			} else {
				pred = { lhs($0) && !rhs($0) }
			}
		}

		return pred
	}

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

		let filterPred = try Self.makePredicateFor(filters: filters, editKeys: editKeys)
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
