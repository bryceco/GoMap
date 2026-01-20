//
//  PresetDisplayForFeature.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// All presets for a feature, for presentation in Common Tags table view
final class PresetDisplayForFeature {
	let featureName: String
	private(set) var sectionList: [PresetDisplayGroup]

	private class func forEachPresetKeyInGroup(_ group: PresetKeyOrGroup, closure: (PresetDisplayKey) -> Void) {
		switch group {
		case let .group(subgroup):
			for g in subgroup.presetKeys {
				forEachPresetKeyInGroup(g, closure: closure)
			}
		case let .key(preset):
			closure(preset)
		}
	}

	func forEachPresetKey(_ closure: (PresetDisplayKey) -> Void) {
		for section in sectionList {
			for g in section.presetKeys {
				Self.forEachPresetKeyInGroup(g, closure: closure)
			}
		}
	}

	func allPresetKeys() -> [PresetDisplayKey] {
		var list: [PresetDisplayKey] = []
		forEachPresetKey({ list.append($0) })
		return list
	}

	func sectionCount() -> Int {
		return sectionList.count
	}

	func tagsInSection(_ index: Int) -> Int {
		let group = sectionList[index]
		return group.presetKeys.count
	}

	func presetAtSection(_ section: Int, row: Int) -> PresetKeyOrGroup {
		let group = sectionList[section]
		let tag = group.presetKeys[row]
		return tag
	}

	func presetAtIndexPath(_ indexPath: IndexPath) -> PresetKeyOrGroup {
		return presetAtSection(indexPath.section, row: indexPath.row)
	}

	class func fieldsFor(featureID: String,
	                     field fieldGetter: @escaping (_ feature: PresetFeature) -> [String]?) -> [String]
	{
		guard let fields = PresetsDatabase.shared
			.inheritedValueOfFeature(featureID, fieldGetter: fieldGetter) as? [String]
		else { return [] }

		var list = [String]()
		for field in fields {
			if field.hasPrefix("{"), field.hasSuffix("}") {
				// copy fields from referenced item
				let refFeature = String(field.dropLast().dropFirst())
				list += fieldsFor(featureID: refFeature, field: fieldGetter)
			} else {
				list.append(field)
			}
		}
		return list
	}

	private func addPresetsForFieldNames(
		fields: [String],
		sort: Bool,
		objectTags: [String: String],
		geometry: GEOMETRY,
		ignore: [String],
		dupSet: inout Set<String>,
		update: (() -> Void)?)
	{
		for field in fields {
			if dupSet.contains(field) {
				continue
			}
			_ = dupSet.insert(field)

			guard let group = PresetsDatabase.shared.presetGroupForField(
				fieldName: field,
				objectTags: objectTags,
				geometry: geometry,
				countryCode: AppDelegate.shared.mainView.currentRegion.country,
				ignore: ignore,
				update: update)
			else {
				continue
			}

			// if both this group and the previous don't have a name then merge them
			if group.name == nil || group.isDrillDown, sectionList.count > 1 {
				var prev = sectionList.last!
				if prev.name == nil {
					prev = PresetDisplayGroup(fromMerger: prev, with: group, sort: sort)
					sectionList.removeLast()
					sectionList.append(prev)
					continue
				}
			}
			sectionList.append(group)
		}
	}

	func addPresetsForFields(
		inFeatureID featureID: String,
		objectTags: [String: String],
		geometry: GEOMETRY,
		field fieldGetter: @escaping (_ feature: PresetFeature) -> [String]?,
		ignore: [String],
		dupSet: inout Set<String>,
		update: (() -> Void)?)
	{
		let fields = PresetDisplayForFeature.fieldsFor(featureID: featureID, field: fieldGetter)
		addPresetsForFieldNames(
			fields: fields,
			sort: false,
			objectTags: objectTags,
			geometry: geometry,
			ignore: ignore,
			dupSet: &dupSet,
			update: update)
	}

	init(withFeature feature: PresetFeature?, // feature == nil if a new object
	     objectTags: [String: String],
	     geometry: GEOMETRY,
	     update: (() -> Void)?)
	{
		featureName = feature?.localizedName ?? ""

		// Always start with Type and Name
		let typeTag = PresetDisplayKey(
			name: NSLocalizedString("Type", comment: "The 'Type' header in Common Tags"),
			type: .featureType,
			tagKey: "",
			defaultValue: nil,
			placeholder: "",
			keyboard: UIKeyboardType.default,
			capitalize: UITextAutocapitalizationType.none,
			autocorrect: UITextAutocorrectionType.no,
			presetValues: nil)
		let nameField = PresetsDatabase.shared.presetFields["name"]!
		let nameTag = PresetDisplayKey(
			name: nameField.localizedLabel ?? "Name",
			type: .text,
			tagKey: "name",
			defaultValue: nil,
			placeholder: nameField.localizedPlaceholder,
			keyboard: UIKeyboardType.default,
			capitalize: UITextAutocapitalizationType.words,
			autocorrect: UITextAutocorrectionType.no,
			presetValues: nil)
		let typeGroup = PresetDisplayGroup(name: "Type", tags: [.key(typeTag), .key(nameTag)], usesBoth: false)
		sectionList = [typeGroup]

		// Add user-defined presets
		var customGroup: [PresetKeyOrGroup] = []
		for custom in PresetKeyUserDefinedList.shared.list {
			if custom.appliesToKey == "" {
				// accept all
			} else if let v = objectTags[custom.appliesToKey] {
				if custom.appliesToValue == "" || v == custom.appliesToValue {
					// accept
				} else {
					continue
				}
			} else {
				continue
			}
			customGroup.append(.key(custom))
		}
		if customGroup.count != 0 {
			let group = PresetDisplayGroup(name: nil, tags: customGroup, usesBoth: false)
			sectionList.append(group)
		}

		// Add presets specific to the type
		guard let feature = feature else {
			// all done
			return
		}
		var dupSet = Set<String>()
		let ignoreTags = Array(feature.tags.keys)
		addPresetsForFields(
			inFeatureID: feature.featureID,
			objectTags: objectTags,
			geometry: geometry,
			field: { f in f.fields },
			ignore: ignoreTags,
			dupSet: &dupSet,
			update: update)

		// Create a break between the common items and the rare items
		sectionList.append(PresetDisplayGroup(name: nil,
		                                      tags: [PresetKeyOrGroup](),
		                                      usesBoth: false))

		// add moreFields fields
		let fields = PresetDisplayForFeature.fieldsFor(featureID: feature.featureID, field: { f in f.moreFields })
		addPresetsForFieldNames(
			fields: fields,
			sort: false,
			objectTags: objectTags,
			geometry: geometry,
			ignore: ignoreTags,
			dupSet: &dupSet,
			update: update)

		// Create a break before universal items
		sectionList.append(PresetDisplayGroup(name: nil,
		                                      tags: [PresetKeyOrGroup](),
		                                      usesBoth: false))

		// add universal fields
		let uni = PresetsDatabase.shared.presetFields.compactMap({ k, v in v.universal ? k : nil })
		addPresetsForFieldNames(
			fields: uni,
			sort: true,
			objectTags: objectTags,
			geometry: geometry,
			ignore: ignoreTags,
			dupSet: &dupSet,
			update: update)
	}
}
