//
//  PresetsDatabase+TableView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

enum PresetFeatureOrCategory {
	case category(PresetCategory)
	case feature(PresetFeature)
}

// Methods used to generate a UITableView
extension PresetsDatabase {
	func featuresAndCategoriesForGeometry(_ geometry: GEOMETRY) -> [PresetFeatureOrCategory] {
		let list = presetDefaults[geometry.rawValue]!
		let featureList = featuresAndCategoriesForMemberList(memberList: list)
		return featureList
	}

	func featuresInCategory(_ category: PresetCategory?,
	                        matching searchText: String,
	                        geometry: GEOMETRY,
	                        location: RegionInfoForLocation) -> [PresetFeature]
	{
		var list = [(feature: PresetFeature, score: Int)]()
		if let category = category {
			for feature in category.members {
				if let score = feature.matchesSearchText(searchText, geometry: geometry) {
					list.append((feature, score))
				}
			}
		} else {
			list = Self.shared.featuresMatchingSearchText(
				searchText,
				geometry: geometry,
				location: location)
		}
		list.sort(by: { obj1, obj2 -> Bool in
			if obj1.score != obj2.score {
				// higher score comes first
				return obj1.score > obj2.score
			}

			// prefer exact matches of primary name over alternate terms
			let feature1 = obj1.feature
			let feature2 = obj2.feature
			let diff = (feature1.nsiSuggestion ? 1 : 0) - (feature2.nsiSuggestion ? 1 : 0)
			if diff != 0 {
				return diff < 0
			}

			let name1 = feature1.friendlyName()
			let name2 = feature2.friendlyName()
			return name1.caseInsensitiveCompare(name2) == .orderedAscending
		})
		return list.map({ $0.feature })
	}

	func allTagKeys() -> Set<String> {
		var set = Set<String>()
		for field in presetFields.values {
			set.formUnion(field.allKeys)
		}
		PresetsDatabase.shared.enumeratePresetsUsingBlock({ feature in
			set.formUnion(feature.tags.keys)
		})
		// these are additionl tags that people might want (e.g. for autocomplete)
		set.formUnion(Set([
			"official_name",
			"alt_name",
			"short_name",
			"old_name",
			"reg_name",
			"nat_name",
			"loc_name"
		]))
		return set
	}

	func allTagValuesForKey(_ key: String) -> Set<String> {
		var set = Set<String>()
		for field in presetFields.values {
			if let k = field.key,
			   k == key,
			   let list = field.options
			{
				set.formUnion(list)
			}
		}
		Self.shared.enumeratePresetsUsingBlock({ feature in
			if let value = feature.tags[key] {
				set.insert(value)
			}
		})
		set.remove("*")
		return set
	}

	static let allFeatureKeysSet: Set<String> = {
		var set = Set<String>()
		PresetsDatabase.shared.enumeratePresetsUsingBlock({ feature in
			var key = feature.featureID
			if let range = key.range(of: "/") {
				key = String(key.prefix(upTo: range.lowerBound))
			}
			set.insert(key)
		})
		return set
	}()

	func allFeatureKeys() -> Set<String> {
		return Self.allFeatureKeysSet
	}

	static let autocompleteIgnoreList: [String: Bool] = [
		"capacity": true,
		"depth": true,
		"ele": true,
		"height": true,
		"housenumber": true,
		"lanes": true,
		"maxspeed": true,
		"maxweight": true,
		"scale": true,
		"step_count": true,
		"unit": true,
		"width": true
	]
	func eligibleForAutocomplete(_ key: String) -> Bool {
		if Self.autocompleteIgnoreList[key] != nil {
			return false
		}
		for (suffix, isSuffix) in Self.autocompleteIgnoreList {
			if isSuffix, key.hasSuffix(suffix), key.dropLast(suffix.count).hasSuffix(":") {
				return false
			}
		}
		return true
	}

	func featuresAndCategoriesForMemberList(memberList: [String]) -> [PresetFeatureOrCategory] {
		let list: [PresetFeatureOrCategory] = memberList.compactMap { featureID in
			if featureID.hasPrefix("category-"),
			   let cat = self.presetCategories[featureID]
			{
				return .category(cat)
			} else if let feature = Self.shared.presetFeatureForFeatureID(featureID) {
				return .feature(feature)
			}
			return nil
		}
		return list // list of PresetFeature or PresetCategory
	}

	private func commonPrefixOfMultiKeys(_ options: [String]) -> String {
		guard options.count > 0,
		      let index = options[0].lastIndex(of: ":")
		else {
			return ""
		}
		let prefix = options[0].prefix(through: index)
		for s in options[1...] {
			if !s.hasPrefix(prefix) {
				return ""
			}
		}
		return String(prefix)
	}

	// a list of keys with yes/no values
	func multiComboWith(
		label: String,
		keys: [String],
		options: [String],
		strings: [String: String]?,
		defaultValue: String?,
		placeholder: String?,
		keyboard: UIKeyboardType,
		capitalize: UITextAutocapitalizationType,
		autocorrect: UITextAutocorrectionType) -> PresetGroup
	{
		let prefix = commonPrefixOfMultiKeys(options)
		var tags: [PresetKeyOrGroup] = []
		for i in keys.indices {
			let name = strings?[options[i]] ?? OsmTags.PrettyTag(String(options[i].dropFirst(prefix.count)))
			let tag = yesNoWith(
				label: name,
				type: .check,
				key: keys[i],
				defaultValue: defaultValue,
				placeholder: nil,
				keyboard: keyboard,
				capitalize: capitalize,
				autocorrect: autocorrect)
			tags.append(.key(tag))
		}
		let group = PresetGroup(name: label, tags: tags, isDrillDown: true, usesBoth: false)
		let group2 = PresetGroup(name: nil, tags: [.group(group)], isDrillDown: true, usesBoth: false)
		return group2
	}

	// a preset value with a supplied list of potential values
	func comboWith(
		label: String,
		type: PresetType,
		key: String,
		options: [[String]],
		strings: [String: Any]?,
		icons: [String: String]?,
		defaultValue: String?,
		placeholder: String?,
		keyboard: UIKeyboardType,
		capitalize: UITextAutocapitalizationType,
		autocorrect: UITextAutocorrectionType) -> PresetKey
	{
		let presets: [PresetValue] = options.flatMap { optionList in
			optionList.map { value in
				if let strings = strings as? [String: String] {
					let name = strings[value] ?? OsmTags.PrettyTag(value)
					return PresetValue(name: name, details: nil, icon: icons?[value], tagValue: value)
				} else if let strings = strings as? [String: [String: String]] {
					let info = strings[value]
					let name = info?["title"] ?? OsmTags.PrettyTag(value)
					let desc = info?["description"] ?? ""
					return PresetValue(name: name, details: desc, icon: icons?[value], tagValue: value)
				} else {
					// print("missing strings definition: \(key)")
					let name = OsmTags.PrettyTag(value)
					return PresetValue(name: name, details: nil, icon: icons?[value], tagValue: value)
				}
			}
		}
		let tag = PresetKey(
			name: label,
			type: type,
			tagKey: key,
			defaultValue: defaultValue,
			placeholder: placeholder,
			keyboard: keyboard,
			capitalize: capitalize,
			autocorrect: autocorrect,
			presets: presets)
		return tag
	}

	// a yes/no preset
	func yesNoWith(
		label: String,
		type: PresetType,
		key: String,
		defaultValue: String?,
		placeholder: String?,
		keyboard: UIKeyboardType,
		capitalize: UITextAutocapitalizationType,
		autocorrect: UITextAutocorrectionType) -> PresetKey
	{
		let presets = [
			PresetValue(name: PresetTranslations.shared.yesForLocale, details: nil, icon: nil, tagValue: "yes"),
			PresetValue(name: PresetTranslations.shared.noForLocale, details: nil, icon: nil, tagValue: "no")
		]
		let tag = PresetKey(
			name: label,
			type: type,
			tagKey: key,
			defaultValue: defaultValue,
			placeholder: placeholder,
			keyboard: keyboard,
			capitalize: capitalize,
			autocorrect: autocorrect,
			presets: presets)
		return tag
	}

	func presetGroupForField(fieldName: String,
	                         objectTags: [String: String],
	                         geometry: GEOMETRY,
	                         countryCode: String,
	                         ignore: [String],
	                         update: (() -> Void)?) -> PresetGroup?
	{
		let field = presetFields[fieldName]!

		if let geoList = field.geometry {
			if !geoList.contains(geometry.rawValue) {
				return nil
			}
		}

		if let prerequisiteTag = field.prerequisiteTag {
			if let key = prerequisiteTag["key"] {
				guard let v = objectTags[key] else { return nil }
				if let value = prerequisiteTag["value"] {
					if v != value {
						return nil
					}
				} else if let valueNot = prerequisiteTag["valueNot"] {
					if v == valueNot {
						return nil
					}
				}
			} else if let keyNot = prerequisiteTag["keyNot"] {
				if objectTags[keyNot] != nil {
					return nil
				}
			} else {
				print("bad preset prerequisiteTag")
			}
		}

		// The locationSet test for presets uses only country codes,
		// while the locationSet for features is more general.
		if let locationSet = field.locationSet,
		   !locationSet.contains(countryCode: countryCode)
		{
			return nil
		}

		let key = field.key ?? fieldName
		let label = field.label ?? OsmTags.PrettyTag(key)

		switch field.type {
		case .defaultCheck, .check, .onewayCheck:
			let tag = yesNoWith(
				label: label,
				type: field.type,
				key: key,
				defaultValue: field.defaultValue,
				placeholder: field.placeholder,
				keyboard: .default,
				capitalize: .none,
				autocorrect: .no)
			let group = PresetGroup(name: nil, tags: [.key(tag)], usesBoth: false)
			return group

		case .radio, .structureRadio, .manyCombo, .multiCombo:
			// all of these can have multiple keys
			let isMultiCombo = field.type == .multiCombo // uses a prefix key with multiple suffixes

			var options = field.options
			if options == nil {
				// need to get options from taginfo
				options = taginfoCache.taginfoFor(key: key, searchKeys: isMultiCombo, update: update)
			} else if isMultiCombo {
				// prepend key: to options
				options = options!.map { k -> String in key + k }
			}

			if isMultiCombo || field.keys != nil {
				// a list of booleans
				let keys = (isMultiCombo ? options : field.keys) ?? []
				guard keys.count != 1 else {
					let option = options!.first!
					let name = field.strings?[option] ?? OsmTags.PrettyTag(option)
					let tag = yesNoWith(
						label: name,
						type: .check,
						key: keys.first!,
						defaultValue: field.defaultValue,
						placeholder: field.placeholder,
						keyboard: .default,
						capitalize: .none,
						autocorrect: .no)
					let group = PresetGroup(name: nil, tags: [.key(tag)], usesBoth: false)
					return group
				}
				let group = multiComboWith(label: label, keys: keys, options: options!, strings: field.strings,
				                           defaultValue: field.defaultValue, placeholder: field.placeholder,
				                           keyboard: .default, capitalize: .none, autocorrect: .no)
				return group
			} else {
				// a multiple selection
				let tag = comboWith(
					label: label,
					type: field.type,
					key: key,
					options: [options!],
					strings: field.strings,
					icons: field.icons,
					defaultValue: field.defaultValue,
					placeholder: field.placeholder,
					keyboard: .default,
					capitalize: .none,
					autocorrect: .no)
				let group = PresetGroup(name: nil, tags: [.key(tag)], usesBoth: false)
				return group
			}

		case .combo, .semiCombo, .networkCombo, .typeCombo, .colour:

			if field.type == .typeCombo, ignore.contains(key) {
				return nil
			}
			let options = field.options ?? []
			let options2 = taginfoCache.taginfoFor(key: key, searchKeys: false, update: update)
				.filter({ !options.contains($0) })
				.sorted()
			let tag = comboWith(
				label: label,
				type: field.type,
				key: key,
				options: [options, options2],
				strings: field.strings,
				icons: field.icons,
				defaultValue: field.defaultValue,
				placeholder: field.placeholder,
				keyboard: .default,
				capitalize: .none,
				autocorrect: .no)
			let group = PresetGroup(name: nil, tags: [.key(tag)], usesBoth: false)
			return group

		case .access, .directionalCombo: // "cycleway" is no longer used

			var tagList: [PresetKeyOrGroup] = []
			let types = field.types ?? [:]
			let strings = field.strings ?? [:]
			let options = field.options!
			for key in field.keys! {
				let name = types[key] ?? OsmTags.PrettyTag(key)
				let tag = comboWith(
					label: name,
					type: field.type,
					key: key,
					options: [options],
					strings: strings,
					icons: field.icons,
					defaultValue: field.defaultValue,
					placeholder: field.placeholder,
					keyboard: .default,
					capitalize: .none,
					autocorrect: .no)
				tagList.append(.key(tag))
			}
			let group = PresetGroup(name: label, tags: tagList, usesBoth: field.type == .directionalCombo)
			return group

		case .address:

			let addressPrefix = key
			let numericFields = [
				"block_number",
				"conscriptionnumber",
				"floor",
				"housenumber",
				"postcode",
				"unit"
			]
			var keysForCountry: [String] = []
			for locale in presetAddressFormats {
				guard let countryCodes = locale.countryCodes else {
					// default
					keysForCountry = locale.addressKeys
					continue
				}
				if countryCodes.contains(countryCode) {
					// country specific format
					keysForCountry = locale.addressKeys
					break
				}
			}
			keysForCountry = keysForCountry.flatMap({ $0.components(separatedBy: "+") })

			let placeholders = field.placeholders
			var addrs: [PresetKeyOrGroup] = []
			for addressKey in keysForCountry {
				let name: String
				let placeholder = placeholders?[addressKey] as? String
				if let placeholder = placeholder, placeholder != "123" {
					name = placeholder
				} else {
					name = OsmTags.PrettyTag(addressKey)
				}
				let keyboard: UIKeyboardType = numericFields.contains(addressKey) ? .numbersAndPunctuation : .default
				let tagKey = "\(addressPrefix):\(addressKey)"
				let tag = PresetKey(
					name: name,
					type: field.type,
					tagKey: tagKey,
					defaultValue: field.defaultValue,
					placeholder: placeholder,
					keyboard: keyboard,
					capitalize: .words,
					autocorrect: .no,
					presets: nil)
				addrs.append(.key(tag))
			}
			let group = PresetGroup(name: label, tags: addrs, usesBoth: false)
			return group

		case .text, .number, .email, .identifier, .maxweight_bridge, .textarea,
		     .tel, .url, .roadheight, .roadspeed, .wikipedia, .wikidata, .date:

			// no presets, but we customize keyboard input
			var keyboard: UIKeyboardType = .default
			var capitalize: UITextAutocapitalizationType = .none
			var autocorrect: UITextAutocorrectionType = .no
			switch field.type {
			case .number, .roadheight, .roadspeed, .date:
				keyboard = .numbersAndPunctuation // UIKeyboardTypeDecimalPad doesn't have Done button
			case .tel:
				keyboard = .phonePad
			case .url:
				keyboard = .URL
			case .email:
				keyboard = .emailAddress
			case .textarea:
				capitalize = .sentences
				autocorrect = .yes
			case .text:
				switch field.key {
				case "architect", "artist_name", "branch", "brand", "comment",
				     "destination", "flag:name", "network", "operator", "subject":
					capitalize = .words
					autocorrect = .default
				default:
					break
				}
			default:
				break
			}
			let tag = PresetKey(
				name: label,
				type: field.type,
				tagKey: key,
				defaultValue: field.defaultValue,
				placeholder: field.placeholder,
				keyboard: keyboard,
				capitalize: capitalize,
				autocorrect: autocorrect,
				presets: nil)
			let group = PresetGroup(name: nil, tags: [.key(tag)], usesBoth: false)
			return group

		case .localized:
			// used for "name" field: not implemented
			return nil

		case .restrictions:
			// used for turn restrictions: not implemented
			return nil

		default:
#if DEBUG
			assertionFailure()
#endif
			return nil
		}
	}
}
