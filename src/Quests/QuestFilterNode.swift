//
//  QuestFilterNode.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/5/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

/// How the children of a filter group are combined.
enum QuestFilterOperator: String, Codable, CaseIterable {
	case and = "AND"
	case or = "OR"

	var toggled: QuestFilterOperator {
		switch self {
		case .and: return .or
		case .or: return .and
		}
	}

	var localizedTitle: String {
		switch self {
		case .and:
			return NSLocalizedString("AND", comment: "Logical operator combining quest filter conditions")
		case .or:
			return NSLocalizedString("OR", comment: "Logical operator combining quest filter conditions")
		}
	}
}

/// A single test of one tag in the filter tree.
struct QuestFilterCondition: Identifiable {
	enum Operator: CaseIterable {
		case equals
		case notEquals
		case exists
		case missing

		/// Whether the condition compares against a value, as opposed to only testing presence.
		var takesValue: Bool {
			switch self {
			case .equals, .notEquals: return true
			case .exists, .missing: return false
			}
		}

		/// Short form shown after the key in a row, e.g. "highway = residential" or "lit missing".
		var localizedTitle: String {
			switch self {
			case .equals: return "="
			case .notEquals: return "≠"
			case .exists:
				return NSLocalizedString("exists", comment: "the tag key is present")
			case .missing:
				return NSLocalizedString("missing", comment: "the tag key is absent")
			}
		}
	}

	let id = UUID() // This is used by SwiftUI
	var key: String
	var op: Operator
	var value: String

	init(key: String, op: Operator, value: String = "") {
		self.key = key
		self.op = op
		self.value = value
	}
}

/// A group of filter conditions and/or nested groups that are all combined with a single operator.
struct QuestFilterGroup: Identifiable {
	let id = UUID() // This is used by SwiftUI
	var op: QuestFilterOperator
	var children: [QuestFilterNode]
}

/// A node in the filter tree: either a single condition or a nested group.
enum QuestFilterNode: Identifiable {
	case condition(QuestFilterCondition)
	case group(QuestFilterGroup)

	var id: UUID {
		switch self {
		case let .condition(condition): return condition.id
		case let .group(group): return group.id
		}
	}
}

// MARK: Tree editing

extension QuestFilterGroup {
	/// All leaf conditions in depth-first order.
	var allConditions: [QuestFilterCondition] {
		return children.flatMap { child -> [QuestFilterCondition] in
			switch child {
			case let .condition(condition): return [condition]
			case let .group(group): return group.allConditions
			}
		}
	}

	/// Finds the group (possibly self) with the given id.
	func group(withID groupID: UUID) -> QuestFilterGroup? {
		if groupID == id {
			return self
		}
		for child in children {
			if case let .group(group) = child,
			   let found = group.group(withID: groupID)
			{
				return found
			}
		}
		return nil
	}

	/// Finds the condition with the given id.
	func condition(withID conditionID: UUID) -> QuestFilterCondition? {
		for child in children {
			switch child {
			case let .condition(condition):
				if condition.id == conditionID {
					return condition
				}
			case let .group(group):
				if let found = group.condition(withID: conditionID) {
					return found
				}
			}
		}
		return nil
	}

	/// Replaces the condition that has the same id as `condition`. Returns false if it isn't in the tree.
	@discardableResult
	mutating func replaceCondition(_ condition: QuestFilterCondition) -> Bool {
		for index in children.indices {
			switch children[index] {
			case let .condition(existing):
				if existing.id == condition.id {
					children[index] = .condition(condition)
					return true
				}
			case var .group(group):
				if group.replaceCondition(condition) {
					children[index] = .group(group)
					return true
				}
			}
		}
		return false
	}

	/// Removes the condition or group with the given id. Any group left empty as a result is removed as well.
	@discardableResult
	mutating func removeNode(withID nodeID: UUID) -> Bool {
		if let index = children.firstIndex(where: { $0.id == nodeID }) {
			children.remove(at: index)
			return true
		}
		for index in children.indices {
			guard case var .group(group) = children[index] else { continue }
			if group.removeNode(withID: nodeID) {
				if group.children.isEmpty {
					children.remove(at: index)
				} else {
					children[index] = .group(group)
				}
				return true
			}
		}
		return false
	}

	/// Appends a node to the end of the group (possibly self) with the given id.
	@discardableResult
	mutating func append(_ node: QuestFilterNode, toGroupWithID groupID: UUID) -> Bool {
		if groupID == id {
			children.append(node)
			return true
		}
		for index in children.indices {
			guard case var .group(group) = children[index] else { continue }
			if group.append(node, toGroupWithID: groupID) {
				children[index] = .group(group)
				return true
			}
		}
		return false
	}

	/// Sets the operator of the group (possibly self) with the given id.
	@discardableResult
	mutating func setOperator(_ newOp: QuestFilterOperator, forGroupWithID groupID: UUID) -> Bool {
		if groupID == id {
			op = newOp
			return true
		}
		for index in children.indices {
			guard case var .group(group) = children[index] else { continue }
			if group.setOperator(newOp, forGroupWithID: groupID) {
				children[index] = .group(group)
				return true
			}
		}
		return false
	}
}

// MARK: Codable
//
// The tree is stored as nested single-key objects, with the operator as the key:
//   { "and": [ ...nodes ] }        { "or": [ ...nodes ] }
//   { "exists": "key" }            { "missing": "key" }
//   { "=": ["key", "value"] }      { "!=": ["key", "value"] }

private struct QuestFilterNodeKey: CodingKey {
	let stringValue: String
	var intValue: Int? { return nil }

	init(_ string: String) {
		stringValue = string
	}

	init?(stringValue: String) {
		self.stringValue = stringValue
	}

	init?(intValue: Int) {
		return nil
	}
}

private extension QuestFilterOperator {
	var jsonKey: String {
		switch self {
		case .and: return "and"
		case .or: return "or"
		}
	}
}

extension QuestFilterNode: Codable {
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: QuestFilterNodeKey.self)
		guard container.allKeys.count == 1,
		      let key = container.allKeys.first
		else {
			throw QuestError.malformedFilterTree
		}
		switch key.stringValue {
		case "and":
			self = try .group(QuestFilterGroup(op: .and,
			                                   children: container.decode([QuestFilterNode].self, forKey: key)))
		case "or":
			self = try .group(QuestFilterGroup(op: .or,
			                                   children: container.decode([QuestFilterNode].self, forKey: key)))
		case "exists":
			self = try .condition(QuestFilterCondition(key: container.decode(String.self, forKey: key),
			                                           op: .exists))
		case "missing":
			self = try .condition(QuestFilterCondition(key: container.decode(String.self, forKey: key),
			                                           op: .missing))
		case "=", "≠", "!=":
			let pair = try container.decode([String].self, forKey: key)
			guard pair.count == 2 else {
				throw QuestError.malformedFilterTree
			}
			self = .condition(QuestFilterCondition(key: pair[0],
			                                       op: key.stringValue == "=" ? .equals : .notEquals,
			                                       value: pair[1]))
		default:
			throw QuestError.malformedFilterTree
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: QuestFilterNodeKey.self)
		switch self {
		case let .group(group):
			try container.encode(group.children, forKey: QuestFilterNodeKey(group.op.jsonKey))
		case let .condition(condition):
			switch condition.op {
			case .exists:
				try container.encode(condition.key, forKey: QuestFilterNodeKey("exists"))
			case .missing:
				try container.encode(condition.key, forKey: QuestFilterNodeKey("missing"))
			case .equals:
				try container.encode([condition.key, condition.value], forKey: QuestFilterNodeKey("="))
			case .notEquals:
				try container.encode([condition.key, condition.value], forKey: QuestFilterNodeKey("≠"))
			}
		}
	}
}

extension QuestFilterGroup: Codable {
	init(from decoder: Decoder) throws {
		guard case let .group(group) = try QuestFilterNode(from: decoder) else {
			throw QuestError.malformedFilterTree
		}
		self.init(op: group.op, children: group.children)
	}

	func encode(to encoder: Encoder) throws {
		try QuestFilterNode.group(self).encode(to: encoder)
	}
}

// MARK: Predicate

extension QuestFilterCondition {
	/// Builds the test this condition applies to an object's tags.
	func makePredicate() throws -> ([String: String]) -> Bool {
		let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
		if key.isEmpty {
			throw QuestError.emptyKeyString
		}
		let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
		switch op {
		case .exists:
			return { $0[key] != nil }
		case .missing:
			return { $0[key] == nil }
		case .equals:
			if value.isEmpty {
				throw QuestError.emptyValueString
			}
			return { $0[key] == value }
		case .notEquals:
			if value.isEmpty {
				throw QuestError.emptyValueString
			}
			return { $0[key] != value }
		}
	}
}

extension QuestFilterGroup {
	/// Builds the combined test for this group. An empty AND group matches everything and an
	/// empty OR group matches nothing; callers decide whether an empty root is an error.
	func makePredicate() throws -> ([String: String]) -> Bool {
		let predicates = try children.map { child -> ([String: String]) -> Bool in
			switch child {
			case let .condition(condition): return try condition.makePredicate()
			case let .group(group): return try group.makePredicate()
			}
		}
		switch op {
		case .and: return { tags in predicates.allSatisfy { $0(tags) } }
		case .or: return { tags in predicates.contains { $0(tags) } }
		}
	}

	/// Trims whitespace from every key and value, as done before saving.
	mutating func trimWhitespace() {
		children = children.map { child in
			switch child {
			case var .condition(condition):
				condition.key = condition.key.trimmingCharacters(in: .whitespacesAndNewlines)
				condition.value = condition.value.trimmingCharacters(in: .whitespacesAndNewlines)
				return .condition(condition)
			case var .group(group):
				group.trimWhitespace()
				return .group(group)
			}
		}
	}
}

// MARK: Textual representation

extension QuestFilterCondition {
	/// Textual form such as "highway=residential" or "lit missing". Blank fields show as "?".
	var expressionText: String {
		let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
		let keyText = key.isEmpty ? "?" : key
		switch op {
		case .equals, .notEquals:
			let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
			let valueText = value.isEmpty ? "?" : value
			return "\(keyText)\(op.localizedTitle)\(valueText)"
		case .exists, .missing:
			return "\(keyText) \(op.localizedTitle)"
		}
	}
}

extension QuestFilterGroup {
	/// The boolean expression the tree represents, with nested groups in parentheses,
	/// e.g. "lit missing AND (highway=residential OR (highway=path AND foot=designated))".
	/// Empty for an empty tree.
	var expressionText: String {
		let parts = children.compactMap { child -> String? in
			switch child {
			case let .condition(condition):
				return condition.expressionText
			case let .group(group):
				if group.children.isEmpty {
					return nil
				}
				let text = group.expressionText
				// A group with a single child doesn't need parentheses
				return group.children.count > 1 ? "(\(text))" : text
			}
		}
		return parts.joined(separator: " \(op.localizedTitle) ")
	}
}

// MARK: Conversion to and from the legacy flat filter list

private extension QuestDefinitionFilter.Relation {
	var inverted: QuestDefinitionFilter.Relation {
		switch self {
		case .equal: return .notEqual
		case .notEqual: return .equal
		}
	}
}

extension QuestFilterCondition {
	/// Interprets a legacy filter, resolving its value conventions: an empty value means the key
	/// is missing and "*" means it exists. The include/exclude flag is ignored; callers fold it
	/// into the relation first.
	init(legacy filter: QuestDefinitionFilter) {
		switch (filter.relation, filter.tagValue) {
		case (.equal, ""), (.notEqual, "*"):
			self.init(key: filter.tagKey, op: .missing)
		case (.equal, "*"), (.notEqual, ""):
			self.init(key: filter.tagKey, op: .exists)
		case (.equal, _):
			self.init(key: filter.tagKey, op: .equals, value: filter.tagValue)
		case (.notEqual, _):
			self.init(key: filter.tagKey, op: .notEquals, value: filter.tagValue)
		}
	}
}

extension QuestFilterGroup {
	/// Which flat filters get ORed together when converting to a tree.
	private enum Bucket: Equatable {
		case key(String) // "=" conditions sharing a key
		case missingEditKey // "=" conditions for a missing editKey
		case standalone // never merged with anything else
	}

	/// Builds a tree equivalent to a legacy flat filter list, following the grouping rules the old
	/// predicate builder used: "=" conditions that share a key are ORed together (as are several
	/// missing editKeys), and everything else is ANDed. Used for quests saved before the tree
	/// existed, and for quests whose tree this version can't read.
	init(filters: [QuestDefinitionFilter], editKeys: [String]) {
		// Fold include/exclude into the relation, since "exclude key=value" means the same as "key≠value".
		let normalized = filters.map { filter -> QuestDefinitionFilter in
			switch filter.included {
			case .include:
				return filter
			case .exclude:
				return QuestDefinitionFilter(tagKey: filter.tagKey,
				                             tagValue: filter.tagValue,
				                             relation: filter.relation.inverted,
				                             included: .include)
			}
		}

		// Collect conditions into buckets, preserving the order in which each bucket first appears.
		var buckets: [(bucket: Bucket, items: [QuestDefinitionFilter])] = []
		for filter in normalized {
			let bucket: Bucket
			switch filter.relation {
			case .equal:
				if filter.tagValue == "", editKeys.contains(filter.tagKey) {
					bucket = .missingEditKey
				} else {
					bucket = .key(filter.tagKey)
				}
			case .notEqual:
				bucket = .standalone
			}
			if bucket != .standalone,
			   let index = buckets.firstIndex(where: { $0.bucket == bucket })
			{
				buckets[index].items.append(filter)
			} else {
				buckets.append((bucket, [filter]))
			}
		}

		let children = buckets.map { entry -> QuestFilterNode in
			let conditions = entry.items.map { QuestFilterNode.condition(QuestFilterCondition(legacy: $0)) }
			if conditions.count == 1 {
				return conditions[0]
			}
			return .group(QuestFilterGroup(op: .or, children: conditions))
		}
		self.init(op: .and, children: children)
	}
}
