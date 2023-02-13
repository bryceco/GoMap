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
	let stdFeatures: [String: PresetFeature] // only generic presets
	var nsiFeatures: [String: PresetFeature] // only NSI presets
	// these map a tag key to a list of features that require that key
	let stdFeatureIndex: [String: [PresetFeature]] // generic preset index
	var nsiFeatureIndex: [String: [PresetFeature]] // generic+NSI index
	var nsiGeoJson: [String: GeoJSON] // geojson regions for NSI

	private class func dataForFile(_ file: String) -> Data? {
		guard
			let path = Bundle.main.resourceURL?
			.appendingPathComponent("presets")
			.appendingPathComponent(file)
		else {
			return nil
		}
		return try? Data(contentsOf: path)
	}

	private class func jsonForFile(_ file: String) -> Any? {
		guard let data = dataForFile(file) else { return nil }
		return try? JSONSerialization.jsonObject(with: data, options: [])
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

	let presetAddressFormats: [PresetAddressFormat] // address formats for different countries
	let presetDefaults: [String: [String]] // map a geometry to a set of features/categories
	let presetCategories: [String: PresetCategory] // map a top-level category ("building") to a set of specific features ("building/retail")
	let presetFields: [String: PresetField] // possible values for a preset key ("oneway=")

	let yesForLocale: String
	let noForLocale: String
	let unknownForLocale: String

	init(withLanguageCode code: String, debug: Bool = true) {
		// get translations for current language
		let file = "translations/" + code + ".json"
		let trans = Self.jsonForFile(file) as! [String: [String: Any]]
		let jsonTranslation = (trans[code]?["presets"] as! [String: [String: Any]]?) ?? [:]

		// get localized common words
		let fieldTrans = jsonTranslation["fields"] as! [String: [String: Any]]? ?? [:]
		let yesNoDict = fieldTrans["internet_access"]?["options"] as! [String: String]?
		yesForLocale = yesNoDict?["yes"] ?? "Yes"
		noForLocale = yesNoDict?["no"] ?? "No"
		unknownForLocale = fieldTrans["opening_hours"]?["placeholder"] as! String? ?? "???"

		// get presets files
		presetDefaults = Self.Translate(Self.jsonForFile("preset_defaults.json")!,
		                                jsonTranslation["defaults"]) as! [String: [String]]
		presetFields = (Self.Translate(Self.jsonForFile("fields.json")!,
		                               jsonTranslation["fields"]) as! [String: Any])
			.compactMapValues({ PresetField(withJson: $0 as! [String: Any]) })

		// address formats
		presetAddressFormats = (Self.jsonForFile("address_formats.json") as! [Any])
			.map({ PresetAddressFormat(withJson: $0 as! [String: Any]) })

		// initialize presets and index them
		let presets = (Self.Translate(Self.jsonForFile("presets.json")!,
		                              jsonTranslation["presets"]) as! [String: Any])
			.compactMapValuesWithKeys({ k, v in
				PresetFeature(withID: k, jsonDict: v as! [String: Any], isNSI: false)
			})
		stdFeatures = presets
		stdFeatureIndex = Self.buildTagIndex([stdFeatures], basePresets: stdFeatures)

		presetCategories = (Self.Translate(Self.jsonForFile("preset_categories.json")!,
		                                   jsonTranslation["categories"]) as! [String: Any])
			.mapValuesWithKeys({ k, v in PresetCategory(withID: k, json: v, presets: presets) })

		// name suggestion index
		nsiFeatures = [String: PresetFeature]()
		nsiFeatureIndex = stdFeatureIndex
		nsiGeoJson = [String: GeoJSON]()

		DispatchQueue.global(qos: .userInitiated).async {
			let nsiDict = Self.jsonForFile("nsi_presets.json") as! [String: Any]
			let nsiPresets = (nsiDict["presets"] as! [String: Any])
				.mapValuesWithKeys({ k, v in
					PresetFeature(withID: k, jsonDict: v as! [String: Any], isNSI: true)!
				})
			let nsiIndex = Self.buildTagIndex([self.stdFeatures, nsiPresets],
			                                  basePresets: self.stdFeatures)
			DispatchQueue.main.async {
				self.nsiFeatures = nsiPresets
				self.nsiFeatureIndex = nsiIndex
#if DEBUG
				if debug, isUnderDebugger() {
					self.testAllPresetFields()
				}
#endif
			}
		}

		// Load geojson outlines for NSI in the background
		DispatchQueue.global(qos: .userInitiated).async {
			if let json = Self.jsonForFile("nsi_geojson.json") {
				let featureList = (json as! [String: Any])["features"] as! [[String: Any]]
				var featureDict = [String: GeoJSON]()
				for feature in featureList {
					if feature["type"] as! String == "Feature" {
						let name = feature["id"] as! String
						let geomDict = feature["geometry"] as! [String: Any]
						do {
							let geojson = try GeoJSON(geometry: geomDict)
							featureDict[name] = geojson
						} catch {
							print("\(error)")
						}
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
		for (_, v) in stdFeatures {
			block(v)
		}
	}

	func enumeratePresetsAndNsiUsingBlock(_ block: (_ feature: PresetFeature) -> Void) {
		for v in stdFeatures.values {
			block(v)
		}
		for v in nsiFeatures.values {
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
		return PresetsDatabase.inheritedFieldForPresetsDict(stdFeatures, featureID: featureID, field: fieldGetter)
	}

	func presetFeatureForFeatureID(_ featureID: String) -> PresetFeature? {
		return stdFeatures[featureID] ?? nsiFeatures[featureID]
	}

	func presetFeatureMatching(tags objectTags: [String: String]?,
	                           geometry: GEOMETRY,
	                           location: MapView.CurrentRegion,
	                           includeNSI: Bool) -> PresetFeature?
	{
		guard let objectTags = objectTags else { return nil }

		var bestFeature: PresetFeature?
		var bestScore = 0.0

		let index = includeNSI ? nsiFeatureIndex : stdFeatureIndex
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

#if DEBUG
	func testAllPresetFields() {
		// Verify all fields can be read in all languages
		for langCode in PresetLanguages.languageCodeList {
			DispatchQueue.global(qos: .background).async {
				let presets = PresetsDatabase(withLanguageCode: langCode, debug: false)
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
	}
#endif
}
