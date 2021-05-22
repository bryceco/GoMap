//
//  PresetsForFeature.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation


// All presets for a feature, for presentation in Common Tags table view
class PresetsForFeature: NSObject {
	var _featureName: String
	var _sectionList: [PresetGroup]

	@objc func featureName() -> String {
		return _featureName
	}

	@objc func sectionList() -> [PresetGroup] {
		return _sectionList
	}

	@objc func sectionCount() -> Int {
		return _sectionList.count
	}

	@objc func tagsInSection(_ index: Int) -> Int {
		let group = _sectionList[index]
		return group.presetKeys.count
	}

	@objc func groupAtIndex(_ index: Int) -> PresetGroup {
		return _sectionList[index]
	}

	@objc func presetAtSection(_ section: Int, row: Int) -> Any {
		let group = _sectionList[section]
		let tag = group.presetKeys[row]
		return tag
	}

	@objc func presetAtIndexPath(_ indexPath: IndexPath) -> Any {
		return presetAtSection( indexPath.section, row: indexPath.row)
	}

	class func fieldsFor(featureID:String, field fieldGetter: @escaping (_ feature: PresetFeature) -> [String]?) -> [String]
	{
		guard let fields = PresetsDatabase.shared.inheritedValueOfFeature(featureID, fieldGetter:fieldGetter) as? [String]
		else { return [] }

		var list = [String]()
		for field in fields {
			if field.hasPrefix("{") && field.hasSuffix("}") {
				// copy fields from referenced item
				let refFeature = String(field.dropLast().dropFirst())
				list += fieldsFor(featureID: refFeature, field: fieldGetter)
			} else {
				list.append( field )
			}
		}
		return list
	}

	func addPresetsForFields(
		inFeatureID featureID: String,
		geometry: String,
		field fieldGetter: @escaping (_ feature: PresetFeature) -> [String]?,
		ignore: [String],
		dupSet: inout Set<String>,
		update: (() -> Void)?
	) {
		let fields = PresetsForFeature.fieldsFor(featureID:featureID, field:fieldGetter)

		for field in fields {

			if dupSet.contains(field) {
				continue
			}
			_ = dupSet.insert(field)

			guard let group = PresetsDatabase.shared.groupForField( fieldName: field, geometry: geometry, ignore: ignore, update: update)
			else {
				continue
			}
			// if both this group and the previous don't have a name then merge them
			if (group.name == nil || group.isDrillDown) && _sectionList.count > 1 {
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

	init(withFeature feature:PresetFeature?,	// feature == nil if a new object
			   objectTags: [String : String],
			   geometry: String,
			   update: (() -> Void)?)
	{
		_featureName = feature?.name ?? ""

		// Always start with Type and Name
		let typeTag = PresetKey(
				name: "Type",
				tagKey: "",
				defaultValue: nil,
				placeholder: "",
				keyboard: UIKeyboardType.default,
				capitalize: UITextAutocapitalizationType.none,
				presets: nil)
		let name = PresetsDatabase.shared.jsonFields["name"] as? [AnyHashable:Any]
		let nameTag = PresetKey(
				name: name?["label"] as? String ?? "Name",
				tagKey: "name",
				defaultValue: nil,
				placeholder: name?["placeholder"] as? String,
				keyboard: UIKeyboardType.default,
				capitalize: UITextAutocapitalizationType.words,
				presets:nil)
		let typeGroup = PresetGroup(name: "Type", tags: [typeTag, nameTag].compactMap { $0 })
		_sectionList = [typeGroup]

		// Add user-defined presets
		var customGroup: [AnyHashable] = []
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
			customGroup.append(custom)
		}
		if customGroup.count != 0 {
			let group = PresetGroup(name: nil, tags: customGroup)
			_sectionList.append(group)
		}

		super.init()

		// Add presets specific to the type
		guard let feature = feature else {
			// all done
			return
		}
		var dupSet = Set<String>()
		let ignoreTags = Array(feature.tags.keys)
		addPresetsForFields(
			inFeatureID: feature.featureID,
			geometry: geometry,
			field: { f in return f.fields },
			ignore: ignoreTags,
			dupSet: &dupSet,
			update: update)
		_sectionList.append(PresetGroup(name: nil, tags: [String]())) // Create a break between the common items and the rare items
		addPresetsForFields(
			inFeatureID: feature.featureID,
			geometry: geometry,
			field: { f in return f.moreFields },
			ignore: ignoreTags,
			dupSet: &dupSet,
			update: update)
	}
}
