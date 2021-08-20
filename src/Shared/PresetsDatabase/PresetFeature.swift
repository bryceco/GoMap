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
final class PresetFeature {
	static let uninitializedImage = UIImage()

	let featureID: String

	// from json dictionary:
	let _addTags: [String: String]?
	let fields: [String]?
	let geometry: [String]
	let icon: String? // icon on the map
	let logoURL: String? // NSI brand image
	let locationSet: [String: [String]]?
	let matchScore: Float
	let moreFields: [String]?
	let name: String?
	let reference: [String: String]?
	let _removeTags: [String: String]?
	let searchable: Bool
	let tags: [String: String]
	let terms: [String]
	let aliases: [String] // an alias is a localizable alternative to 'name'

	init(withID featureID: String, jsonDict: [String: Any], isNSI: Bool) {
		self.featureID = featureID

		_addTags = jsonDict["addTags"] as? [String: String]
		fields = jsonDict["fields"] as? [String]
		geometry = jsonDict["geometry"] as? [String] ?? []
		icon = jsonDict["icon"] as? String
		logoURL = jsonDict["imageURL"] as? String
		locationSet = PresetFeature.convertLocationSet(jsonDict["locationSet"] as? [String: [String]])
		matchScore = jsonDict["matchScore"] as? Float ?? 1.0
		moreFields = jsonDict["moreFields"] as? [String]
		name = jsonDict["name"] as? String
		reference = jsonDict["reference"] as? [String: String]
		_removeTags = jsonDict["removeTags"] as? [String: String]
		searchable = jsonDict["searchable"] as? Bool ?? true
		tags = jsonDict["tags"] as! [String: String]
		if let terms = jsonDict["terms"] as? String {
			self.terms = terms.split(separator: ",").map({ String($0) })
		} else {
			terms = jsonDict["terms"] as? [String] ?? jsonDict["matchNames"] as? [String] ?? []
		}
		aliases = (jsonDict["aliases"] as? String)?.split(separator: "\n").map({ String($0) }) ?? []

		nsiSuggestion = isNSI
	}

	class func convertLocationSet(_ locationSet: [String: [String]]?) -> [String: [String]]? {
		// convert locations to country codes
		guard var includes = locationSet?["include"] else { return nil }
		for i in 0..<includes.count {
			switch includes[i] {
			case "conus":
				includes[i] = "us"
			case "001":
				return nil
			default:
				continue
			}
		}
		return ["include": includes]
	}

	let nsiSuggestion: Bool // is from NSI
	var nsiLogo: UIImage? // from NSI imageURL

	var _iconUnscaled: UIImage? = PresetFeature.uninitializedImage
	var _iconScaled24: UIImage? = PresetFeature.uninitializedImage

	var description: String {
		return featureID
	}

	func isGeneric() -> Bool {
		return featureID == "point" ||
			featureID == "line" ||
			featureID == "area"
	}

	func friendlyName() -> String {
		return name ?? featureID
	}

	func summary() -> String? {
		let parentID = PresetFeature.parentIDofID(featureID)
		let result = PresetsDatabase.shared.inheritedValueOfFeature(parentID, fieldGetter: { $0.name })
		return result as? String
	}

	func iconUnscaled() -> UIImage? {
		if _iconUnscaled == PresetFeature.uninitializedImage {
			_iconUnscaled = icon != nil ? UIImage(named: icon!) : nil
		}
		return _iconUnscaled
	}

	func iconScaled24() -> UIImage? {
		if _iconScaled24 == PresetFeature.uninitializedImage {
			if let image = iconUnscaled() {
				_iconScaled24 = EditorMapLayer.IconScaledForDisplay(image)
			} else {
				_iconScaled24 = nil
			}
		}
		return _iconScaled24
	}

	func addTags() -> [String: String] {
		return _addTags ?? tags
	}

	func removeTags() -> [String: String] {
		return _removeTags ?? addTags()
	}

	class func parentIDofID(_ featureID: String) -> String? {
		if let range = featureID.range(of: "/", options: .backwards, range: nil, locale: nil) {
			return String(featureID.prefix(upTo: range.lowerBound))
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
		if let name = name,
		   let range = name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive])
		{
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

	func matchObjectTagsScore(_ objectTags: [String: String], geometry: GEOMETRY) -> Double {
		guard self.geometry.contains(geometry.rawValue) else { return 0.0 }

		var totalScore: Float = 1.0

		var seen = Set<String>()
		for (key, value) in tags {
			seen.insert(key)

			var v: String?
			if key.hasSuffix("*") {
				let c = String(key.dropLast())
				v = objectTags.first(where: { (key: String, _: String) -> Bool in
					key.hasPrefix(c)
				})?.value
			} else {
				v = objectTags[key]
			}
			if let v = v {
				if value == v {
					totalScore += matchScore
					continue
				}
				if value == "*" {
					totalScore += matchScore / 2
					continue
				}
			} else if key == "area", value == "yes", geometry == .AREA {
				totalScore += 0.1
				continue
			}
			return 0.0 // invalid match
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
			if let field = PresetsDatabase.shared.jsonFields[fieldName] as? [String: Any],
			   let key = field["key"] as? String,
			   let def = field["default"] as? String,
			   let geom = field["geometry"] as? [String],
			   geom.contains(geometry.rawValue)
			{
				result[key] = def
			}
		}
		return result
	}
}
