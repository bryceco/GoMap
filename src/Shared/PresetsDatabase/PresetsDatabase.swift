//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

final class PresetsDatabase {
	static var shared = PresetsDatabase(withLanguageCode: PresetLanguages.preferredLanguageCode())
	class func reload(withLanguageCode code: String) {
		// called when language changes
		shared = PresetsDatabase(withLanguageCode: code)
	}

	// these map a FeatureID to a feature
	let stdPresets: [String: PresetFeature] // only generic presets
	var nsiPresets: [String: PresetFeature] // only NSI presets
	// these map a tag key to a list of features that require that key
	let stdIndex: [String: [PresetFeature]] // generic preset index
	var nsiIndex: [String: [PresetFeature]] // generic+NSI index
	var nsiGeoJson: [String: GeoJSON] // geojson regions for NSI

	private class func jsonForFile(_ file: String) -> Any? {
		guard let path = Bundle.main.resourcePath?.appending("/presets/" + file),
		      let rootPresetData = try? NSData(contentsOfFile: path) as Data,
		      let dict = try? JSONSerialization.jsonObject(with: rootPresetData, options: [])
		else {
			return nil
		}
		return dict
	}

	private class func Translate(_ orig: Any, _ translation: Any?) -> Any {
		guard let translation = translation as? [String: Any] else {
			return orig
		}
		let orig = orig as! [String: Any]

		// both are dictionaries, so recurse on each key/value pair
		var newDict = [String: Any]()
		for (key, obj) in orig {
			if key == "options" {
				newDict[key] = obj
				newDict["strings"] = translation[key]
			} else {
				newDict[key] = Translate(obj, translation[key])
			}
		}

		// need to add things that don't exist in orig
		for (key, obj) in translation {
			if newDict[key] == nil {
				newDict[key] = obj
			}
		}
		return newDict
	}

	let jsonAddressFormats: [Any] // address formats for different countries
	let jsonDefaults: [String: Any] // map a geometry to a set of features/categories
	let jsonCategories: [String: Any] // map a top-level category ("building") to a set of specific features ("building/retail")
	let presetFields: [String: PresetField] // possible values for a preset key ("oneway=")

	let yesForLocale: String
	let noForLocale: String
	let unknownForLocale: String

	init(withLanguageCode code: String) {
		// get translations for current language
		let file = "translations/" + code + ".json"
		let trans = Self.jsonForFile(file) as! [String: [String: Any]]
		let jsonTranslation = (trans[code]?["presets"] as? [String: [String: Any]]) ?? [:]

		// get localized common words
		let fieldTrans = jsonTranslation["fields"] as? [String: [String: Any]] ?? [:]
		let yesNoDict = fieldTrans["internet_access"]?["options"] as? [String: String]
		yesForLocale = yesNoDict?["yes"] ?? "Yes"
		noForLocale = yesNoDict?["no"] ?? "No"
		unknownForLocale = fieldTrans["opening_hours"]?["placeholder"] as? String ?? "???"

		// get presets files
		jsonDefaults = Self.Translate(Self.jsonForFile("preset_defaults.json")!,
		                              jsonTranslation["defaults"]) as! [String: Any]
		jsonCategories = Self.Translate(Self.jsonForFile("preset_categories.json")!,
		                                jsonTranslation["categories"]) as! [String: Any]
		presetFields = (Self.Translate(Self.jsonForFile("fields.json")!,
		                               jsonTranslation["fields"]) as! [String: Any])
			.compactMapValues({ PresetField(withJson: $0 as! [String: Any]) })

		// address formats
		jsonAddressFormats = Self.jsonForFile("address_formats.json") as! [Any]

		// initialize presets and index them
		var jsonPresetsDict = Self.jsonForFile("presets.json")!
		jsonPresetsDict = Self.Translate(jsonPresetsDict, jsonTranslation["presets"])
		stdPresets = Self.featureDictForJsonDict(jsonPresetsDict as! [String: [String: Any]], isNSI: false)
		stdIndex = Self.buildTagIndex([stdPresets], basePresets: stdPresets)

		// name suggestion index
		nsiPresets = [String: PresetFeature]()
		nsiIndex = stdIndex
		nsiGeoJson = [String: GeoJSON]()

		DispatchQueue.global(qos: .userInitiated).async {
			let jsonNsiPresetsDict = Self.jsonForFile("nsi_presets.json") as! [String: [String: Any]]
			let nsiPresets2 = Self.featureDictForJsonDict(jsonNsiPresetsDict,
			                                              isNSI: true)
			let nsiIndex2 = Self.buildTagIndex([self.stdPresets, nsiPresets2],
			                                   basePresets: self.stdPresets)
			DispatchQueue.main.async {
				self.nsiPresets = nsiPresets2
				self.nsiIndex = nsiIndex2

#if DEBUG
				// verify all fields can be read
				for langCode in PresetLanguages.languageCodeList {
					DispatchQueue.global(qos: .background).async {
						let presets = PresetsDatabase(withLanguageCode: langCode)
						for (name, field) in presets.presetFields {
							var geometry = GEOMETRY.LINE
							if let geom = field.geometry {
								geometry = GEOMETRY(rawValue: geom[0])!
							}
							_ = presets.presetGroupForField(fieldName: name,
															objectTags: [:],
															geometry: geometry,
															countryCode: "us",
															ignore: [],
															update: nil)
						}
					}
				}
#endif
			}
		}

		DispatchQueue.global(qos: .userInitiated).async {
			if let json = Self.jsonForFile("nsi_geojson.json"),
			   let dict = json as? [String: Any?],
			   let features = dict["features"] as? [Any]
			{
				var featureDict = [String: GeoJSON]()
				for feature2 in features {
					guard let feature = feature2 as? [String: Any?] else { continue }
					if feature["type"] as? String == "Feature",
					   let name = feature["id"] as? String,
					   let geomDict = feature["geometry"] as? [String: Any?],
					   let geojson = GeoJSON(geometry: geomDict)
					{
						featureDict[name] = geojson
					}
				}
				DispatchQueue.main.async {
					self.nsiGeoJson = featureDict
				}
			}
		}
	}

	// OSM TagInfo database in the cloud: contains either a group or an array of values
	var taginfoCache = [String: [String]]()

	// initialize presets database
	private class func featureDictForJsonDict(_ dict: [String: [String: Any]], isNSI: Bool) -> [String: PresetFeature] {
		let presetDict = isNSI ? dict["presets"] as! [String: [String: Any]] : dict
		var presets = [String: PresetFeature]()
		presets.reserveCapacity(presetDict.count)
		for (name, values) in presetDict {
			if let feature = PresetFeature(withID: name, jsonDict: values, isNSI: isNSI) {
				presets[name] = feature
			}
		}
		return presets
	}

	/// basePresets is always the regular presets
	/// inputList is either regular presets, or both presets and NSI
	private class func buildTagIndex(_ inputList: [[String: PresetFeature]],
	                                 basePresets: [String: PresetFeature]) -> [String: [PresetFeature]]
	{
		// keys contains all tag keys that have an associated preset
		var keys: [String: Int] = [:]
		for (featureID, _) in basePresets {
			var key = featureID
			if let range = key.range(of: "/") {
				key = String(key.prefix(upTo: range.lowerBound))
			}
			keys[key] = (keys[key] ?? 0) + 1
		}
		var tagIndex: [String: [PresetFeature]] = [:]
		for list in inputList {
			for (_, feature) in list {
				var added = false
				for key in feature.tags.keys {
					if keys[key] != nil {
						if tagIndex[key]?.append(feature) == nil {
							tagIndex[key] = [feature]
						}
						added = true
					}
				}
				if !added {
					if tagIndex[""]?.append(feature) == nil {
						tagIndex[""] = [feature]
					}
				}
			}
		}
		return tagIndex
	}

	// enumerate contents of database
	func enumeratePresetsUsingBlock(_ block: (_ feature: PresetFeature) -> Void) {
		for (_, v) in stdPresets {
			block(v)
		}
	}

	func enumeratePresetsAndNsiUsingBlock(_ block: (_ feature: PresetFeature) -> Void) {
		for v in stdPresets.values {
			block(v)
		}
		for v in nsiPresets.values {
			block(v)
		}
	}

	// go up the feature tree and return the first instance of the requested field value
	private class func inheritedFieldForPresetsDict(_ presetDict: [String: PresetFeature],
	                                                featureID: String?,
	                                                field fieldGetter: @escaping (_ feature: PresetFeature) -> Any?)
		-> Any?
	{
		var featureID = featureID
		while featureID != nil {
			if let feature = presetDict[featureID!],
			   let field = fieldGetter(feature)
			{
				return field
			}
			featureID = PresetFeature.parentIDofID(featureID!)
		}
		return nil
	}

	func inheritedValueOfFeature(_ featureID: String?,
	                             fieldGetter: @escaping (_ feature: PresetFeature) -> Any?) -> Any?
	{
		// This is currently never used for NSI entries, so we can ignore nsiPresets
		return PresetsDatabase.inheritedFieldForPresetsDict(stdPresets, featureID: featureID, field: fieldGetter)
	}

	func presetFeatureForFeatureID(_ featureID: String) -> PresetFeature? {
		return stdPresets[featureID] ?? nsiPresets[featureID]
	}

	func presetFeatureMatching(tags objectTags: [String: String]?,
	                           geometry: GEOMETRY,
	                           location: MapView.CurrentRegion,
	                           includeNSI: Bool) -> PresetFeature?
	{
		guard let objectTags = objectTags else { return nil }

		var bestFeature: PresetFeature?
		var bestScore = 0.0

		let index = includeNSI ? nsiIndex : stdIndex
		let keys = objectTags.keys + [""]
		for key in keys {
			if let list = index[key] {
				for feature in list {
					var score = feature.matchObjectTagsScore(objectTags, geometry: geometry, location: location)
					if !feature.searchable {
						score *= 0.999
					}
					if score > bestScore {
						bestScore = score
						bestFeature = feature
					}
				}
			}
		}
		return bestFeature
	}

	func featuresMatchingSearchText(_ searchText: String?,
	                                geometry: GEOMETRY,
	                                location: MapView.CurrentRegion) -> [(PresetFeature, Int)]
	{
		var list = [(PresetFeature, Int)]()
		enumeratePresetsAndNsiUsingBlock { feature in
			guard feature.searchable,
			      feature.locationSetIncludes(location),
			      let score = feature.matchesSearchText(searchText, geometry: geometry)
			else {
				return
			}
			list.append((feature, score))
		}
		return list
	}
}
