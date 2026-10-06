//
//  QuestFilterValidation.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/5/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

/// What a single condition says about its key.
private enum QuestFilterConstraint: Equatable {
	case equals(String)
	case notEquals(String)
	case present
	case missing

	/// Returns nil for an incomplete condition (a comparison with no value yet).
	init?(_ condition: QuestFilterCondition) {
		let value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
		switch condition.op {
		case .equals:
			if value.isEmpty { return nil }
			self = .equals(value)
		case .notEquals:
			if value.isEmpty { return nil }
			self = .notEquals(value)
		case .exists:
			self = .present
		case .missing:
			self = .missing
		}
	}

	/// True if no tag value can satisfy both constraints at once.
	static func areContradictory(_ a: QuestFilterConstraint, _ b: QuestFilterConstraint) -> Bool {
		switch (a, b) {
		case let (.equals(x), .equals(y)):
			return x != y
		case let (.equals(x), .notEquals(y)), let (.notEquals(y), .equals(x)):
			return x == y
		case (.equals, .missing), (.missing, .equals),
		     (.present, .missing), (.missing, .present):
			return true
		default:
			return false
		}
	}

	/// True if every possible tag value satisfies at least one of the constraints.
	static func areExhaustive(_ a: QuestFilterConstraint, _ b: QuestFilterConstraint) -> Bool {
		switch (a, b) {
		case let (.notEquals(x), .notEquals(y)):
			return x != y
		case let (.equals(x), .notEquals(y)), let (.notEquals(y), .equals(x)):
			return x == y
		case (.notEquals, .present), (.present, .notEquals),
		     (.present, .missing), (.missing, .present):
			return true
		default:
			return false
		}
	}
}

extension QuestFilterGroup {
	/// A logical problem with the conditions in a group that makes it pointless.
	enum Problem: Equatable {
		/// An AND group containing conditions on the same key that can't both be true.
		case neverMatches
		/// An OR group containing conditions on the same key that between them cover every object.
		case alwaysMatches

		var localizedDescription: String {
			switch self {
			case .neverMatches:
				return NSLocalizedString("Never matches",
				                         comment: "Warning that a quest filter group's conditions contradict each other")
			case .alwaysMatches:
				return NSLocalizedString("Always matches",
				                         comment: "Warning that a quest filter group's conditions match every object")
			}
		}
	}

	/// Checks this group's own conditions for a contradiction (AND) or a tautology (OR).
	/// Only direct children are examined; nested groups report their own problems.
	/// Conditions with an empty key or value are ignored since the user is probably still typing.
	var problem: Problem? {
		let conditions: [(key: String, constraint: QuestFilterConstraint)] = children.compactMap { child in
			guard case let .condition(condition) = child else { return nil }
			let key = condition.key.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !key.isEmpty,
			      let constraint = QuestFilterConstraint(condition)
			else { return nil }
			return (key, constraint)
		}

		for i in conditions.indices {
			for j in conditions.indices where j > i && conditions[i].key == conditions[j].key {
				let a = conditions[i].constraint
				let b = conditions[j].constraint
				switch op {
				case .and:
					if QuestFilterConstraint.areContradictory(a, b) {
						return .neverMatches
					}
				case .or:
					if QuestFilterConstraint.areExhaustive(a, b) {
						return .alwaysMatches
					}
				}
			}
		}
		return nil
	}
}
