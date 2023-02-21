//
//  QuestDefinition.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/20/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

/// A quest definition is a user-generated, editable, codable description of a quest.

protocol QuestDefinition: Codable {
	var title: String { get }
	func makeQuestInstance() throws -> QuestProtocol
}

enum QuestError: LocalizedError {
	case unknownKey(String)
	case unknownFeature(String)
	case noStringEquivalent
	case illegalLabel(String)
	case noFiltersDefined
	case unrecognizedUserDefinitionType

	public var errorDescription: String? {
		switch self {
		case let .unknownKey(text): return "The tag key '\(text)' is not referenced by any features"
		case let .unknownFeature(text): return "The feature '\(text)' does not exist"
		case .noStringEquivalent: return "Unable to convert the data to string"
		case let .illegalLabel(text): return "The quest label '\(text)' must be a single character"
		case .unrecognizedUserDefinitionType: return "A quest definition is of an unrecognized type"
		case .noFiltersDefined: return "No filters are defined for the quest"
		}
	}
}

// MARK: Quest with features

struct QuestDefinedWithPresetFeatures: QuestDefinition {
	var title: String // "Add Surface" or similar
	var label: String // single character displayed in MapMarkerButton
	var presetKey: String // "surface"
	var includeFeatures: [String] // list of featureID

	func makeQuestInstance() throws -> QuestProtocol {
		return try QuestInstanceWithFeatures(presetFeatures: self)
	}
}

// MARK: Quest with filters

struct QuestTagFilter: Codable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
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
		if tagValue.isEmpty {
			switch relation {
			case .equal:
				return { $0[tagKey] == nil }
			case .notEqual:
				return { $0[tagKey] != nil }
			}
		} else {
			switch relation {
			case .equal:
				return { $0[tagKey] == tagValue }
			case .notEqual:
				return { $0[tagKey] != tagValue }
			}
		}
	}
}

struct QuestDefinedFromFilters: QuestDefinition {
	var title: String
	var label: String
	var tagKey: String
	var filters: [QuestTagFilter]

	private static func makeOrSets(list: [QuestTagFilter]) throws -> [([String: String]) -> Bool] {
		var list = list
		var orSets: [([String: String]) -> Bool] = []
		while let rule = list.popLast() {
			// collect all items that match first item
			var pred = rule.makePredicate()
			while let otherIndex = list.indices.first(where: {
				list[$0].tagKey == rule.tagKey && list[$0].included == rule.included
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

	private static func makeIncludePredicate(include: [QuestTagFilter]) throws -> (([String: String]) -> Bool) {
		var orSets = try Self.makeOrSets(list: include)
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

	private static func makeExcludePredicate(exclude: [QuestTagFilter]) throws -> (([String: String]) -> Bool)? {
		var orSets = try Self.makeOrSets(list: exclude)
		guard !orSets.isEmpty else {
			return nil
		}
		var andPred = orSets.popLast()!
		while let rhs = orSets.popLast() {
			let lhs = andPred
			// FIXME: Need to decide if we want to AND or OR here.
			andPred = { tags in lhs(tags) || rhs(tags) }
		}
		return andPred
	}

	private static func makePredicate(filters: [QuestTagFilter]) throws -> (([String: String]) -> Bool) {
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
		                     label: .text(label),
		                     presetKey: tagKey,
		                     appliesToObject: { pred($0.tags) },
		                     acceptsValue: { _ in true })
	}
}
