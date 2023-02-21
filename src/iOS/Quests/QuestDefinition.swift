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
