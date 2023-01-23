//
//  PresetsForFeature.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// All presets for a feature, for presentation in Common Tags table view
final class PresetsForFeature {
	var _featureName: String
	var _sectionList: [PresetGroup]

	func featureName() -> String {
		return _featureName
	}

	private class func forEachPresetKeyInGroup(_ group: PresetKeyOrGroup, closure: (PresetKey) -> Void) {
		switch group {
		case let .group(subgroup):
			for g in subgroup.presetKeys {
				forEachPresetKeyInGroup(g, closure: closure)
			}
		case let .key(preset):
			closure(preset)
		}
	}

	func forEachPresetKey(_ closure: (PresetKey) -> Void) {
		for section in _sectionList {
			for g in section.presetKeys {
				Self.forEachPresetKeyInGroup(g, closure: closure)
			}
		}
	}

	func allPresetKeys() -> [PresetKey] {
		var list: [PresetKey] = []
		forEachPresetKey({ list.append($0) })
		return list
	}

	func sectionCount() -> Int {
		return _sectionList.count
	}

	func tagsInSection(_ index: Int) -> Int {
		let group = _sectionList[index]
		return group.presetKeys.count
	}

	func sectionAtIndex(_ index: Int) -> PresetGroup {
		return _sectionList[index]
	}

	func presetAtSection(_ section: Int, row: Int) -> PresetKeyOrGroup {
		let group = _sectionList[section]
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

	func addPresetsForFields(
		inFeatureID featureID: String,
		objectTags: [String: String],
		geometry: GEOMETRY,
		field fieldGetter: @escaping (_ feature: PresetFeature) -> [String]?,
		ignore: [String],
		dupSet: inout Set<String>,
		update: (() -> Void)?)
	{
		let fields = PresetsForFeature.fieldsFor(featureID: featureID, field: fieldGetter)

		for field in fields {
			if dupSet.contains(field) {
				continue
			}
			_ = dupSet.insert(field)

			guard let group = PresetsDatabase.shared.presetGroupForField(
				fieldName: field,
				objectTags: objectTags,
				geometry: geometry,
				countryCode: AppDelegate.shared.mapView.currentRegion.country,
				ignore: ignore,
				update: update)
			else {
				continue
			}
			// if both this group and the previous don't have a name then merge them
			if group.name == nil || group.isDrillDown, _sectionList.count > 1 {
				var prev = _sectionList.last!
				if prev.name == nil {
					prev = PresetGroup(fromMerger: prev, with: group)
					_sectionList.removeLast()
					_sectionList.append(prev)
					continue
				}
			}
			_sectionList.append(group)
		}
	}

	init(withFeature feature: PresetFeature?, // feature == nil if a new object
	     objectTags: [String: String],
	     geometry: GEOMETRY,
	     update: (() -> Void)?)
	{
		_featureName = feature?.name ?? ""

		// Always start with Type and Name
		let typeTag = PresetKey(
			name: NSLocalizedString("Type", comment: "The 'Type' header in Common Tags"),
			type: "",
			tagKey: "",
			defaultValue: nil,
			placeholder: "",
			keyboard: UIKeyboardType.default,
			capitalize: UITextAutocapitalizationType.none,
			autocorrect: UITextAutocorrectionType.no,
			presets: nil)
		let nameField = PresetsDatabase.shared.presetFields["name"]!
		let nameTag = PresetKey(
			name: nameField.label ?? "Name",
			type: "",
			tagKey: "name",
			defaultValue: nil,
			placeholder: nameField.placeholder,
			keyboard: UIKeyboardType.default,
			capitalize: UITextAutocapitalizationType.words,
			autocorrect: UITextAutocorrectionType.no,
			presets: nil)
		let typeGroup = PresetGroup(name: "Type", tags: [.key(typeTag), .key(nameTag)])
		_sectionList = [typeGroup]

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
			let group = PresetGroup(name: nil, tags: customGroup)
			_sectionList.append(group)
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
		_sectionList
			.append(PresetGroup(name: nil,
			                    tags: [PresetKeyOrGroup]())) // Create a break between the common items and the rare items
		addPresetsForFields(
			inFeatureID: feature.featureID,
			objectTags: objectTags,
			geometry: geometry,
			field: { f in f.moreFields },
			ignore: ignoreTags,
			dupSet: &dupSet,
			update: update)
	}
}
