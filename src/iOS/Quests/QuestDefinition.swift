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
	var tagKeys: [String] { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
	func accepts(tagValue: String) -> Bool
}

// A quest instance is a concrete QuestProtocol

class QuestInstance: QuestProtocol {
	// These items define the quest
	let ident: String // Uniquely identify the quest
	let title: String // Localized instructions on what action to take
	let label: String
	let tagKeys: [String] // The value the user is being asked to set
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
	     tagKeys: [String],
	     appliesToObject: @escaping (OsmBaseObject) -> Bool,
	     acceptsValue: @escaping (String) -> Bool)
	{
		self.ident = ident
		self.title = title
		self.label = label
		self.tagKeys = tagKeys
		self.appliesToObject = appliesToObject
		self.acceptsValue = acceptsValue
	}
}

enum QuestError: LocalizedError {
	case unknownKey(String)
	case unknownFeature(String)
	case noStringEquivalent
	case illegalLabel(String)
	case noFiltersDefined
	case unrecognizedUserDefinitionType
	case emptyKeyString

	public var errorDescription: String? {
		switch self {
		case let .unknownKey(text): return "The tag key '\(text)' is not referenced by any features"
		case let .unknownFeature(text): return "The feature '\(text)' does not exist"
		case .noStringEquivalent: return "Unable to convert the data to string"
		case let .illegalLabel(text): return "The quest label '\(text)' must be a single character"
		case .unrecognizedUserDefinitionType: return "A quest definition is of an unrecognized type"
		case .noFiltersDefined: return "No filters are defined for the quest"
		case .emptyKeyString: return "Empty tag key is not permitted"
		}
	}
}
