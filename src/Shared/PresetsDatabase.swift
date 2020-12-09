//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

// A feature-defining tag such as amenity=shop
@objc @objcMembers class PresetFeature: NSObject {

	static let missingImage = UIImage()

	let featureName: String

	// from json dictionary:
	let _addTags: [String : String]?
	let fields: [String]?
	let geometry: [String]?
	let icon: String?
	public let logoURL: String?
	let locationSet: [String: [String]]?
	let matchScore: Double
	let moreFields: [String]?
	let name: String?
	let reference: [String : String]?
	let _removeTags: [String : String]?
	let searchable: Bool
	let tags: [String : String]
	let terms: [String]?

	init(withName featureName:String, jsonDict:[String:Any], isNSI:Bool)
	{
		self.featureName = featureName

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

		self.suggestion = isNSI
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

	public var logoImage: UIImage?
	public var renderInfo: RenderInfo?
	public let suggestion: Bool

	var _imageUnscaled: UIImage?
	var _imageScaled24: UIImage?

	func friendlyName() -> String
	{
		return self.name ?? self.featureName
	}

	func summary() -> String? {
		let feature = PresetFeature.parentNameOfName( self.featureName )
		let result = PresetsDatabase.inheritedValueOfFeature(feature, value: { (feature:PresetFeature?) -> AnyHashable? in
			return feature!.name
		})
		return result as? String
	}

	func imageUnscaled() -> UIImage? {
		if _imageUnscaled == nil {
			_imageUnscaled = self.icon != nil ? UIImage(named: self.icon!) : nil
			if _imageUnscaled == nil {
				_imageUnscaled = PresetFeature.missingImage
			}
		}
		return _imageUnscaled == PresetFeature.missingImage ? nil : _imageUnscaled
	}

	func imageScaled24() -> UIImage?
	{
		if _imageScaled24 == nil {
			_imageScaled24 = self.imageUnscaled()
			if _imageScaled24 != nil {
				_imageScaled24 = IconScaledForDisplay( _imageScaled24 );
			} else {
				_imageScaled24 = PresetFeature.missingImage
			}
		}
		return _imageScaled24 == PresetFeature.missingImage ? nil : _imageScaled24
	}

	func addTags() -> [String : String]? {
		return self._addTags != nil ? self._addTags : self.tags
	}

	func removeTags() -> [String : String]? {
		return self._removeTags != nil ? self._removeTags : self.addTags()
	}

	class func parentNameOfName(_ name:String) -> String?
	{
		guard let range = name.range(of: "/", options: .backwards, range: nil, locale: nil) else {
			return nil
		}
		let s = name.prefix(upTo: range.lowerBound)
		return String(s)
	}
	func parentName() -> String?
	{
		return PresetFeature.parentNameOfName(self.featureName)
	}

	func matchesSearchText(_ searchText: String?) -> Bool {
		guard let searchText = searchText else {
			return false
		}
		if self.featureName.range(of: searchText, options: .caseInsensitive) != nil {
			return true
		}
		if self.friendlyName().range(of: searchText, options: .caseInsensitive) != nil {
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

	static var presets : [String :PresetFeature]?
	static var nsiPresets : [String :PresetFeature]?

	// initialize database
	private class func featureDictForJsonDict(_ dict:NSDictionary, isNSI:Bool) -> [String:PresetFeature]
	{
		var presets = [String :PresetFeature]()
		let dict2 = dict as! [String:[String:Any]]
		for (name,values) in dict2 {
			presets[name] = PresetFeature(withName: name, jsonDict: values, isNSI:isNSI)
		}
		return presets
	}
	@objc class func initializeWith(presetsDict:NSDictionary, nsiPresetsDict:NSDictionary)
	{
		presets 	= featureDictForJsonDict(presetsDict, isNSI:false)
		nsiPresets 	= featureDictForJsonDict(nsiPresetsDict, isNSI:true)
	}

	// enumerate contents of database
	@objc class func enumeratePresetsUsingBlock(_ block:(_ name: String, _ feature: PresetFeature) -> Void) {
		for (k,v) in presets! {
			block(k,v)
		}
	}
	@objc class func enumeratePresetsAndNsiUsingBlock(_ block:(_ name: String, _ feature: PresetFeature) -> Void) {
		for (k,v) in presets! {
			block(k,v)
		}
		for (k,v) in nsiPresets! {
			block(k,v)
		}
	}

	// go up the feature tree and return the first instance of the requested field value
	private class func inheritedFieldForPresetsDict( _ presetDict: [String:PresetFeature],
													 featureName: String?,
													 field fieldGetter: @escaping (_ feature: PresetFeature?) -> AnyHashable? )
													-> AnyHashable?
	{
		var featureName = featureName
		while featureName != nil {
			if let feature = presetDict[featureName!],
			   let field = fieldGetter(feature)
			{
				return field
			}
			featureName = PresetFeature.parentNameOfName(featureName!)
		}
		return nil
	}
	@objc class func inheritedValueOfFeature( _ featureName: String?,
											  value valueGetter: @escaping (_ feature: PresetFeature?) -> AnyHashable? )
											-> AnyHashable?
	{
		// This is currently never used for NSI entries, so we can ignore nsiPresets
		return PresetsDatabase.inheritedFieldForPresetsDict(presets!, featureName: featureName, field: valueGetter)
	}


	@objc class func presetFeatureForFeatureName(_ name:String) -> PresetFeature?
	{
		return presets![name]
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
		let (feature,score) = matchObjectTagsToFeature(presets!, objectTags: objectTags, geometry: geometry)
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
		PresetsDatabase.enumeratePresetsAndNsiUsingBlock { (_, feature:PresetFeature) in
			if feature.searchable {
				if let country = country,
				   let loc = feature.locationSet,
				   let includes = loc["include"],
				   includes.count > 0
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
