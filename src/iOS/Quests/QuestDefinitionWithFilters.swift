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
	var tagKey: String
	var filters: [QuestDefinitionFilter]

	private static func makeOrSets(list: [QuestDefinitionFilter]) -> [([String: String]) -> Bool] {
		var list = list
		var orSets: [([String: String]) -> Bool] = []
		while let rule = list.popLast() {
			// collect all items that match first item
			var pred = rule.makePredicate()
			while let otherIndex = list.indices.first(where: {
				list[$0].tagKey == rule.tagKey && list[$0].relation == rule.relation
			}) {
				let rhs = list[otherIndex].makePredicate()
				list.remove(at: otherIndex)
				let lhs = pred
				pred = { tags in lhs(tags) || rhs(tags) }
			}
			orSets.append(pred)
		}
		return orSets
	}

	private static func makeIncludePredicate(include: [QuestDefinitionFilter]) throws -> (([String: String]) -> Bool) {
		var orSets = Self.makeOrSets(list: include)
		guard !orSets.isEmpty else {
			throw QuestError.noFiltersDefined
		}
		// combine all OR sets with ANDS
		var andPred = orSets.popLast()!
		while let rhs = orSets.popLast() {
			let lhs = andPred
			andPred = { tags in lhs(tags) && rhs(tags) }
		}
		return andPred
	}

	private static func makeExcludePredicate(exclude: [QuestDefinitionFilter]) throws -> (([String: String]) -> Bool)? {
		var orSets = Self.makeOrSets(list: exclude)
		guard !orSets.isEmpty else {
			return nil
		}
		var andPred = orSets.popLast()!
		while let rhs = orSets.popLast() {
			let lhs = andPred
			andPred = { tags in lhs(tags) && rhs(tags) }
		}
		return andPred
	}

	private static func makePredicate(filters: [QuestDefinitionFilter]) throws -> (([String: String]) -> Bool) {
		if filters.contains(where: { $0.tagKey == "" }) {
			throw QuestError.emptyKeyString
		}

		let include = filters.filter({ $0.included == .include })
		let exclude = filters.filter({ $0.included == .exclude })

		let includePred = try Self.makeIncludePredicate(include: include)
		let excludePred = try Self.makeExcludePredicate(exclude: exclude)

		if let excludePred = excludePred {
			return { includePred($0) && !excludePred($0) }
		} else {
			return includePred
		}
	}

	func makeQuestInstance() throws -> QuestProtocol {
		let pred = try Self.makePredicate(filters: filters)
		return QuestInstance(ident: title,
		                     title: title,
		                     label: label,
		                     presetKey: tagKey,
		                     appliesToObject: { pred($0.tags) },
		                     acceptsValue: { _ in true })
	}
}
