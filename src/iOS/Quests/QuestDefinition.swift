//
//  QuestDefinition.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/8/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

protocol QuestProtocol {
	var ident: String { get }
	var title: String { get }
	var icon: UIImage? { get }
	var presetField: PresetField { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
	func accepts(tagValue: String) -> Bool
}

enum QuestError: Error {
	case unknownField(String)
	case unknownFeature(String)
}

struct QuestHighwaySurface: QuestProtocol {
	var ident: String { "QuestHighwaySurface" }
	var title: String { "Highway surface" }
	var tagKey: String { "surface" }
	var icon: UIImage? { nil }
	var presetField: PresetField

	func appliesTo(_ object: OsmBaseObject) -> Bool {
		if let way = object as? OsmWay,
		   way.tags["highway"] != nil,
		   way.tags["surface"] == nil
		{
			return true
		}
		return false
	}

	func accepts(tagValue: String) -> Bool {
		return !tagValue.isEmpty
	}
}

class QuestDefinition: QuestProtocol {
	// These items define the quest
	let ident: String // Uniquely identify the quest
	let title: String // This provides additional instructions on what action to take
	let icon: UIImage?
	let presetField: PresetField // The value the user is being asked to set
	let appliesToGeometry: [GEOMETRY]
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
		 icon: UIImage?,
		 presetField: PresetField,
		 appliesToGeometry: [GEOMETRY],
		 appliesToObject: @escaping (OsmBaseObject) -> Bool,
		 acceptsValue: @escaping (String) -> Bool)
	{
		self.ident = ident
		self.title = title
		self.icon = icon
		self.presetField = presetField
		self.appliesToGeometry = appliesToGeometry
		self.appliesToObject = appliesToObject
		self.acceptsValue = acceptsValue
	}

	convenience init(ident: String,
					 title: String,
					 icon: UIImage,
					 presetField: PresetField, // The value the user is being asked to set
					 // The set of features the user is interested in (everything if empty)
					 appliesToGeometry: [GEOMETRY],
					 includeFeatures: [PresetFeature],
					 excludeFeatures: [PresetFeature], // The set of features to exclude
					 accepts: @escaping ((String) -> Bool)) // This is acceptance criteria for a value the user typed in
	{
		typealias Validator = (OsmBaseObject) -> Bool

		let geomFunc: Validator = appliesToGeometry.isEmpty ? { _ in true } : { obj in
			appliesToGeometry.contains(obj.geometry())
		}
		let includeFunc = Self.getMatchFunc(includeFeatures.map { $0.tags })
		let excludeFunc = Self.getMatchFunc(excludeFeatures.map { $0.tags })
		let tagKey = presetField.key ?? presetField.keys![0] // FIXME: support multiple keys
		let applies: Validator = { obj in
			obj.tags[tagKey] == nil &&
			includeFunc(obj.tags) && !excludeFunc(obj.tags) && geomFunc(obj)
		}
		self.init(ident: ident,
				  title: title,
				  icon: icon,
				  presetField: presetField,
				  appliesToGeometry: appliesToGeometry,
				  appliesToObject: applies,
				  acceptsValue: accepts)
	}

	static func getMatchFunc(_ featureList: [[String: String]]) -> (([String: String]) -> Bool) {
		if featureList.isEmpty {
			return { _ in false }
		}
		return { candidate in
			// iterate through array of features
			for feature in featureList {
				// check whether candidate object matches all tags in feature
				var matches = true
				for kv in feature {
					guard let value = candidate[kv.key],
						  value == kv.value || kv.value == "*"
					else {
						matches = false
						break
					}
				}
				if matches {
					return true
				}
			}
			return false
		}
	}

	convenience
	init(ident: String,
		 title: String,
		 icon: UIImage,
		 presetField: String, // The value the user is being asked to set
		 appliesToGeometry: [GEOMETRY],
		 includeFeatures: [String], // The set of features the user is interested in (everything if empty)
		 excludeFeatures: [String], // The set of features to exclude
		 accepts: ((String) -> Bool)? = nil // This is acceptance criteria for a value the user typed in
	) throws {
		guard let presetFieldRef = PresetsDatabase.shared.presetFields[presetField] else {
			throw QuestError.unknownField(presetField)
		}

		// If the user didn't define any features then infer them
		var includeFeatures = includeFeatures
		if includeFeatures.isEmpty {
			includeFeatures = Self.featuresContaining(field: presetField, geometry: appliesToGeometry)
		}

		let include = try includeFeatures.map {
			guard let feature = PresetsDatabase.shared.stdPresets[$0] else { throw QuestError.unknownFeature($0) }
			return feature
		}
		let exclude = try excludeFeatures.map {
			guard let feature = PresetsDatabase.shared.stdPresets[$0] else { throw QuestError.unknownFeature($0) }
			return feature
		}

		self.init(ident: ident,
				  title: title,
				  icon: icon,
				  presetField: presetFieldRef,
				  appliesToGeometry: appliesToGeometry,
				  includeFeatures: include,
				  excludeFeatures: exclude,
				  accepts: accepts ?? { _ in true })
	}

	static func featuresContaining(field: String, geometry: [GEOMETRY]) -> [String] {
		// find all features containing the desired field
		var featureNames = Set<String>()
		let appliesToGeometrySet = Set(geometry.map { $0.rawValue })
		for feature in PresetsDatabase.shared.stdPresets.values {
			if !feature.geometry.isEmpty,
			   !appliesToGeometrySet.isEmpty,
			   appliesToGeometrySet.intersection(feature.geometry).isEmpty
			{
				continue
			}
			guard feature.fields?.contains(field) ?? false
			else { continue }
			featureNames.insert(feature.featureID)
		}
		return Array(featureNames)
	}
}
