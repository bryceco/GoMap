//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

extension PresetsDatabase
{
	struct Feature {
		let addTags : [ String : String ]?
		let countryCodes : [ String ]?
		let geometry : [ String ]?
		let icon : String?
		let imageURL : String?
		let matchScore : Double?
		let name : String?
		let reference : [ String : String ]?
		let suggestion : Int?
		let tags : [ String : String ]?
		let terms : [ String ]?
	}

	private static func convertStringDict( _ jsonDict : NSDictionary? ) -> [ String : String ]?
	{
		if let jsonDict = jsonDict {
			var newDict = [String:String]()
			for (key,value) in jsonDict {
				let newKey : String = key as! String
				let newValue : String = value as! String
				newDict[newKey] = newValue
			}
			return newDict
		}
		return nil
	}

	private static func convertStringArray( _ jsonArray : NSArray? ) -> [String]?
	{
		if let jsonArray = jsonArray {
			return (jsonArray as! [String]).map { (s) -> String in
				return s as String
			}
		}
		return nil
	}

	private static func convertFeatureToSwift( _ jsonDict : NSDictionary ) -> Feature?
	{
		let addTags = convertStringDict( jsonDict["addTags"] as? NSDictionary )
		let countryCodes = jsonDict["countryCodes"] as? [String]
		let geometry = jsonDict["geometry"] as? [String]
		let icon = jsonDict["icon"] as? String
		let imageURL = jsonDict["imageURL"] as? String
		let matchScore = jsonDict["matchScore"] as? Double
		let name = jsonDict["name"] as? String
		let reference = convertStringDict( jsonDict["reference"] as? NSDictionary )
		let suggestion = jsonDict["suggestion"] as? Int
		let tags = convertStringDict( jsonDict["tags"] as? NSDictionary )
		let terms = jsonDict["terms"] as? [String]
		let feature = Feature(addTags: addTags,
							  countryCodes: countryCodes,
							  geometry: geometry,
							  icon: icon,
							  imageURL: imageURL,
							  matchScore: matchScore,
							  name: name,
							  reference: reference,
							  suggestion: suggestion,
							  tags: tags,
							  terms: terms)
		return feature
	}

	private static func convertToSwift( _ jsonDict : NSDictionary ) -> [ String : Feature ]
	{
		var featureDict = [String:Feature]()

		for (name, dict) in jsonDict {
			let name2 : String = name as! String
			let dict2 : NSDictionary = dict as! NSDictionary
			let feature = convertFeatureToSwift(dict2)
			featureDict[name2] = feature
		}
		return featureDict
	}

	private static var presetsDict : [ String : Feature ]? = nil

	@objc static func featureNameForObjectDictSwift( _ dict : NSDictionary,
													 countryCode : String?,
													 objectTags : [String:String]?,
													 geometry:NSString) -> String?
	{
		guard let objectTags = convertStringDict( objectTags as NSDictionary? ) else { return nil }

		var bestMatchScore = 0.0
		var bestMatchName : String? = nil

		if presetsDict == nil {
			presetsDict = convertToSwift( dict )
		}

		nextFeature:
		for ( featureName, dict ) in presetsDict! {

			if let countryCode = countryCode,
				let countryCodes = dict.countryCodes,
				!countryCodes.contains(countryCode)
			{
				continue
			}

			var totalScore = 0.0
			if let geom = dict.geometry,
				geom.contains(geometry as String)
			{
				totalScore = 1
			} else {
				continue
			}

			let matchScore = dict.matchScore == nil ? 1.0 : dict.matchScore!

			guard let keyvals = dict.tags else { continue }

			var seen = Set<String>()
			for (key,value) in keyvals {
				seen.insert(key)

				var v : String?
				if key.hasSuffix("*") {
					let c = String(key.dropLast())
					v = objectTags.first(where: { (key: String, value: String) -> Bool in
						return key.hasPrefix(c)
					})?.value
				} else {
					v = objectTags[ key ]
				}
				if let v = v {
					if value == v {
						totalScore += matchScore
						continue
					}
					if value == "*" {
						totalScore += matchScore/2
						continue
					}
				} else if key == "area" && value == "yes" && geometry == "area" {
					totalScore += 0.1
					continue
				}
				continue nextFeature	// invalid match
			}

			// boost score for additional matches in addTags
			if let addTags = dict.addTags {
				for (key,val) in addTags {
					if !seen.contains(key) && objectTags[key] == val {
						totalScore += matchScore;
					}
				}
			}

			if totalScore > bestMatchScore {
				bestMatchName = featureName
				bestMatchScore = totalScore
			}
		}
		return bestMatchName
	}


}
