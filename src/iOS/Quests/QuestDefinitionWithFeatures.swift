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
	var ident = ""
	var title: String // "Add Surface" or similar
	var label: String // single character displayed in MapMarkerButton
	var tagKey: String // "surface"
	var includeFeatures: [String] // list of featureID
	var accepts: ((String) -> Bool)?

	init(ident: String = "",
	     title: String,
	     label: String,
	     tagKey: String,
	     includeFeatures: [String],
	     accepts: ((String) -> Bool)? = nil)
	{
		self.ident = ident
		self.title = title
		self.label = label
		self.tagKey = tagKey
		self.includeFeatures = includeFeatures
		self.accepts = accepts
	}

	// MARK: Codable

	private enum CodingKeys: String, CodingKey {
		// We don't encode ident or accept for now
		case title
		case label
		case tagKey
		case presetKey // alias for tagKey
		case includeFeatures
	}

	init(from decoder: Decoder) throws {
		do {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			title = try container.decode(String.self, forKey: .title)
			label = try container.decode(String.self, forKey: .label)
			tagKey = try (try? container.decode(String.self, forKey: .presetKey))
				?? container.decode(String.self, forKey: .tagKey)
			includeFeatures = try container.decode([String].self, forKey: .includeFeatures)
		} catch {
			print("\(error)")
			throw error
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(title, forKey: .title)
		try container.encode(label, forKey: .label)
		try container.encode(tagKey, forKey: .tagKey)
		try container.encode(includeFeatures, forKey: .includeFeatures)
	}

	// MARK: makeQuestInstance

	private static func makeInstanceWith(
		ident: String,
		title: String,
		label: String,
		tagKey: String, // The value the user is being asked to set
		// The set of features the user is interested in (everything if empty)
		includeFeaturePresets: [PresetFeature],
		accepts: @escaping ((String) -> Bool))
		-> QuestInstance // This is acceptance criteria for a value the user typed in
	{
		guard !includeFeaturePresets.isEmpty else { fatalError() }

		let includeFunc = Self.predicateFor(features: includeFeaturePresets)
		let applies: (OsmBaseObject) -> Bool = { obj in
			// we ignore geometry currently, but probably will need to handle it in the future
			let tags = obj.tags
			return tags[tagKey] == nil && includeFunc(tags)
		}

		return QuestInstance(ident: ident,
		                     title: title,
		                     label: label,
		                     tagKeys: [tagKey],
		                     appliesToObject: applies,
		                     acceptsValue: accepts)
	}

	private static func makeInstanceWith(ident: String,
	                                     title: String,
	                                     label: String,
	                                     tagKey: String, // The value the user is being asked to set
	                                     includeFeatures: [String],
	                                     // The set of features the user is interested in (everything if empty)
	                                     accepts: ((String) -> Bool)? =
	                                     	nil // This is acceptance criteria for a value the user typed in
	) throws -> QuestInstance {
		if label.count != 1,
		   !label.hasPrefix("ic_quest_")
		{
			throw QuestError.illegalLabel(label)
		}

		// If the user didn't define any features then infer them
		var includeFeatures = includeFeatures
		if includeFeatures.isEmpty {
			includeFeatures = try Self.featuresContaining(presetKey: tagKey, more: false)
		}

		let include = try includeFeatures.map {
			guard let feature = PresetsDatabase.shared.stdFeatures[$0] else { throw QuestError.unknownFeature($0) }
			return feature
		}

		return Self.makeInstanceWith(ident: ident,
		                             title: title,
		                             label: label,
		                             tagKey: tagKey,
		                             includeFeaturePresets: include,
		                             accepts: accepts ?? { !$0.isEmpty })
	}

	private static func makeInstanceWith(presetFeatures quest: QuestDefinitionWithFeatures) throws -> QuestInstance {
		return try makeInstanceWith(ident: quest.title,
		                            title: quest.title,
		                            label: quest.label,
		                            tagKey: quest.tagKey,
		                            includeFeatures: quest.includeFeatures)
	}

	// Use a set of features to build a function that filters for those features
	static func predicateFor(features: [PresetFeature]) -> (([String: String]) -> Bool) {
		return Self.getMatchFunc(features.map { $0.tags })
	}

	// Compute a function that determines whether a given tag dictionary matches the feature(s) of the quest
	private static func getMatchFunc(_ featureList: [[String: String]]) -> (([String: String]) -> Bool) {
		if featureList.isEmpty {
			return { _ in false }
		}

		// build a dictionary of tags that must match
		var matchDict: [String: [[String: String]]] = [:]
		for feature in featureList {
			for key in feature.keys {
				if matchDict[key]?.append(feature) == nil {
					matchDict[key] = [feature]
				}
			}
		}

		// check whether candidate object matches all tags in feature
		@inline(__always)
		func matchTagsOf(candidate: [String: String], to feature: [String: String]) -> Bool {
			// check whether candidate object matches all tags in feature
			for kv in feature {
				guard let value = candidate[kv.key],
				      value == kv.value || kv.value == "*"
				else {
					return false
				}
			}
			return true
		}

		return { candidate in
			for key in candidate.keys {
				guard let features = matchDict[key] else { continue }
				for feature in features {
					if matchTagsOf(candidate: candidate, to: feature) {
						return true
					}
				}
			}
			return false
		}
	}

	static func featuresContaining(presetKey: String, more: Bool) throws -> [String] {
		// find all features containing the desired field
		let featureNames = PresetsDatabase.shared.stdFeatures.values.compactMap {
			$0.fieldContainingTagKey(presetKey, more: more) != nil ? $0.featureID : nil
		}
		if featureNames.isEmpty {
			throw QuestError.unknownKey(presetKey)
		}
		return featureNames
	}

	func makeQuestInstance() throws -> QuestProtocol {
		return try Self.makeInstanceWith(presetFeatures: self)
	}
}
