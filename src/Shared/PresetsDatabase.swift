//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

// A feature-defining tag such as amenity=shop
@objc class PresetFeature: NSObject {

	static let uninitializedImage = UIImage()

	@objc let featureID: String

	// from json dictionary:
	let _addTags: [String : String]?
	@objc let fields: [String]?
	@objc let geometry: [String]?
	let icon: String?							// icon on the map
	@objc let logoURL: String?					// NSI brand image
	let locationSet: [String: [String]]?
	let matchScore: Double
	@objc let moreFields: [String]?
	@objc let name: String?
	let reference: [String : String]?
	let _removeTags: [String : String]?
	let searchable: Bool
	@objc let tags: [String : String]
	let terms: [String]?

	init(withID featureID:String, jsonDict:[String:Any], isNSI:Bool)
	{
		self.featureID = featureID

		self._addTags = jsonDict["addTags"] as? [String: String]
		self.fields = jsonDict["fields"] as? [String]
		self.geometry = jsonDict["geometry"] as? [String]
		self.icon = jsonDict["icon"] as? String
		self.logoURL = jsonDict["imageURL"] as? String
		self.locationSet = PresetFeature.convertLocationSet( jsonDict["locationSet"] as? [String: [String]] )
		self.matchScore = jsonDict["matchScore"] as? Double ?? 1.0
		self.moreFields = jsonDict["moreFields"] as? [String]
		self.name = jsonDict["name"] as? String
		self.reference = jsonDict["reference"] as? [String : String]
		self._removeTags = jsonDict["removeTags"] as? [String: String]
		self.searchable = jsonDict["searchable"] as? Bool ?? true
		self.tags = jsonDict["tags"] as! [String: String]
		self.terms = jsonDict["terms"] as? [String]

		self.nsiSuggestion = isNSI
	}

	class func convertLocationSet( _ locationSet:[String:[String]]? ) -> [String:[String]]?
	{
		// convert locations to country codes
		guard var includes = locationSet?["include"] else { return nil }
		for i in 0 ..< includes.count {
			switch includes[i] {
			case "conus":
				includes[i] = "us"
			case "001":
				return nil
			default:
				continue
			}
		}
		return ["include":includes]
	}

	@objc let nsiSuggestion: Bool		// is from NSI
	@objc var nsiLogo: UIImage? = nil	// from NSI imageURL

	var _iconUnscaled: UIImage? = PresetFeature.uninitializedImage
	var _iconScaled24: UIImage? = PresetFeature.uninitializedImage

	@objc func friendlyName() -> String
	{
		return self.name ?? self.featureID
	}

	@objc func summary() -> String? {
		let parentID = PresetFeature.parentIDofID( self.featureID )
		let result = PresetsDatabase.inheritedValueOfFeature(parentID,
			valueGetter: { (feature:PresetFeature?) -> AnyHashable? in return feature!.name })
		return result as? String
	}

	@objc func iconUnscaled() -> UIImage? {
		if _iconUnscaled == PresetFeature.uninitializedImage {
			_iconUnscaled = self.icon != nil ? UIImage(named: self.icon!) : nil
		}
		return _iconUnscaled
	}
	@objc func iconScaled24() -> UIImage?
	{
		if _iconScaled24 == PresetFeature.uninitializedImage {
			_iconScaled24 = IconScaledForDisplay( self.iconUnscaled() )
		}
		return _iconScaled24
	}

	@objc func addTags() -> [String : String]? {
		return self._addTags ?? self.tags
	}

	@objc func removeTags() -> [String : String]? {
		return self._removeTags ?? self.addTags()
	}

	class func parentIDofID(_ featureID:String) -> String?
	{
		if let range = featureID.range(of: "/", options: .backwards, range: nil, locale: nil) {
			return String( featureID.prefix(upTo: range.lowerBound) )
		}
		return nil
	}

	@objc func matchesSearchText(_ searchText: String?) -> Bool {
		guard let searchText = searchText else {
			return false
		}
		if self.featureID.range(of: searchText, options: .caseInsensitive) != nil {
			return true
		}
		if self.name?.range(of: searchText, options: .caseInsensitive) != nil {
			return true
		}
		if let terms = self.terms {
			for term in terms {
				if term.range(of: searchText, options: .caseInsensitive) != nil {
					return true
				}
			}
		}
		return false
	}
}


@objc class PresetsDatabase : NSObject {

	static var stdPresets : [String :PresetFeature]?
	static var nsiPresets : [String :PresetFeature]?

	// initialize database
	private class func featureDictForJsonDict(_ dict:NSDictionary, isNSI:Bool) -> [String:PresetFeature]
	{
		var presets = [String :PresetFeature]()
		let dict2 = dict as! [String:[String:Any]]
		for (name,values) in dict2 {
			presets[name] = PresetFeature(withID: name, jsonDict: values, isNSI:isNSI)
		}
		return presets
	}
	@objc class func initializeWith(presetsDict:NSDictionary, nsiPresetsDict:NSDictionary)
	{
		stdPresets 	= featureDictForJsonDict(presetsDict, isNSI:false)
		nsiPresets 	= featureDictForJsonDict(nsiPresetsDict, isNSI:true)
	}

	// enumerate contents of database
	@objc class func enumeratePresetsUsingBlock(_ block:(_ feature: PresetFeature) -> Void) {
		for (_,v) in stdPresets! {
			block(v)
		}
	}
	@objc class func enumeratePresetsAndNsiUsingBlock(_ block:(_ feature: PresetFeature) -> Void) {
		for (_,v) in stdPresets! {
			block(v)
		}
		for (_,v) in nsiPresets! {
			block(v)
		}
	}

	// go up the feature tree and return the first instance of the requested field value
	private class func inheritedFieldForPresetsDict( _ presetDict: [String:PresetFeature],
													 featureID: String?,
													 field fieldGetter: @escaping (_ feature: PresetFeature?) -> AnyHashable? )
													-> AnyHashable?
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
	@objc class func inheritedValueOfFeature( _ featureID: String?,
											  valueGetter: @escaping (_ feature: PresetFeature?) -> AnyHashable? )
											-> AnyHashable?
	{
		// This is currently never used for NSI entries, so we can ignore nsiPresets
		return PresetsDatabase.inheritedFieldForPresetsDict(stdPresets!, featureID: featureID, field: valueGetter)
	}


	@objc class func presetFeatureForFeatureID(_ featureID:String) -> PresetFeature?
	{
		return stdPresets![featureID] ?? nsiPresets![featureID]
	}

	private static func matchObjectTagsToFeature(_ presetsDict: [String:PresetFeature],
												 objectTags: [String: String]?,
												 geometry: NSString)
												-> (feature:PresetFeature?,score:Double)
    {
		guard let objectTags = objectTags else { return (nil,0.0) }

		var bestMatchScore = 0.0
		var bestMatchFeature: PresetFeature? = nil

		nextFeature:
		for (_, preset) in presetsDict {

			var totalScore = 0.0
			if let geom = preset.geometry,
				geom.contains(geometry as String)
			{
				totalScore = 1
			} else {
				continue
			}

			var seen = Set<String>()
			for (key, value) in preset.tags {
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
						totalScore += preset.matchScore
						continue
					}
					if value == "*" {
						totalScore += preset.matchScore / 2
						continue
					}
				} else if key == "area", value == "yes", geometry == "area" {
					totalScore += 0.1
					continue
				}
				continue nextFeature // invalid match
			}

			// boost score for additional matches in addTags
			if let addTags = preset._addTags {
				for (key, val) in addTags {
					if !seen.contains(key), objectTags[key] == val {
						totalScore += preset.matchScore
					}
				}
			}

			if totalScore > bestMatchScore {
				bestMatchFeature = preset
				bestMatchScore = totalScore
			}
		}
		return (bestMatchFeature,bestMatchScore)
	}
	@objc static func matchObjectTagsToFeature(_ objectTags: [String: String]?,
												 geometry: NSString,
												 includeNSI: Bool) -> PresetFeature?
	{
		let (feature,score) = matchObjectTagsToFeature(stdPresets!, objectTags: objectTags, geometry: geometry)
		if includeNSI {
			let (feature2,score2) = matchObjectTagsToFeature(nsiPresets!, objectTags: objectTags, geometry: geometry)
			if score2 > score {
				return feature2
			}
		}
		return feature
	}

	@objc static func featuresMatchingSearchText(_ searchText:String?, country:String? ) -> [PresetFeature]
	{
		var list = [PresetFeature]()
		PresetsDatabase.enumeratePresetsAndNsiUsingBlock { (feature:PresetFeature) in
			if feature.searchable {
				if let country = country,
				   let loc = feature.locationSet,
				   let includes = loc["include"]
				{
					if !includes.contains(country) {
						return
					}
				}
				if feature.matchesSearchText(searchText) {
					list.append(feature)
				}
			}
		}
		return list
	}
}
