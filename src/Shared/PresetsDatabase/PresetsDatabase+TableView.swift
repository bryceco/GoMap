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

	@objc func featuresInCategory( _ category: PresetCategory?, matching searchText: String, geometry:String) -> [PresetFeature] {
		var list = [PresetFeature]()
		if let category = category {
			for feature in category.members {
				if feature.matchesSearchText(searchText, geometry: geometry) {
					list.append(feature)
				}
			}
		} else {
			let countryCode = AppDelegate.shared.mapView?.countryCodeForLocation
			list = PresetsDatabase.shared.featuresMatchingSearchText(searchText, geometry:geometry, country: countryCode)
		}
		let searchText = searchText.lowercased()
		list.sort(by: { (obj1, obj2) -> Bool in
			// prefer exact matches of primary name over alternate terms
			let name1 = obj1.friendlyName()
			let name2 = obj2.friendlyName()
			let p1 = name1.lowercased().hasPrefix(searchText)
			let p2 = name2.lowercased().hasPrefix(searchText)
			if p1 != p2 {
				return (p1 ? 1:0) > (p2 ? 1:0)
			}
			// sort so that regular items come before suggestions
			let diff = (obj1.nsiSuggestion ? 1:0) - (obj2.nsiSuggestion ? 1:0)
			if diff != 0 {
				return diff < 0
			}
			return name1.caseInsensitiveCompare(name2) == .orderedAscending
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

	static let areaTagsDictionary: [String : [String:Bool]] = {

		// make a list of items that can/cannot be areas
		var areaKeys = [String : [String:Bool]]()
		let ignore = ["barrier", "highway", "footway", "railway", "type"]

		// whitelist
		PresetsDatabase.shared.enumeratePresetsUsingBlock({ feature in
			if feature.nsiSuggestion  ||
				!feature.geometry.contains("area")  ||
				feature.tags.count > 1 // very specific tags aren't suitable for whitelist, since we don't know which key is primary (in iD the JSON order is preserved and it would be the first key)
			{
				return
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
			if feature.nsiSuggestion  ||
				feature.geometry.contains("area")
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
			if let exclusions = PresetsDatabase.areaTagsDictionary[key] {
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

	// search the taginfo database, return the data immediately if its cached,
	// and call the update function later if it isn't
	func taginfoFor( key:String, searchKeys:Bool, update:(() -> Void)?) -> [String]
	{
		let cacheKey = key + (searchKeys ? ":K" : ":V")
		if let cached = taginfoCache[cacheKey] {
			return cached
		}
		guard let update = update else {
			// some callers don't want to wait for results
			return []
		}
		taginfoCache[cacheKey] = []	// mark as in-transit

		DispatchQueue.global(qos: .default).async(execute: {
			let cleanKey = searchKeys ? key.trimmingCharacters(in: CharacterSet(charactersIn: ":")) : key
			let urlText = searchKeys
				? "https://taginfo.openstreetmap.org/api/4/keys/all?query=\(cleanKey)&filter=characters_colon&page=1&rp=10&sortname=count_all&sortorder=desc"
				: "https://taginfo.openstreetmap.org/api/4/key/values?key=\(cleanKey)&page=1&rp=25&sortname=count_all&sortorder=desc"
			var rawData: Data? = nil
			if let url = URL(string: urlText) {
				do {
					try rawData = Data(contentsOf: url)
				} catch {}
			}
			if let rawData = rawData {
				var json: [AnyHashable : Any]? = nil
				do {
					json = try JSONSerialization.jsonObject(with: rawData, options: []) as? [AnyHashable : Any]
				} catch {
				}
				let results = json?["data"] as? [AnyHashable] ?? []
				var resultList: [String] = []
				if searchKeys {
					for v in results {
						guard let v = v as? [AnyHashable : Any] else {
							continue
						}
						if (v["count_all"] as? NSNumber)?.intValue ?? 0 < 1000 {
							continue // it's a very uncommon value, so ignore it
						}
						if let k = v["key"] as? String {
							resultList.append(k)
						}
					}
				} else {
					for v in results {
						guard let v = v as? [AnyHashable : Any] else {
							continue
						}
						if ((v["fraction"] as? NSNumber)?.doubleValue ?? 0.0) < 0.01 {
							continue // it's a very uncommon value, so ignore it
						}
						if let val = v["value"] as? String {
							resultList.append(val)
						}
					}
				}
				if resultList.count > 0 {
					DispatchQueue.main.async(execute: {
						self.taginfoCache[cacheKey] = resultList
						update()
					})
				}
			}
		})
		return []
	}

	private func commonPrefixOfMultiKeys(_ options:[String]) -> String
	{
		guard options.count > 0,
			  let index = options[0].lastIndex(of: ":") else
		{
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
	func multiComboWith(label:String, keys:[String], options:[String], strings:[String:String]?,
						defaultValue:String?, placeholder:String?, keyboard:UIKeyboardType, capitalize:UITextAutocapitalizationType) -> PresetGroup
	{
		let prefix = commonPrefixOfMultiKeys( options )
		var tags: [PresetKey] = []
		for i in keys.indices {
			let name = strings?[options[i]] ?? OsmTags.PrettyTag(String(options[i].dropFirst(prefix.count)))
			let tag = yesNoWith(label:name, key:keys[i], defaultValue:defaultValue, placeholder:nil, keyboard:keyboard, capitalize:capitalize)
			tags.append(tag)
		}
		let group = PresetGroup(name: label, tags: tags, isDrillDown: true)
		let group2 = PresetGroup(name: nil, tags: [group], isDrillDown: true)
		return group2
	}

	// a preset value with a supplied list of potential values
	func comboWith(label:String, key:String, options:[String], strings:[String:Any]?,
					defaultValue:String?, placeholder:String?, keyboard:UIKeyboardType, capitalize:UITextAutocapitalizationType) -> PresetKey
	{
		var presets: [PresetValue] = []
		for value in options {
			if let strings = strings as? [String:String] {
				let name = strings[value] ?? OsmTags.PrettyTag(value)
				presets.append(PresetValue(name: name, details: nil, tagValue: value))
			} else if let strings = strings as? [String:[String:String]] {
				let info = strings[value]
				let name = info?["title"] ?? OsmTags.PrettyTag(value)
				let desc = info?["description"] ?? ""
				presets.append(PresetValue(name: name, details: desc, tagValue: value))
			} else {
				print("missing strings definition: \(key)")
				let name = OsmTags.PrettyTag(value)
				presets.append(PresetValue(name: name, details: nil, tagValue: value))
			}
		}
		let tag = PresetKey(name: label, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: presets)
		return tag
	}

	// a yes/no preset
	func yesNoWith(label:String, key:String, defaultValue:String?, placeholder:String?, keyboard:UIKeyboardType, capitalize:UITextAutocapitalizationType) -> PresetKey
	{
		let presets = [
			PresetValue(name: PresetsDatabase.shared.yesForLocale, details: nil, tagValue: "yes"),
			PresetValue(name: PresetsDatabase.shared.noForLocale, details: nil, tagValue: "no")
		]
		let tag = PresetKey(name:label, tagKey:key, defaultValue:defaultValue, placeholder:placeholder, keyboard:keyboard, capitalize:capitalize, presets:presets)
		return tag
	}

	func groupForField( fieldName: String, geometry: String, ignore: [String]?, update: (() -> Void)?) -> PresetGroup?
	{
		guard let dict = jsonFields[fieldName] as? [AnyHashable : Any] else { return nil }
		if dict.count == 0 {
			return nil
		}

		if let geoList = dict["geometry"] as? [String] {
			if !geoList.contains(geometry) {
				return nil
			}
		}

		if let _ = dict["prerequisiteTag"] as? [String:String] {
			// supporting this would require us to dynamically add/remove fields as tags are set
			print("preset \(fieldName) doesn't honor prerequisiteTag")
		}

		let type 			= dict["type"] as! String
		let keyType 		= dict["key"] as? String ?? fieldName
		let label 			= dict["label"] as? String ?? OsmTags.PrettyTag(keyType)
		let placeholder 	= dict["placeholder"] as? String
		let defaultValue 	= dict["default"] as? String
		var keyboard 		= UIKeyboardType.default
		var capitalize 		= keyType.hasPrefix("name:") || (keyType == "operator") ? UITextAutocapitalizationType.words : UITextAutocapitalizationType.none

		switch type {

		case "defaultcheck", "check", "onewayCheck":
			let key = dict["key"] as! String
			let tag = yesNoWith(label: label, key: key, defaultValue:defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize)
			let group = PresetGroup(name:nil, tags:[tag])
			return group

		case "radio", "structureRadio", "manyCombo", "multiCombo":
			// all of these can have multiple keys
			let isMultiCombo = type == "multiCombo"	// uses a prefix key with multiple suffixes

			var options = dict["options"] as? [String]
			if options == nil {
				// need to get options from taginfo
				let key = dict["key"] as! String
				options = taginfoFor( key:key, searchKeys:isMultiCombo, update:update)
			} else if isMultiCombo {
				// prepend key: to options
				options = options!.map{ (k) -> String in return (dict["key"] as! String)+k }
			}
			let strings = dict["strings"] as? [String:String]

			if isMultiCombo || dict["keys"] != nil {
				// a list of booleans
				let keys = (isMultiCombo ? options : dict["keys"] as? [String]) ?? []
				if keys.count == 1 {
					let key = keys[0]
					let option = options![0]
					let name = strings?[option] ?? OsmTags.PrettyTag(option)
					let tag = yesNoWith(label: name, key: key, defaultValue:defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize)
					let group = PresetGroup(name:nil, tags:[tag])
					return group
				}
				let group = multiComboWith(label:label, keys:keys, options:options!, strings:strings,
										   defaultValue:defaultValue, placeholder:placeholder, keyboard:keyboard, capitalize:capitalize)
				return group
			} else {
				// a multiple selection
				let key = dict["key"] as! String
				let tag = comboWith(label:label, key: key, options: options!, strings: strings, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize)
				let group = PresetGroup(name: nil, tags: [tag])
				return group
			}

		case "combo", "semiCombo", "networkCombo", "typeCombo":

			let key = dict["key"] as! String
			if (type == "typeCombo") && (ignore?.contains(key) ?? false) {
				return nil
			}
			let options = dict["options"] as? [String] ?? taginfoFor(key:key, searchKeys:false, update:update)
			let strings = dict["strings"] as? [String:String]
			let tag = comboWith(label: label, key:key, options:options, strings:strings, defaultValue:defaultValue, placeholder:placeholder, keyboard:keyboard, capitalize:capitalize)
			let group = PresetGroup(name: nil, tags: [tag])
			return group

		case "access", "cycleway":

			var tagList: [PresetKey] = []

			let keys = dict["keys"] as! [String]
			let types = dict["types"] as! [String:String]
			let strings = dict["strings"] as! [String:[String:String]]
			let options = dict["options"] as! [String]
			for key in keys {
				let name = types[key] ?? OsmTags.PrettyTag(key)
				let tag = comboWith(label: name, key: key, options: options, strings: strings, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize)
				tagList.append(tag)
			}
			let group = PresetGroup(name: label, tags: tagList)
			return group

		case "address":

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

			let placeholders = dict["placeholders"] as? [String : Any]
			var addrs: [AnyHashable] = []
			for addressGroup in keysForCountry ?? [] {
				for addressKey in addressGroup {
					var name: String?
					let placeholder = placeholders?[addressKey] as? String
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

		case "text", "number", "email", "identifier", "maxweight_bridge", "textarea",
			"tel", "url", "roadheight", "roadspeed", "wikipedia", "wikidata":

			// no presets
			switch type {
			case "number", "roadheight", "roadspeed":
				keyboard = .numbersAndPunctuation // UIKeyboardTypeDecimalPad doesn't have Done button
			case "tel":
				keyboard = .numbersAndPunctuation // UIKeyboardTypePhonePad doesn't have Done Button
			case "url":
				keyboard = .URL
			case "email":
				keyboard = .emailAddress
			case "textarea":
				capitalize = .sentences
			default:
				break
			}
			let key = dict["key"] as! String
			let tag = PresetKey(name: label, tagKey: key, defaultValue: defaultValue, placeholder: placeholder, keyboard: keyboard, capitalize: capitalize, presets: nil)
			let group = PresetGroup(name: nil, tags: [tag])
			return group

		case "localized", "restrictions":
			// not implemented
			return nil

		default:
			#if DEBUG
				assert(false)
			#endif
			return nil
		}
	}
}
