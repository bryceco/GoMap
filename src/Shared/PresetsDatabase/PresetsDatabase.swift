//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

final class PresetsDatabase {
	static var shared = {
		let langCode = PresetLanguages.preferredPresetLanguageCode()
		do {
			return try PresetsDatabase(withLanguageCode: langCode)
		} catch {
			showInternalError(error, context: "langCode = \(langCode)")
			return PresetsDatabase()
		}
	}()

	class func reload(withLanguageCode code: String) throws {
		// called when language changes
		shared = try PresetsDatabase(withLanguageCode: code)
	}

	// these map a FeatureID to a feature
	var stdFeatures: [String: PresetFeature] // only generic presets + user custom features
	var nsiFeatures: [String: PresetFeature] // only NSI presets
	// these map a tag key to a list of features that require that key
	let stdFeatureIndex: [String: [PresetFeature]] // generic preset index
	var nsiFeatureIndex: [String: [PresetFeature]] // generic+NSI index
	var nsiGeoJson: [String: GeoJSONGeometry] // geojson regions for NSI

	class func pathForFile(_ file: String) throws -> URL {
		guard let bundle = Bundle.main.resourceURL else {
			throw ContextualError("Missing bundle URL")
		}
		return bundle.appendingPathComponent("presets").appendingPathComponent(file)
	}

	private class func dataForFile(_ file: String) throws -> Data {
		let path = try Self.pathForFile(file)
		return try Data(contentsOf: path)
	}

	private class func jsonForFile(_ file: String) throws -> Any {
		let data = try dataForFile(file)
		return try JSONSerialization.jsonObject(with: data, options: [])
	}

	private class func MergeTranslations(into orig: Any, from translation: Any?) throws -> Any {
		guard let translation = translation as? [String: Any] else {
			return orig
		}
		let orig = try cast(orig, to: [String: Any].self)

		func optionsArray(for opt: Any?) -> [String]?
		{
			if let s = opt as? [String] {
				return s
			} else if let s = opt as? [String: String] {
				return Array(s.keys)
			} else {
				return nil
			}
		}

		func stringsDict(for trans: Any?) -> [String: String]?
		{
			if let s = trans as? [String: String] {
				return s
			} else if let s = trans as? [String: [String: String]] {
				return s.compactMapValues{ $0["title"] }
			} else {
				return nil
			}
		}

		// both are dictionaries, so recurse on each key/value pair
		var newDict = [String: Any]()
		for (key, obj) in orig {
			if key == "options" {
				newDict[key] = optionsArray(for: obj)
				newDict["strings"] = stringsDict(for: translation[key])
			} else {
				newDict[key] = try MergeTranslations(into: obj, from: translation[key])
			}
		}

		// need to add things that don't exist in orig
		for (key, obj) in translation {
			if newDict[key] == nil {
				if key == "options" {
					newDict[key] = optionsArray(for: obj)
					newDict["strings"] = stringsDict(for: obj)
				} else {
					newDict[key] = obj
				}
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

	lazy var taginfoCache = TagInfo()

	init() {
		presetAddressFormats = []
		presetDefaults = [:]
		presetCategories = [:]
		presetFields = [:]
		yesForLocale = ""
		noForLocale = ""
		unknownForLocale = ""
		stdFeatures = [:]
		nsiFeatures = [:]
		stdFeatureIndex = [:]
		nsiFeatureIndex = [:]
		nsiGeoJson = [:]
	}

	init(withLanguageCode code: String, debug: Bool = true) throws {
		let startTime = Date()

		// get translations for current language
		do {
			let data = try Self.dataForFile("translations/\(code).json")
			let translations = try PresetTranslation(from: data)
			print(translations.asPrettyJSON())
		} catch {
			print("XXX")
			print(error)
		}
		var trans = try cast(Self.jsonForFile("translations/\(code).json"), to: [String: [String: Any]].self)
		trans = try cast(trans[code], to: [String: [String: Any]].self)
		if let dash = code.firstIndex(of: "-") {
			// If the language is a code like "en-US" we want to combine the "en" and "en-US" translations
			let baseCode = String(code.prefix(upTo: dash))
			var transBase = try cast(
				Self.jsonForFile("translations/\(baseCode).json"),
				to: [String: [String: Any]].self)
			transBase = try cast(transBase[baseCode], to: [String: [String: Any]].self)
			trans = try cast(Self.MergeTranslations(into: trans, from: transBase), to: [String: [String: Any]].self)
		}

		let jsonTranslation = try cast(trans["presets"], to: [String: [String: Any]]?.self) ?? [:]

		// get localized common words
		let fieldTrans = try cast(jsonTranslation["fields"], to: [String: [String: Any]]?.self) ?? [:]
		let yesNoDict = try cast(fieldTrans["internet_access"]?["strings"], to: [String: String]?.self)
		yesForLocale = yesNoDict?["yes"] ?? "Yes"
		noForLocale = yesNoDict?["no"] ?? "No"
		unknownForLocale = try cast(fieldTrans["opening_hours"]?["placeholder"], to: String?.self) ?? "???"

		let readTime = Date()

		// get presets files
		presetDefaults = try cast(Self.MergeTranslations(
			into: Self.jsonForFile("preset_defaults.json"),
			from: jsonTranslation["defaults"]), to: [String: [String]].self)
		presetFields = try cast(Self.MergeTranslations(into: Self.jsonForFile("fields.json"),
		                                               from: jsonTranslation["fields"]), to: [String: Any].self)
			.compactMapValues({ PresetField(withJson: try cast($0, to: [String: Any].self)) })

		// address formats
		presetAddressFormats = try cast(Self.jsonForFile("address_formats.json"), to: [Any].self)
			.map({ PresetAddressFormat(withJson: try cast($0, to: [String: Any].self)) })

		// initialize presets and index them
		let presets = try cast(Self.MergeTranslations(into: Self.jsonForFile("presets.json"),
		                                              from: jsonTranslation["presets"]), to: [String: Any].self)
			.compactMapValuesWithKeys({ k, v in
				PresetFeature(withID: k, jsonDict: try cast(v, to: [String: Any].self), isNSI: false)
			})
		stdFeatures = presets
		stdFeatureIndex = Self.buildTagIndex([stdFeatures], basePresets: stdFeatures)

		presetCategories = try cast(Self.MergeTranslations(into: Self.jsonForFile("preset_categories.json"),
		                                                   from: jsonTranslation["categories"]), to: [String: Any].self)
			.mapValuesWithKeys({ k, v in PresetCategory(withID: k, json: v, presets: presets) })

		// name suggestion index
		nsiFeatures = [String: PresetFeature]()
		nsiFeatureIndex = stdFeatureIndex
		nsiGeoJson = [String: GeoJSONGeometry]()

		DispatchQueue.main.async {
			// Get features provided by the user. This is done async because
			// we need to be initialized before adding in the presets.
			if let customFeatures = CustomFeatureList.restore() {
				self.insertCustomFeatures(customFeatures.list)
			}

			// After custom items are added we can compute NSI, which
			// includes stdFeatures, custom features and NSI.
			DispatchQueue.global(qos: .userInitiated).async {
				do {
					let startTime = Date()
					let nsiDict = try cast(Self.jsonForFile("nsi_presets.json"), to: [String: Any].self)
					let readTime = Date()
					let nsiPresets = try cast(nsiDict["presets"], to: [String: Any].self)
						.mapValuesWithKeys({ k, v in
							guard
								let p = PresetFeature(withID: k,
								                      jsonDict: try cast(v, to: [String: Any].self),
								                      isNSI: true)
							else {
								throw ContextualError("nil preset")
							}
							return p
						})
					let nsiIndex = Self.buildTagIndex([self.stdFeatures, nsiPresets],
					                                  basePresets: self.stdFeatures)
					DispatchQueue.main.async {
						self.nsiFeatures = nsiPresets
						self.nsiFeatureIndex = nsiIndex
#if DEBUG && false
						if debug, isUnderDebugger() {
							self.testAllPresetFields()
						}
#endif
					}
					print("NSI read = \(readTime.timeIntervalSince(startTime)), " +
						"decode = \(Date().timeIntervalSince(readTime))")
				} catch {
					showInternalError(error, context: "NSI")
				}
			}
		}

		// Load geojson outlines for NSI in the background
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				let data = try Self.dataForFile("nsi_geojson.json")
				let geoJson = try GeoJSONFile(data: data)
				var featureDict = [String: GeoJSONGeometry]()
				for feature in geoJson.features {
					if feature.type == "Feature" {
						let name = try unwrap(feature.id)
						featureDict[name] = feature.geometry
					}
				}
				DispatchQueue.main.async {
					self.nsiGeoJson = featureDict
				}
			} catch {
				showInternalError(error, context: "NSI geojson")
			}
		}
		print("PresetsDatabase read = \(readTime.timeIntervalSince(startTime)), " +
			"decode = \(Date().timeIntervalSince(readTime))")
	}

	/// basePresets is always the regular presets
	/// inputList is either regular presets, or both presets and NSI
	private class func buildTagIndex(_ inputList: [[String: PresetFeature]],
	                                 basePresets: [String: PresetFeature]) -> [String: [PresetFeature]]
	{
		// keys contains all tag keys that have an associated preset
		var keys: [String: Int] = [:]
		for featureID in basePresets.keys {
			var key = featureID
			if let range = key.range(of: "/") {
				key = String(key.prefix(upTo: range.lowerBound))
			}
			keys[key] = (keys[key] ?? 0) + 1
		}
		var tagIndex: [String: [PresetFeature]] = [:]
		for list in inputList {
			for feature in list.values {
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
		for v in stdFeatures.values {
			block(v)
		}
	}

	func insertCustomFeatures(_ features: [CustomFeature]) {
		// remove all exising features
		let removals = stdFeatures.compactMap { $0.value is CustomFeature ? $0.key : nil }
		for key in removals {
			stdFeatures.removeValue(forKey: key)
			nsiFeatures.removeValue(forKey: key)
		}
		// add in the new list
		for f in features {
			stdFeatures[f.featureID] = f
			nsiFeatures[f.featureID] = f
		}
	}

	// Cache features in the local region to speed up searches
	var localRegion = RegionInfoForLocation.none
	var stdLocal: [PresetFeature] = []
	var nsiLocal: [PresetFeature] = []
	func enumeratePresetsAndNsiIn(region: RegionInfoForLocation, using block: (_ feature: PresetFeature) -> Void) {
		if region != localRegion {
			localRegion = region
			stdLocal = stdFeatures.values.filter({ $0.searchable && $0.locationSet.overlaps(region) })
			nsiLocal = nsiFeatures.values.filter({ $0.searchable && $0.locationSet.overlaps(region) })
		}
		for v in stdLocal {
			block(v)
		}
		for v in nsiLocal {
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
	                           geometry: GEOMETRY?,
	                           location: RegionInfoForLocation,
	                           includeNSI: Bool,
	                           withPresetKey: String? = nil,
	                           ignoringCustomFeatures: Bool = false) -> PresetFeature?
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
					guard score > 0 else {
						continue
					}
					if !feature.searchable {
						score *= 0.999
					}
					if score >= bestScore {
						// special case for quests where we want to ensure we pick
						// a feature containing presetKey
						if let withPresetKey = withPresetKey,
						   feature.fieldContainingTagKey(withPresetKey, more: true) == nil
						{
							continue
						}
						// For ties we take the first alphabetically, just to be consistent
						if score == bestScore, feature.featureID > bestFeature!.featureID {
							continue
						}
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
	                                location: RegionInfoForLocation) -> [(PresetFeature, Int)]
	{
		var list = [(PresetFeature, Int)]()
		enumeratePresetsAndNsiIn(region: location, using: { feature in
			guard
				let score = feature.matchesSearchText(searchText, geometry: geometry)
			else {
				return
			}
			list.append((feature, score))
		})
		return list
	}

#if DEBUG
	func testAllPresetFields() {
		// Verify all fields can be read in all languages
		for langCode in PresetLanguages.languageCodeList {
			DispatchQueue.global(qos: .background).async {
				do {
					let presets = try PresetsDatabase(withLanguageCode: langCode, debug: false)
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
				} catch {
					fatalError("\(error)")
				}
			}
		}
	}
#endif
}
