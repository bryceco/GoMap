//
//  PresetsDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation


@objc class PresetsDatabase : NSObject {

	@objc static var shared = PresetsDatabase()
	@objc class func reload()
	{
		// called when language changes
		shared = PresetsDatabase()
	}

	// these map a FeatureID to a feature
	let stdPresets : [String :PresetFeature]	// only generic presets
	var nsiPresets : [String :PresetFeature]	// only NSI presets
	// these map a tag key to a list of features that require that key
	let stdIndex : [String: [PresetFeature]]	// generic preset index
	var nsiIndex : [String: [PresetFeature]]	// generic+NSI index

	private class func DictionaryForFile(_ file: String?) -> Any? {
		guard let file = file else { return nil }
		let rootDir = Bundle.main.resourcePath!
		let rootPresetPath = rootDir + "/presets/" + file
		guard let rootPresetData = NSData(contentsOfFile: rootPresetPath) as Data? else { return nil }
		do {
			let dict = try JSONSerialization.jsonObject(with: rootPresetData, options: [])
			return dict
		} catch {
		}
		return nil
	}

	private class func Translate(_ orig: Any?, _ translation: Any?) -> Any? {
		guard let translation = translation else {
			return orig
		}
		if (orig is String) && (translation is String) {
			if (translation as! String).hasPrefix("<") {
				return orig // meta content
			}
			return translation
		}
		if let origArray = orig as? [AnyHashable] {
			if let translation = translation as? [AnyHashable : Any] {
				var newArray = [AnyHashable]()
				newArray.reserveCapacity(origArray.count)
				for i in 0..<origArray.count {
					let o = translation[NSNumber(value: i)] ?? origArray[i]
					newArray[i] = o as! AnyHashable
				}
				return newArray
			} else if let translation = translation as? String {
				let a = translation.components(separatedBy: ",")
				return a
			 } else {
				 return origArray
			 }
		}

		if let orig = orig as? [String:Any],
		   let translation = translation as? [String:Any]
		{
			var newDict = [String:Any]()
			for (key,obj) in orig {
				if key == "strings" {
					// for "strings" the translation skips a level
					newDict[key] = Translate( obj, translation )
				} else {
					newDict[key] = Translate( obj, translation[key] )
				}
			}
			return newDict
		}
		return orig
	}

	@objc let jsonAddressFormats: [Any]				 	// address formats for different countries
	@objc let jsonDefaults: [String : Any] 				// map a geometry to a set of features/categories
	@objc let jsonCategories: [String : Any]	 		// map a top-level category ("building") to a set of specific features ("building/retail")
	@objc let jsonFields: [String : Any]				// possible values for a preset key ("oneway=")

	@objc let yesForLocale: String
	@objc let noForLocale: String

	override init() {
		// get translations for current language
		let presetLanguages = PresetLanguages() // don't need to save this, it doesn't get used again unless user changes the language
		let code = presetLanguages.preferredLanguageCode()
		let file = "translations/"+code+".json"
		let trans = PresetsDatabase.DictionaryForFile(file) as! [String : [String : Any]]
		let jsonTranslation	= (trans[ code ]?[ "presets" ] as? [String : [String : Any]]) ?? [String:[String:Any]]()
		let yesNoDict = ((jsonTranslation["fields"])?["internet_access"] as? [String:Any])?["options"] as? [String:String]
		yesForLocale = yesNoDict?[ "yes" ] ?? "Yes"
		noForLocale  = yesNoDict?[ "no" ] ?? "No"

		// get presets files
		let jsonDefaultsPre 	= PresetsDatabase.DictionaryForFile("preset_defaults.json")!
		let jsonCategoriesPre 	= PresetsDatabase.DictionaryForFile("preset_categories.json")!
		let jsonFieldsPre 		= PresetsDatabase.DictionaryForFile("fields.json")!
		jsonDefaults	= (PresetsDatabase.Translate( jsonDefaultsPre,		jsonTranslation["defaults"] ) as? [String : Any])!
		jsonCategories	= (PresetsDatabase.Translate( jsonCategoriesPre,	jsonTranslation["categories"] ) as? [String : Any])!
		jsonFields		= (PresetsDatabase.Translate( jsonFieldsPre,		jsonTranslation["fields"] ) as? [String : Any])!

		// address formats
		jsonAddressFormats	 	= PresetsDatabase.DictionaryForFile("address_formats.json") as! [Any]

		// initialize presets and index them
		var jsonPresetsDict		= PresetsDatabase.DictionaryForFile("presets.json")
		jsonPresetsDict			= PresetsDatabase.Translate( jsonPresetsDict, jsonTranslation["presets"] )
		stdPresets 	= PresetsDatabase.featureDictForJsonDict(jsonPresetsDict as! [String : [String:Any]], isNSI:false)
		stdIndex 	= PresetsDatabase.buildTagIndex([stdPresets], basePresets: stdPresets)

		// name suggestion index
		nsiPresets = [String: PresetFeature]()
		nsiIndex   = stdIndex
		super.init()
		DispatchQueue.global(qos: .userInitiated).async {
			let jsonNsiPresetsDict 	= PresetsDatabase.DictionaryForFile("nsi_presets.json")
			let nsiPresets2 = PresetsDatabase.featureDictForJsonDict(jsonNsiPresetsDict as! [String : [String:Any]], isNSI:true)
			let nsiIndex2 	= PresetsDatabase.buildTagIndex([self.stdPresets,nsiPresets2], basePresets: self.stdPresets)
			DispatchQueue.main.async {
				self.nsiPresets = nsiPresets2
				self.nsiIndex 	= nsiIndex2
			}
		}
	}

	// initialize presets database
	private class func featureDictForJsonDict(_ dict:[String:[String:Any]], isNSI:Bool) -> [String:PresetFeature]
	{
		var presets = [String :PresetFeature]()
		for (name,values) in dict {
			presets[name] = PresetFeature(withID: name, jsonDict: values, isNSI:isNSI)
		}
		return presets
	}
	class func buildTagIndex(_ inputList:[[String:PresetFeature]], basePresets:[String:PresetFeature]) -> [String:[PresetFeature]]
	{
		var keys = [String:Int]()
		for (featureID,_) in basePresets {
			var key = featureID
			if let range = key.range(of:"/") {
				key = String(key.prefix(upTo: range.lowerBound))
			}
			keys[key] = (keys[key] ?? 0) + 1
		}
		var tagIndex = [String:[PresetFeature]]()
		for list in inputList {
			for (_,feature) in list {
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
	@objc func enumeratePresetsUsingBlock(_ block:(_ feature: PresetFeature) -> Void) {
		for (_,v) in stdPresets {
			block(v)
		}
	}
	@objc func enumeratePresetsAndNsiUsingBlock(_ block:(_ feature: PresetFeature) -> Void) {
		for (_,v) in stdPresets {
			block(v)
		}
		for (_,v) in nsiPresets {
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
	@objc func inheritedValueOfFeature( _ featureID: String?,
										valueGetter: @escaping (_ feature: PresetFeature?) -> AnyHashable? )
										-> AnyHashable?
	{
		// This is currently never used for NSI entries, so we can ignore nsiPresets
		return PresetsDatabase.inheritedFieldForPresetsDict(stdPresets, featureID: featureID, field: valueGetter)
	}


	@objc func presetFeatureForFeatureID(_ featureID:String) -> PresetFeature?
	{
		return stdPresets[featureID] ?? nsiPresets[featureID]
	}

	@objc func matchObjectTagsToFeature(_ objectTags: [String: String]?,
												 geometry: String?,
												 includeNSI: Bool) -> PresetFeature?
	{
		guard let geometry = geometry,
			  let objectTags = objectTags else { return nil }

		var bestFeature: PresetFeature? = nil
		var bestScore: Double = 0.0

		let index = includeNSI ? nsiIndex : stdIndex
		let keys = objectTags.keys + [""]
		for key in keys {
			if let list = index[key] {
				for feature in list {
					let score = feature.matchObjectTagsScore(objectTags, geometry: geometry)
					if score > bestScore {
						bestScore = score
						bestFeature = feature
					}
				}
			}
		}
		return bestFeature
	}

	@objc func featuresMatchingSearchText(_ searchText:String?, country:String? ) -> [PresetFeature]
	{
		var list = [PresetFeature]()
		enumeratePresetsAndNsiUsingBlock { (feature) in
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
