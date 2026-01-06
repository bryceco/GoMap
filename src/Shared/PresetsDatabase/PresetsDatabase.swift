//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

final class PresetsDatabase {
	static let shared = {
		do {
			let database = try PresetsDatabase()
			return database
		} catch {
			showInternalError(error, context: nil)
			fatalError()
		}
	}()

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

	class func dataForFile(_ file: String) throws -> Data {
		let path = try Self.pathForFile(file)
		return try Data(contentsOf: path)
	}

	private class func jsonForFile(_ file: String) throws -> Any {
		let data = try dataForFile(file)
		return try JSONSerialization.jsonObject(with: data, options: [])
	}

	let presetAddressFormats: [PresetAddressFormat] // address formats for different countries
	let presetDefaults: [GEOMETRY: [String]] // map a geometry to a set of features/categories
	let presetCategories: [String: PresetCategory] // map a top-level category ("building") to a set of specific features ("building/retail")
	let presetFields: [String: PresetField] // possible values for a preset key ("oneway=")

	lazy var taginfoCache = TagInfo()

	init() throws {
		let startTime = Date()
		let readTime = Date()

		// default top-level items for an untagged geometry
		let defaults = try JSONDecoder().decode([String: [String]].self,
		                                        from: Self.dataForFile("preset_defaults.json"))
		presetDefaults = Dictionary(uniqueKeysWithValues:
			defaults.compactMap { key, value in
				guard let intKey = GEOMETRY(rawValue: key) else { return nil }
				return (intKey, value)
			})

		presetFields = try cast(Self.jsonForFile("fields.json"), to: [String: Any].self)
			.compactMapValuesWithKeys({ k, v in
				try PresetField(identifier: k, json: cast(v, to: [String: Any].self)) })

		// address formats
		presetAddressFormats = try JSONDecoder().decode([PresetAddressFormat].self,
		                                                from: Self.dataForFile("address_formats.json"))

		// initialize presets and index them
		let presets = try cast(Self.jsonForFile("presets.json"), to: [String: Any].self)
			.compactMapValuesWithKeys({ k, v in
				try PresetFeature(withID: k, jsonDict: cast(v, to: [String: Any].self), isNSI: false)
			})
		stdFeatures = presets
		stdFeatureIndex = Self.buildTagIndex([stdFeatures], basePresets: stdFeatures)

		presetCategories = try cast(Self.jsonForFile("preset_categories.json"), to: [String: Any].self)
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
								let p = try PresetFeature(withID: k,
								                          jsonDict: cast(v, to: [String: Any].self),
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
			do {
				try PresetTranslations.shared.setLanguage(langCode)
				for (name, field) in self.presetFields {
					var geometry = GEOMETRY.LINE
					if let geom = field.geometry {
						geometry = GEOMETRY(rawValue: geom[0])!
					}
					_ = self.presetGroupForField(fieldName: name,
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
#endif
}
