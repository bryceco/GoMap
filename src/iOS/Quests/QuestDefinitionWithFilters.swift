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
	var title: String
	var label: String
	var tagKeys: [String]
	var filters: [QuestDefinitionFilter]

	init(title: String, label: String, tagKeys: [String], filters: [QuestDefinitionFilter]) {
		self.title = title
		self.label = label
		self.tagKeys = tagKeys
		self.filters = filters
	}

	// MARK: Codable

	enum CodingKeys: String, CodingKey {
		case title
		case label
		case tagKeys
		case tagKey // old alias for tagKeys
		case filters
	}

	init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			title = try container.decode(String.self, forKey: .title)
			label = try container.decode(String.self, forKey: .label)
			if let string = try? container.decode(String.self, forKey: .tagKey) {
				tagKeys = string.split(separator: ",").map { String($0) }
			} else {
				tagKeys = try container.decode([String].self, forKey: .tagKeys)
			}
			filters = try container.decode([QuestDefinitionFilter].self, forKey: .filters)
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(title, forKey: .title)
		try container.encode(label, forKey: .label)
		try container.encode(tagKeys, forKey: .tagKeys)
		try container.encode(filters, forKey: .filters)
	}

	// MARK: makeQuestInstance

	/*
	 highway = primary
	 highway = secondary // gets ORed with previous
	 highway != lamp
	 highway != path		// gets ANDed with previous
	 */
	private typealias predicate = ([String: String]) -> Bool
	private static func makeGroups(list: [QuestDefinitionFilter])
		-> [(predicate: predicate, included: Bool)]
	{
		var list = list
		var groups: [(predicate, Bool)] = []
		while let rule = list.popLast() {

			// collect all items that match first item for key and relation
			var pred = rule.makePredicate()
			while let otherIndex = list.indices.first(where: {
				list[$0].tagKey == rule.tagKey &&
				list[$0].relation == rule.relation &&
				list[$0].included == rule.included
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
			groups.append((pred, rule.included == .include))
		}
		return groups
	}

	private static func makePredicate(filters: [QuestDefinitionFilter]) throws -> (([String: String]) -> Bool) {
		if filters.contains(where: { $0.tagKey == "" }) {
			throw QuestError.emptyKeyString
		}
		if filters.first(where: { $0.included == .include }) == nil {
			throw QuestError.noFiltersDefined
		}

		var groups = makeGroups(list: filters)

		let group = groups.popLast()!
		let p = group.predicate
		var pred = group.included ? p : { !p($0) }

		while let rhsGroup = groups.popLast() {
			let lhs = pred
			let rhs = rhsGroup.predicate
			if rhsGroup.included {
				pred = { lhs($0) && rhs($0) }
			} else {
				pred = { lhs($0) && !rhs($0) }
			}
		}
		return pred
	}

	func makeQuestInstance() throws -> QuestProtocol {
		let pred = try Self.makePredicate(filters: filters)
		return QuestInstance(ident: title,
		                     title: title,
		                     label: label,
		                     tagKeys: tagKeys,
		                     appliesToObject: { pred($0.tags) },
		                     acceptsValue: { _ in true })
	}
}
