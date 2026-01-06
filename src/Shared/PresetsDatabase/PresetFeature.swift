//
//  PresetFeature.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/11/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// A feature-defining tag such as amenity=shop
class PresetFeature: CustomDebugStringConvertible {
	static let uninitializedImage = UIImage()

	let _addTags: [String: String]?
	let aliases: [String] // an alias is a localizable alternative to 'name'
	let featureID: String
	let fieldsWithRedirect: [String]?
	let geometry: [String]
	let iconName: String? // icon on the map
	let locationSet: LocationSet
	let matchScore: Double
	let moreFieldsWithRedirect: [String]?
	let nameWithRedirect: String
	let reference: [String: String]?
	let _removeTags: [String: String]?
	let searchable: Bool
	let tags: [String: String]
	let terms: [String]

	// computed properties
	var addTags: [String: String] { return _addTags ?? tags }
	var removeTags: [String: String] { return _removeTags ?? addTags }

	init(_addTags: [String: String]?,
	     aliases: [String], // an alias is a localizable alternative to 'name'
	     featureID: String,
	     fieldsWithRedirect: [String]?,
	     geometry: [String],
	     icon: String?, // icon on the map
	     locationSet: LocationSet,
	     matchScore: Double,
	     moreFieldsWithRedirect: [String]?,
	     nameWithRedirect: String,
	     nsiSuggestion: Bool,
	     reference: [String: String]?,
	     _removeTags: [String: String]?,
	     searchable: Bool,
	     tags: [String: String],
	     terms: [String])
	{
		self._addTags = _addTags
		self.aliases = aliases
		self.featureID = featureID
		self.fieldsWithRedirect = fieldsWithRedirect
		self.geometry = geometry
		iconName = icon
		self.locationSet = locationSet
		self.matchScore = matchScore
		self.moreFieldsWithRedirect = moreFieldsWithRedirect
		self.nameWithRedirect = nameWithRedirect
		self.nsiSuggestion = nsiSuggestion
		self.reference = reference
		self._removeTags = _removeTags
		self.searchable = searchable
		self.tags = tags
		self.terms = terms
	}

	convenience init?(withID featureID: String,
	                  jsonDict: [String: Any],
	                  isNSI: Bool)
	{
		guard jsonDict["tags"] is [String: String] else { return nil }

		self.init(
			_addTags: jsonDict["addTags"] as! [String: String]?,
			aliases: (jsonDict["aliases"] as! String?)?.split(separator: "\n").map({ String($0) }) ?? [],
			featureID: featureID,
			fieldsWithRedirect: jsonDict["fields"] as! [String]?,
			geometry: jsonDict["geometry"] as! [String]? ?? [],
			icon: jsonDict["icon"] as! String?,
			locationSet: LocationSet(withJson: jsonDict["locationSet"]),
			matchScore: jsonDict["matchScore"] as! Double? ?? 1.0,
			moreFieldsWithRedirect: jsonDict["moreFields"] as! [String]?,
			nameWithRedirect: jsonDict["name"] as! String? ?? featureID,
			nsiSuggestion: isNSI,
			reference: jsonDict["reference"] as! [String: String]?,
			_removeTags: jsonDict["removeTags"] as! [String: String]?,
			searchable: jsonDict["searchable"] as! Bool? ?? true,
			tags: jsonDict["tags"] as! [String: String],
			terms: {
				if let terms = jsonDict["terms"] as? String {
					return terms.split(separator: ",").map({ String($0) })
				} else {
					return jsonDict["terms"] as! [String]? ?? jsonDict["matchNames"] as! [String]? ?? []
				}
			}())
	}

	let nsiSuggestion: Bool // is from NSI
	private var _nsiLogo: UIImage? // from NSI imageURL
	private var _iconUnscaled: UIImage? = PresetFeature.uninitializedImage
	private var _iconScaled24: UIImage? = PresetFeature.uninitializedImage

	var description: String {
		return featureID
	}

	var debugDescription: String {
		return description
	}

	var localizedName: String {
		// This has to be done in a lazy manner because the redirect may not exist yet when we are instantiated
		var feature = self
		while feature.nameWithRedirect.hasPrefix("{"), feature.nameWithRedirect.hasSuffix("}") {
			let redirect = String(nameWithRedirect.dropFirst().dropLast())
			if let preset = PresetsDatabase.shared.presetFeatureForFeatureID(redirect) {
				feature = preset
			}
		}
		return PresetTranslations.shared.name(for: feature) ?? feature.nameWithRedirect
	}

	var fields: [String]? {
		// This has to be done in a lazy manner because the redirect may not exist yet when we are instantiated
		guard
			let fieldsWithRedirect = fieldsWithRedirect
		else {
			return nil
		}
		return fieldsWithRedirect.flatMap {
			if $0.hasPrefix("{"), $0.hasSuffix("}") {
				let redirect = String($0.dropFirst().dropLast())
				guard let preset = PresetsDatabase.shared.presetFeatureForFeatureID(redirect) else {
					print("bad preset redirect: \(redirect)")
					DbgAssert(false)
					return [String]()
				}
				return preset.fields ?? []
			}
			return [$0]
		}
	}

	var moreFields: [String]? {
		// This has to be done in a lazy manner because the redirect may not exist yet when we are instantiated
		guard let moreFieldsWithRedirect = moreFieldsWithRedirect else { return nil }
		return moreFieldsWithRedirect.flatMap {
			if $0.hasPrefix("{"), $0.hasSuffix("}") {
				let redirect = String($0.dropFirst().dropLast())
				guard let preset = PresetsDatabase.shared.presetFeatureForFeatureID(redirect) else {
					print("bad preset redirect: \(redirect)")
					DbgAssert(false)
					return [String]()
				}
				return preset.moreFields ?? []
			}
			return [$0]
		}
	}

	func isGeneric() -> Bool {
		return featureID == "point" ||
			featureID == "line" ||
			featureID == "area"
	}

	func friendlyName() -> String {
		return localizedName
	}

	func summary() -> String? {
		let parentID = PresetFeature.parentIDofID(featureID)
		let result = PresetsDatabase.shared.inheritedValueOfFeature(parentID, fieldGetter: { $0.localizedName })
		return result as? String
	}

	var iconUnscaled: UIImage? {
		if _iconUnscaled === PresetFeature.uninitializedImage {
			if let iconName = iconName {
				_iconUnscaled = UIImage(named: iconName)
			} else {
				_iconUnscaled = nil
			}
		}
		return _iconUnscaled
	}

	func nsiLogo(callback: ((UIImage) -> Void)?) -> UIImage? {
		guard nsiSuggestion else {
			return iconUnscaled?.withRenderingMode(.alwaysTemplate)
		}
		if let icon = _nsiLogo {
			return icon
		}
		if let callback {
			let nsi = NsiLogoDatabase.shared
			if let icon = nsi.retrieveLogoForNsiItem(featureID: featureID,
			                                         whenFinished: { img in
			                                         	self._nsiLogo = img
			                                         	callback(img)
			                                         })
			{
				_nsiLogo = icon
				return icon
			}
		}
		return iconUnscaled?.withRenderingMode(.alwaysTemplate)
	}

	var iconScaled24: UIImage? {
		if _iconScaled24 === PresetFeature.uninitializedImage {
			if let image = iconUnscaled {
				_iconScaled24 = EditorMapLayer.IconScaledForDisplay(image)
			} else {
				_iconScaled24 = nil
			}
		}
		return _iconScaled24
	}

	func objectTagsUpdatedForFeature(_ tags: [String: String],
	                                 geometry: GEOMETRY,
	                                 location: RegionInfoForLocation) -> [String: String]
	{
		var tags = tags

		if self is CustomFeature,
		   let baseFeature = PresetsDatabase.shared.presetFeatureMatching(tags: self.tags,
		                                                                  geometry: geometry,
		                                                                  location: location,
		                                                                  includeNSI: false,
		                                                                  ignoringCustomFeatures: true),
		   baseFeature.tags.isEmpty
		{
			// Our custom feature is not a specialization of a preset feature, so merge tags rather than replacing
			for (k, v) in self.tags {
				tags[k] = v
			}
			return tags
		}

		let oldFeature = PresetsDatabase.shared.presetFeatureMatching(
			tags: tags,
			geometry: geometry,
			location: location,
			includeNSI: true)

		// remove previous feature tags
		var removeTags = oldFeature?.removeTags ?? [:]
		for key in addTags.keys {
			removeTags.removeValue(forKey: key)
		}
		for key in removeTags.keys {
			tags.removeValue(forKey: key)
		}

#if false
		// Find fields that belongs to presets in oldFeature and don't exist in presets in new feature
		// and delete them. This will do things like remove the "cuisine" tag when a restaurant is
		// retagged as a shop.
		if let oldKeys = oldFeature?.allKeysForAllPresets(more: true) {
			let newKeys = allKeysForAllPresets(more: true)
			let removeKeys = Set(oldKeys).subtracting(newKeys)
			for key in removeKeys {
				tags.removeValue(forKey: key)
			}
		}
#endif

		// add new feature tags
		for (key, value) in addTags {
			if value == "*" {
				if tags[key] == nil {
					tags[key] = "yes"
				} else {
					// already has a value
				}
			} else {
				tags[key] = value
			}
		}

		// add default values of new feature fields
		let defaults = defaultValuesForGeometry(geometry)
		for (key, value) in defaults {
			if tags[key] == nil {
				tags[key] = value
			}
		}

		// add area=yes if it is implied
		if PresetArea.shared.needsAreaKey(forTags: tags, geometry: geometry, feature: self) {
			tags["area"] = "yes"
		}

		// remove any empty values
		tags = tags.compactMapValues({ $0 == "" ? nil : $0 })

		return tags
	}

	/// Returns the parent feature of a feature. For example "highway/residential" returns "highway".
	/// - Parameter featureID: The featureID of interest.
	/// - Returns: The featureID with the last component removed, or nil if none.
	class func parentIDofID(_ featureID: String) -> String? {
		if let range = featureID.range(of: "/", options: .backwards, range: nil, locale: nil) {
			return String(featureID.prefix(upTo: range.lowerBound))
		}
		return nil
	}

	/// Return the ``PresetField`` that references the provided tag key.
	/// This is used for recognizing quests.
	///
	/// - Parameters:
	///  - key: The tag key we're looking for, such as "surface"
	///  - more: Boolean indicating whether to search moreFields as well as regular fields.
	func fieldContainingTagKey(_ key: String, more: Bool) -> PresetField? {
		let allFields = (fields ?? []) + (more ? (moreFields ?? []) : [])
		for fieldName in allFields {
			if let field = PresetsDatabase.shared.presetFields[fieldName],
			   field.key == key || (field.keys?.contains(key) ?? false)
			{
				return field
			}
		}
		return nil
	}

	private enum PresetMatchScore: Int {
		case name = 4
		case alias = 3
		case term = 2
		case featureId = 1
	}

	private static func scoreForTextCompare(base: PresetMatchScore, text: String, search: String) -> Int? {
		guard
			let range = text.range(of: search, options: [.caseInsensitive, .diacriticInsensitive])
		else {
			return nil
		}
		// best case is it matches the prefix
		if range.lowerBound == text.startIndex {
			return 10 * base.rawValue + 5
		}
		// next best is it matches the start of a word
		if text[text.index(before: range.lowerBound)].isWhitespace {
			return 10 * base.rawValue
		}
		// it must be some random string in the middle of a word
		return base.rawValue
	}

	func matchesSearchText(_ searchText: String?, geometry: GEOMETRY) -> Int? {
		guard let searchText = searchText else {
			return nil
		}
		if !self.geometry.contains(geometry.rawValue) {
			return nil
		}

		if let score = Self.scoreForTextCompare(base: .name, text: localizedName, search: searchText) {
			return score
		}
		for alias in aliases {
			if let score = Self.scoreForTextCompare(base: .alias, text: alias, search: searchText) {
				return score
			}
		}
		for term in terms {
			if let score = Self.scoreForTextCompare(base: .term, text: term, search: searchText) {
				return score
			}
		}
		if let score = Self.scoreForTextCompare(base: .featureId, text: featureID, search: searchText) {
			return score
		}
		return nil
	}

	func matchObjectTagsScore(_ objectTags: [String: String], geometry: GEOMETRY?,
	                          location: RegionInfoForLocation) -> Double
	{
		if let geometry = geometry,
		   !self.geometry.contains(geometry.rawValue) ||
		   !locationSet.overlaps(location)
		{
			return 0.0
		}

		var totalScore = 1.0

		var seen = Set<String>()
		for (key, value) in tags {
			seen.insert(key)

			guard let v = objectTags[key] else { return 0.0 }
			if value == v {
				totalScore += matchScore
			} else if value == "*" {
				totalScore += matchScore / 2
			} else {
				return 0.0 // invalid match
			}
		}

		// boost score for additional matches in addTags
		if let addTags = _addTags {
			for (key, val) in addTags {
				if !seen.contains(key), objectTags[key] == val {
					totalScore += matchScore
				}
			}
		}
		return Double(totalScore)
	}

	func defaultValuesForGeometry(_ geometry: GEOMETRY) -> [String: String] {
		var result: [String: String] = [:]
		let fields = PresetsForFeature.fieldsFor(featureID: featureID, field: { f in f.fields })
		for fieldName in fields {
			if let field = PresetsDatabase.shared.presetFields[fieldName],
			   let key = field.key,
			   let def = field.defaultValue,
			   let geom = field.geometry,
			   geom.contains(geometry.rawValue)
			{
				result[key] = def
			}
		}
		return result
	}

	func allKeysForAllPresets(more: Bool) -> [String] {
		let f1 = PresetsForFeature.fieldsFor(featureID: featureID, field: { $0.fields })
		let f2 = more ? PresetsForFeature.fieldsFor(featureID: featureID, field: { $0.moreFields }) : []
		let k1 = f1.flatMap { PresetsDatabase.shared.presetFields[$0]!.allKeys }
		let k2 = f2.flatMap { PresetsDatabase.shared.presetFields[$0]!.allKeys }
		return k1 + k2
	}

	private var cachedWikiDescription: Any? = NSNull()
	func wikiDescription(update: @escaping (String) -> Void) -> String? {
		if nsiSuggestion {
			// NSI entries have their own, more specific description
			return nil
		}
		if !(cachedWikiDescription is NSNull) {
			return cachedWikiDescription as! String?
		}
		cachedWikiDescription = nil
		let key: String
		let value: String
		if let reference = reference {
			key = reference["key"]!
			value = reference["value"] ?? ""
		} else if tags.count == 1 {
			let kv = tags.first!
			key = kv.key
			value = kv.value
		} else {
			return nil
		}

		let languageCode = PresetLanguages.preferredPresetLanguageCode()
		if let result =
			WikiPage.shared.wikiDataFor(key: key,
			                            value: value,
			                            language: languageCode,
			                            imageWidth: 0,
			                            update: { result in
			                            	if let result = result {
			                            		self.cachedWikiDescription = result.description
			                            		update(result.description)
			                            	} else {
			                            		TagInfo.wikiInfoFor(key: key,
			                            		                    value: value,
			                            		                    update: { result in
			                            		                    	guard result != "" else { return }
			                            		                    	self.cachedWikiDescription = result
			                            		                    	update(result)
			                            		                    })
			                            	}
			                            })
		{
			cachedWikiDescription = result.description
			return result.description
		}
		return nil
	}
}
