//
//  PresetsDatabase+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/13/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation


// The entire presets database from iD
extension PresetsDatabase {
	@objc func featuresAndCategoriesForGeometry(_ geometry: String) -> [AnyHashable]? {
		let list = jsonDefaults[geometry] as! [String]
		let featureList = self.featuresAndCategoriesForMemberList( memberList: list )
		return featureList
	}

	@objc func featuresInCategory( _ category: PresetCategory?, matching searchText: String) -> [PresetFeature] {
		var list = [PresetFeature]()
		if let category = category {
			for feature in category.members {
				if feature.matchesSearchText(searchText) {
					list.append(feature)
				}
			}
		} else {
			let countryCode = AppDelegate.shared.mapView?.countryCodeForLocation
			list = PresetsDatabase.shared.featuresMatchingSearchText(searchText, country: countryCode)
		}
		list.sort(by: { (obj1, obj2) -> Bool in
			// sort so that regular items come before suggestions
			let diff = (obj1.nsiSuggestion ? 1:0) - (obj2.nsiSuggestion ? 1:0)
			if diff != 0 {
				return diff < 0
			}
			// prefer exact matches of primary name over alternate terms
			let name1 = obj1.friendlyName
			let name2 = obj2.friendlyName
			let p1 = name1().hasPrefix(searchText)
			let p2 = name2().hasPrefix(searchText)
			if p1 != p2 {
				return (p1 ? 1:0) < (p2 ? 1:0)
			}
			return name1().caseInsensitiveCompare(name2()) == .orderedAscending
		})
		return list
	}

	@objc func allTagKeys() -> Set<String> {
		var set = Set<String>()
		for (_,dict) in jsonFields {
			guard let dict = dict as? [String:Any] else { continue }
			if let key = dict["key"] as? String {
				set.insert(key)
			}
			if let keys = dict["keys"] as? [String] {
				for key in keys {
					set.insert(key)
				}
			}
		}
		PresetsDatabase.shared.enumeratePresetsUsingBlock( { feature in
			for (key,_) in feature.tags {
				set.insert(key)
			}
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

	@objc func allTagValuesForKey(_ key: String) -> Set<AnyHashable>? {
		var set = Set<String>()
		for (_,dict) in jsonFields {
			guard let dict = dict as? [String:Any] else { continue }
			if let k = dict["key"] as? String,
			k == key,
			let dict2 = dict["strings"] as? [String : Any],
			let dict3 = dict2["options"] as? [String : Any]
			{
				set.formUnion(Set(dict3.keys))
			}
		}
		PresetsDatabase.shared.enumeratePresetsUsingBlock( { feature in
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
			var key = feature.featureID;
			if let range = key.range(of: "/") {
				key = String(key.prefix(upTo: range.lowerBound))
			}
			set.insert(key)
		})
		return set
	}()

	@objc func allFeatureKeys() -> Set<String>? {
		return PresetsDatabase.allFeatureKeysSet
	}

	static let isAreaAreaTags: [String : [String:Bool]] = {

		// make a list of items that can/cannot be areas
		var areaKeys = [String : [String:Bool]]()
		let ignore = ["barrier", "highway", "footway", "railway", "type"]

		// whitelist
		PresetsDatabase.shared.enumeratePresetsUsingBlock({ feature in
			if feature.nsiSuggestion  {
				return
			}
			if let geom = feature.geometry,
				geom.contains("area")
			{
				return
			}
			if feature.tags.count > 1 {
				return // very specific tags aren't suitable for whitelist, since we don't know which key is primary (in iD the JSON order is preserved and it would be the first key)
			}
			for (key,_) in feature.tags {
				if ignore.contains(key) {
					return
				}
				areaKeys[key] = [String : Bool]()
			}
		})

		// blacklist
		PresetsDatabase.shared.enumeratePresetsUsingBlock({ feature in
			if feature.nsiSuggestion {
				return
			}
			if let geom = feature.geometry,
				geom.contains("area")
			{
				return
			}
			for (key,value) in feature.tags {
				if ignore.contains(key) {
					return
				}
				if value == "*" {
					return
				}
				if var d = areaKeys[key] {
					d[value] = true
				}
			}
		})
		return areaKeys
	}()

	@objc func isArea(_ way: OsmWay) -> Bool {

		if let value = way.tags?["area"] {
			if OsmTags.IsOsmBooleanTrue(value) {
				return true
			}
			if OsmTags.IsOsmBooleanFalse(value) {
				return false
			}
		}
		if !way.isClosed() {
			return false
		}
		if (way.tags?.count ?? 0) == 0 {
			return true // newly created closed way
		}
		for (key,val) in way.tags! {
			if let exclusions = PresetsDatabase.isAreaAreaTags[key] {
				if exclusions[val] == nil {
					return true
				}
			}
		}
		return false
	}

	static var autocompleteIgnoreList: [String : Bool] = [
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
	@objc func eligibleForAutocomplete(_ key: String) -> Bool {
		if PresetsDatabase.autocompleteIgnoreList[key] != nil {
			return false
		}
		for (suffix, isSuffix) in PresetsDatabase.autocompleteIgnoreList {
			if isSuffix && key.hasSuffix(suffix) && key.dropLast(suffix.count).hasSuffix(":") {
				return false
			}
		}
		return true
	}

	func featuresAndCategoriesForMemberList(memberList: [String]) -> [AnyHashable] {
		var list: [AnyHashable] = []
		for featureID in memberList {
			if featureID.hasPrefix("category-") {
				let category = PresetCategory(categoryID: featureID)
				list.append(category)
			} else {
				if let feature = PresetsDatabase.shared.presetFeatureForFeatureID(featureID) {
					list.append(feature)
				}
			}
		}
		return list // list of PresetFeature or PresetCategory
	}

	func groupForField( fieldName: String, geometry: String, ignore: [String]?, update: (() -> Void)?) -> PresetGroup?
	{
		guard let dict = jsonFields[fieldName ] as? [AnyHashable : Any] else { return nil }
		if dict.count == 0 {
			return nil
		}

		if let geoList = dict["geometry"] as? [String] {
			if !geoList.contains(geometry) {
				return nil
			}
		}

		var key = dict["key"] as? String ?? fieldName
		let type = dict["type"] as? String
		let keysArray = dict["keys"] as? [String]
		let label = dict["label"] as? String
		var placeholder = dict["placeholder"] as? String
		let dictStrings = dict["strings"] as? [String:Any]
		let stringsOptionsDict = dictStrings?["options"] as? [String : Any]
		let stringsTypesDict = dictStrings?["types"] as? [AnyHashable : Any]
		let optionsArray = dict["options"] as? [AnyHashable]
		let defaultValue = dict["default"] as? String
		#if os(iOS)
		var keyboard = UIKeyboardType.default
		var capitalize = key.hasPrefix("name:") || (key == "operator") ? UITextAutocapitalizationType.words : UITextAutocapitalizationType.none
		#else
		var keyboard = 0
		let UITextAutocapitalizationTypeNone = 0
		let UITextAutocapitalizationTypeWords = 1
		var capitalize = key?.hasPrefix("name:") ?? false || (key == "operator") ? .words : .none
		#endif

		//r	DLog(@"%@",dict);

		if (type == "defaultcheck") || (type == "check") || (type == "onewayCheck") {

			let presets = [
				PresetValue(name: PresetsDatabase.shared.yesForLocale, details: nil, tagValue: "yes"),
				PresetValue(name: PresetsDatabase.shared.noForLocale, details: nil, tagValue: "no")
			]
			let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: presets)
			let group = PresetGroup(name:nil, tags:[tag])
			return group
		} else if (type == "radio") || (type == "structureRadio") {

			if let keysArray = keysArray {

				// a list of booleans
				let presets = [
					PresetValue(name: PresetsDatabase.shared.yesForLocale, details: nil, tagValue: "yes"),
					PresetValue(name: PresetsDatabase.shared.noForLocale, details: nil, tagValue: "no")
				]
				var tags: [PresetKey] = []
				for k in keysArray {
					let name = stringsOptionsDict![k] as? String
					let tag = PresetKey(name: name!, tagKey: k, defaultValue: defaultValue, placeholder: nil, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
					tags.append(tag)
				}
				let group = PresetGroup(name: label, tags: tags)
				return group
			} else if let optionsArray = optionsArray {

				// a multiple selection
				var presets: [PresetValue] = []
				for v in optionsArray {
					guard let v = v as? String else {
						continue
					}
					presets.append(PresetValue(name: nil, details: nil, tagValue: v))
				}
				let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
				let group = PresetGroup(name: nil, tags: [tag])
				return group
			} else if let stringsOptionsDict = stringsOptionsDict {

				// a multiple selection
				var presets: [PresetValue] = []
				for (val2,prettyName) in stringsOptionsDict as! [String:String] {
					let p = PresetValue(name: prettyName, details: nil, tagValue: val2)
					presets.append(p)
				}
				let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
				let group = PresetGroup(name: nil, tags: [tag].compactMap { $0 })
				return group
			} else {
			#if DEBUG
				assert(false)
			#endif
				return nil
			}
		} else if (type == "radio") || (type == "structureRadio") {

			if let keysArray = keysArray {

				// a list of booleans
				var tags: [PresetKey] = []
				let presets = [
					PresetValue(name: PresetsDatabase.shared.yesForLocale, details: nil, tagValue: "yes"),
					PresetValue(name: PresetsDatabase.shared.noForLocale, details: nil, tagValue: "no")
				]
				for k in keysArray {
					let name = stringsOptionsDict?[k] as? String
					let tag = PresetKey(name: name!, tagKey: k, defaultValue: defaultValue, placeholder: nil, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
					tags.append(tag)
				}
				let group = PresetGroup(name: label, tags: tags)
				return group
			} else if let optionsArray = optionsArray {

				// a multiple selection
				var presets: [PresetValue] = []
				for v in optionsArray {
					guard let v = v as? String else {
						continue
					}
					presets.append(PresetValue(name: nil, details: nil, tagValue: v))
				}
				let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
				let group = PresetGroup(name: nil, tags: [tag])
				return group
			} else {
			#if DEBUG
				assert(false)
			#endif
				return nil
			}
		} else if (type == "combo") || (type == "semiCombo") || (type == "multiCombo") || (type == "typeCombo") || (type == "manyCombo") {
			if (type == "typeCombo") && (ignore?.contains(key) ?? false) {
				return nil
			}
			let isMulti = type == "multiCombo"
			if isMulti && !key.hasSuffix(":") {
				key = key + ":"
			}
			var presets: [PresetValue] = []
			if let stringsOptionsDict = stringsOptionsDict {

				for (k,v) in stringsOptionsDict as! [String:String] {
					presets.append(PresetValue(name: v, details: nil, tagValue: k))
				}
				presets.sort(by: { (obj1, obj2) -> Bool in
					return obj1.name < obj2.name
				})
			} else if let optionsArray = optionsArray {

				for v in optionsArray {
					if let v = v as? String {
						presets.append(PresetValue(name: nil, details: nil, tagValue: v))
					}
				}

			} else {

				// check tagInfo
				if let cached = g_taginfoCache[fieldName] {
					// already got them once
					if cached is PresetGroup {
						return cached as? PresetGroup // hack for multi-combo: we already created the group and stashed it in presets
					} else {
						// its an array, and we'll convert it to a group below
					}
				} else if let update = update {
					DispatchQueue.global(qos: .default).async(execute: {
						let cleanKey = isMulti ? key.trimmingCharacters(in: CharacterSet(charactersIn: ":")) : key
						let urlText = isMulti
							? "https://taginfo.openstreetmap.org/api/4/keys/all?query=\(cleanKey)&filter=characters_colon&page=1&rp=10&sortname=count_all&sortorder=desc"
							: "https://taginfo.openstreetmap.org/api/4/key/values?key=\(key)&page=1&rp=25&sortname=count_all&sortorder=desc"
						let url = URL(string: urlText)
						var data: Data? = nil
						if let url = url {
							do {
								try data = Data(contentsOf: url)
							} catch {}
						}
						if let data = data {
							var presets2: AnyHashable? = nil
							var dict2: [AnyHashable : Any]? = nil
							do {
								dict2 = try JSONSerialization.jsonObject(with: data, options: []) as? [AnyHashable : Any]
							} catch {
							}
							let values = dict2?["data"] as? [AnyHashable]
							if isMulti {
								// a list of booleans
								var tags: [PresetKey] = []
								let yesNo = [
									PresetValue(name: PresetsDatabase.shared.yesForLocale, details: nil, tagValue: "yes"),
									PresetValue(name: PresetsDatabase.shared.noForLocale, details: nil, tagValue: "no")
								]
								for v in values ?? [] {
									guard let v = v as? [AnyHashable : Any] else {
										continue
									}
									if (v["count_all"] as? NSNumber)?.intValue ?? 0 < 1000 {
										continue // it's a very uncommon value, so ignore it
									}
									if let k = v["key"] as? String {
										let tag = PresetKey(name: k, tagKey: k, defaultValue: defaultValue, placeholder: nil, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: yesNo)
										tags.append(tag)
									}
								}
								let group = PresetGroup(name: label, tags: tags)
								let group2 = PresetGroup(name: nil, tags: [group])
								group.isDrillDown = true
								group2.isDrillDown = true
								presets2 = group2

							} else {

								var presetList : [PresetValue] = []
								for v in values ?? [] {
									guard let v = v as? [AnyHashable : Any] else {
										continue
									}
									if ((v["fraction"] as? NSNumber)?.doubleValue ?? 0.0) < 0.01 {
										continue // it's a very uncommon value, so ignore it
									}
									if let val = v["value"] as? String {
										presetList.append(PresetValue(name: nil, details: nil, tagValue: val))
									}
								}
								presets2 = presetList
							}
							DispatchQueue.main.async(execute: {
								self.g_taginfoCache[fieldName] = presets2
								update()
							})
						}
					})
				} else {
					// already submitted to network, so don't do it again
				}
			}

			if isMulti {
				let group = PresetGroup(name: label, tags: [])
				let group2 = PresetGroup(name: nil, tags: [group])
				group.isDrillDown = true
				group2.isDrillDown = true
				return group2
			} else {
				let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
				let group = PresetGroup(name: nil, tags: [tag])
				return group
			}

		} else if type == "cycleway" {

			var tagList: [PresetKey] = []

			for key in keysArray ?? [] {
				var presets: [PresetValue] = []
				for (k,v) in stringsOptionsDict as? [String:[String:String]] ?? [:] {
					let n = v["title"]
					let d = v["description"]
					presets.append(PresetValue(name: n, details: d, tagValue: k))
				}
				let name = (stringsTypesDict?[key] as? String) ?? OsmTags.PrettyTag(type!)
				let tag = PresetKey(name: name, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: UITextAutocapitalizationType.none, presets: presets)
				tagList.append(tag)
			}
			let group = PresetGroup(name: label, tags: tagList)
			return group

		} else if type == "address" {

			let addressPrefix = dict["key"] as! String
			let numericFields = [
				"block_number",
				"conscriptionnumber",
				"floor",
				"housenumber",
				"postcode",
				"unit"
			]

			let countryCode = AppDelegate.shared.mapView?.countryCodeForLocation ?? "<unknown>"
			var keysForCountry: [[String]]? = nil
			for localeDict in jsonAddressFormats {
				guard let localeDict = localeDict as? [String:Any] else { continue }
				if let countryCodeList = localeDict["countryCodes"] as? [String],
				   countryCodeList.contains(countryCode)
				{
					// country specific format
					keysForCountry = localeDict["format"] as? [[String]]
					break
				} else {
					// default
					keysForCountry = localeDict["format"] as? [[String]]
				}
			}

			let placeholders = (dict["strings"] as? [String:Any])?["placeholders"] as? [String : Any]
			var addrs: [AnyHashable] = []
			for addressGroup in keysForCountry ?? [] {
				for addressKey in addressGroup {
					var name: String?
					placeholder = placeholders?[addressKey] as? String
					if placeholder != nil && (placeholder != "123") {
						name = placeholder
					} else {
						name = OsmTags.PrettyTag(addressKey)
					}
					keyboard = numericFields.contains(addressKey) ? .numbersAndPunctuation : .default
					let tagKey = "\(addressPrefix):\(addressKey)"
					let tag = PresetKey(name: name!, tagKey: tagKey, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: UITextAutocapitalizationType.words, presets: nil)
					addrs.append(tag)
				}
			}
			let group = PresetGroup(name: label, tags: addrs)
			return group
		} else if (type == "text") || (type == "number") || (type == "email") || (type == "identifier") || (type == "textarea") || (type == "tel") || (type == "url") || (type == "roadspeed") || (type == "wikipedia") || (type == "wikidata") {

			// no presets
			if (type == "number") || (type == "roadspeed") {
				keyboard = .numbersAndPunctuation // UIKeyboardTypeDecimalPad doesn't have Done button
			} else if type == "tel" {
				keyboard = .numbersAndPunctuation // UIKeyboardTypePhonePad doesn't have Done Button
			} else if type == "url" {
				keyboard = .URL
			} else if type == "email" {
				keyboard = UIKeyboardType.emailAddress
			} else if type == "textarea" {
				capitalize = .sentences
			}
			let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: nil)
			let group = PresetGroup(name: nil, tags: [tag])
			return group

		} else if type == "access" {

			// special case
			var presets: [PresetValue] = []
			for (k,info) in stringsOptionsDict as! [String:[String:Any]] {
				let v = PresetValue(name: info["title"] as? String, details: info["description"] as? String, tagValue: k)
				presets.append(v)
			}

			var tags: [AnyHashable] = []
			for k in keysArray ?? [] {
				let name = stringsTypesDict?[k] as? String
				let tag = PresetKey(name: name!, tagKey: k, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: presets)
				tags.append(tag)
			}
			let group = PresetGroup(name: label, tags: tags)
			return group
		} else if type == "localized" {

			// not implemented
			return nil
		} else {

		#if DEBUG
			assert(false)
		#endif
			let tag = PresetKey(name: label!, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: nil)
			let group = PresetGroup(name: nil, tags: [tag])
			return group
		}
	}
}
