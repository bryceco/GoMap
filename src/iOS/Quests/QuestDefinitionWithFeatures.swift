//
//  QuestDefinitionWithFeatures.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/21/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation


// MARK: Quest with features

struct QuestDefinitionWithFeatures: QuestDefinition {
	var title: String // "Add Surface" or similar
	var label: String // single character displayed in MapMarkerButton
	var presetKey: String // "surface"
	var includeFeatures: [String] // list of featureID

	func makeQuestInstance() throws -> QuestProtocol {
		return try QuestInstanceWithFeatures(presetFeatures: self)
	}
}
