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
final class PresetFeature: CustomDebugStringConvertible {
	static let uninitializedImage = UIImage()

	let featureID: String

	// from json dictionary:
	let _addTags: [String: String]?
	let fieldsWithRedirect: [String]?
	let geometry: [String]
	let icon: String? // icon on the map
	let logoURL: String? // NSI brand image
	let locationSet: [String: [Any]]?
	let matchScore: Float
	let moreFieldsWithRedirect: [String]?
	let nameWithRedirect: String
	let reference: [String: String]?
	let _removeTags: [String: String]?
	let searchable: Bool
	let tags: [String: String]
	let terms: [String]
	let aliases: [String] // an alias is a localizable alternative to 'name'

	var addTags: [String: String] { return _addTags ?? tags }
	var removeTags: [String: String] { return _removeTags ?? addTags }

	init?(withID featureID: String, jsonDict: [String: Any], isNSI: Bool) {
		guard jsonDict["tags"] is [String: String] else { return nil }

		self.featureID = featureID

		_addTags = jsonDict["addTags"] as! [String: String]?
		fieldsWithRedirect = jsonDict["fields"] as! [String]?
		geometry = jsonDict["geometry"] as! [String]? ?? []
		icon = jsonDict["icon"] as! String?
		logoURL = jsonDict["imageURL"] as! String?
		locationSet = jsonDict["locationSet"] as! [String: [Any]]?
		matchScore = Float(jsonDict["matchScore"] as! Double? ?? 1.0)
		moreFieldsWithRedirect = jsonDict["moreFields"] as! [String]?
		nameWithRedirect = jsonDict["name"] as! String? ?? featureID
		reference = jsonDict["reference"] as! [String: String]?
		_removeTags = jsonDict["removeTags"] as! [String: String]?
		searchable = jsonDict["searchable"] as! Bool? ?? true
		tags = jsonDict["tags"] as! [String: String]
		if let terms = jsonDict["terms"] as? String {
			self.terms = terms.split(separator: ",").map({ String($0) })
		} else {
			terms = jsonDict["terms"] as! [String]? ?? jsonDict["matchNames"] as! [String]? ?? []
		}
		aliases = (jsonDict["aliases"] as! String?)?.split(separator: "\n").map({ String($0) }) ?? []
		nsiSuggestion = isNSI
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

	var name: String {
		// This has to be done in a lazy manner because the redirect may not exist yet when we are instantiated
		if nameWithRedirect.hasPrefix("{"), nameWithRedirect.hasSuffix("}") {
			let redirect = String(nameWithRedirect.dropFirst().dropLast())
			if let preset = PresetsDatabase.shared.presetFeatureForFeatureID(redirect) {
				return preset.name
			}
		}
		return nameWithRedirect
	}

	var fields: [String]? {
		// This has to be done in a lazy manner because the redirect may not exist yet when we are instantiated
		guard let fieldsWithRedirect = fieldsWithRedirect else { return nil }
		return fieldsWithRedirect.flatMap {
			if $0.hasPrefix("{"), $0.hasSuffix("}") {
				let redirect = String($0.dropFirst().dropLast())
				if let preset = PresetsDatabase.shared.presetFeatureForFeatureID(redirect),
				   let fields = preset.fields
				{
					return fields
				}
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
				if let preset = PresetsDatabase.shared.presetFeatureForFeatureID(redirect),
				   let moreFields = preset.moreFields
				{
					return moreFields
				}
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
		return name
	}

	func summary() -> String? {
		let parentID = PresetFeature.parentIDofID(featureID)
		let result = PresetsDatabase.shared.inheritedValueOfFeature(parentID, fieldGetter: { $0.name })
		return result as? String
	}

	var iconUnscaled: UIImage? {
		if _iconUnscaled === PresetFeature.uninitializedImage {
			_iconUnscaled = icon != nil ? UIImage(named: icon!) : nil
		}
		return _iconUnscaled
	}

	func nsiLogo(_ callback: ((UIImage) -> Void)?) -> UIImage? {
		guard nsiSuggestion else {
			return iconUnscaled?.withRenderingMode(.alwaysTemplate)
		}

		if let icon = _nsiLogo {
			return icon
		}
		if let callback = callback {
			if let icon = NsiLogoDatabase.shared.retrieveLogoForNsiItem(featureID: featureID,
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

	func objectTagsUpdatedForFeature(_ tags: [String: String], geometry: GEOMETRY,
	                                 location: MapView.CurrentRegion) -> [String: String]
	{
		var tags = tags

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
		case namePrefix = 10
		case aliasPrefix = 9
		case termPrefix = 8
		case featureIdPrefix = 7

		case nameInternal = 6
		case aliasInternal = 5
		case termInternal = 4
		case featureIdInternal = 3
	}

	func matchesSearchText(_ searchText: String?, geometry: GEOMETRY) -> Int? {
		guard let searchText = searchText else {
			return nil
		}
		if !self.geometry.contains(geometry.rawValue) {
			return nil
		}
		if let range = name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) {
			return (range.lowerBound == name.startIndex
				? PresetMatchScore.namePrefix : PresetMatchScore.nameInternal).rawValue
		}
		for alias in aliases {
			if let range = alias.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) {
				return (range.lowerBound == alias.startIndex
					? PresetMatchScore.aliasPrefix : PresetMatchScore.aliasInternal).rawValue
			}
		}
		for term in terms {
			if let range = term.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) {
				return (range.lowerBound == term.startIndex
					? PresetMatchScore.termPrefix : PresetMatchScore.termInternal).rawValue
			}
		}
		if let range = featureID.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) {
			return (range.lowerBound == featureID.startIndex
				? PresetMatchScore.featureIdPrefix : PresetMatchScore.featureIdInternal).rawValue
		}
		return nil
	}

	func matchObjectTagsScore(_ objectTags: [String: String], geometry: GEOMETRY?,
	                          location: MapView.CurrentRegion) -> Double
	{
		if let geometry = geometry,
		   !self.geometry.contains(geometry.rawValue) ||
		   !locationSetIncludes(location)
		{
			return 0.0
		}

		var totalScore: Float = 1.0

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

	func locationMatches(_ location: Any, at currentLocation: MapView.CurrentRegion) -> Bool {
		if let location = location as? String {
			if location == "001" {
				return true
			} else if location.hasSuffix(".geojson") {
				if let geojson = PresetsDatabase.shared.nsiGeoJson[location],
				   geojson.contains(currentLocation.latLon)
				{
					return true
				}
				return false
			} else {
				if currentLocation.regions.contains(location) {
					return true
				}
				return false
			}
		} else if let numbers = location as? [NSNumber],
		          (2...3).contains(numbers.count)
		{
			// lat, lon, radius
			let lon = numbers[0].doubleValue
			let lat = numbers[1].doubleValue
			let radius = numbers.count > 2 ? numbers[2].doubleValue : 25000.0
			let dist = GreatCircleDistance(LatLon(lon: lon, lat: lat),
			                               currentLocation.latLon)
			return dist <= radius
		}
		print("unknown locationSet entry: \(location)")
		return false
	}

	func locationSetIncludes(_ location: MapView.CurrentRegion) -> Bool {
		guard let locationSet = locationSet else { return true }
		if let includeList = locationSet["include"] {
			if nsiSuggestion {
				if !includeList.contains(where: { locationMatches($0, at: location) }) {
					return false
				}
			} else {
				if !includeList.contains(where: { $0 as? String == location.country }) {
					return false
				}
			}
		}
		if let excludeList = locationSet["exclude"] {
			if nsiSuggestion {
				if excludeList.contains(where: { locationMatches($0, at: location) }) {
					return false
				}
			} else {
				if excludeList.contains(where: { $0 as? String == location.country }) {
					return false
				}
			}
		}
		return true
	}
}
