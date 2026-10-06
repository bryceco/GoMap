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

/// A quest protocol is something that filters OSM objects and displays a marker for them

protocol QuestProtocol {
	var ident: String { get }
	var title: String { get }
	var label: String { get }
	var editKeys: [String] { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
	func accepts(tagValue: String) -> Bool
}

extension QuestProtocol {
	static func isImage(label: String) -> Bool {
		return label.hasPrefix("ic_quest_")
	}

	static func isCharacter(label: String) -> Bool {
		return label.count == 1
	}
}

// A quest instance is a concrete QuestProtocol

class QuestInstance: QuestProtocol {
	// These items define the quest
	let ident: String // Uniquely identify the quest
	let title: String // Localized instructions on what action to take
	let label: String // The emoji/character/image used on the quest pin
	let editKeys: [String] // The value the user is being asked to set
	let appliesToObject: (OsmBaseObject) -> Bool
	let acceptsValue: (String) -> Bool

	func appliesTo(_ object: OsmBaseObject) -> Bool {
		return appliesToObject(object)
	}

	func accepts(tagValue: String) -> Bool {
		return acceptsValue(tagValue)
	}

	init(ident: String,
	     title: String,
	     label: String,
	     editKeys: [String],
	     appliesToObject: @escaping (OsmBaseObject) -> Bool,
	     acceptsValue: @escaping (String) -> Bool)
	{
		self.ident = ident
		self.title = title
		self.label = label
		self.editKeys = editKeys
		self.appliesToObject = appliesToObject
		self.acceptsValue = acceptsValue
	}
}

enum QuestError: LocalizedError {
	case unknownKey(String)
	case unknownFeature(String)
	case illegalLabel(String)
	case noFiltersDefined
	case emptyKeyString
	case emptyValueString
	case malformedFilterTree

	public var errorDescription: String? {
		switch self {
		case let .unknownKey(text):
			return String(format: NSLocalizedString("The tag key '%@' is not referenced by any features",
			                                        comment: "Quest validation error"), text)
		case let .unknownFeature(text):
			return String(format: NSLocalizedString("The feature '%@' does not exist",
			                                        comment: "Quest validation error"), text)
		case let .illegalLabel(text):
			return String(format: NSLocalizedString("The quest label '%@' must be a single character",
			                                        comment: "Quest validation error"), text)
		case .noFiltersDefined:
			return NSLocalizedString("No filters are defined for the quest",
			                         comment: "Quest validation error")
		case .emptyKeyString:
			return NSLocalizedString("Empty tag key is not permitted",
			                         comment: "Quest validation error")
		case .emptyValueString:
			return NSLocalizedString("Empty tag value is not permitted",
			                         comment: "Quest validation error")
		case .malformedFilterTree:
			return NSLocalizedString("The quest filter is malformed",
			                         comment: "Quest validation error")
		}
	}
}
