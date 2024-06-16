//
//  OsmTags.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

// not used as a class yet, maybe someday
final class OsmTags {
	private static let PrettyTagExpr = try! NSRegularExpression(pattern: "^[abcdefghijklmnopqrstuvwxyz_:;]+$",
	                                                            options: [])

	class func PrettyTag(_ tag: String) -> String {
		if PrettyTagExpr.matches(in: tag, options: [], range: NSRange(location: 0, length: tag.utf16.count)).count > 0 {
			return tag.replacingOccurrences(of: "_", with: " ").capitalized
		}
		return tag
	}

	class func isOsmBooleanTrue(_ value: String?) -> Bool {
		switch value {
		case "true", "yes", "1":
			return true
		default:
			return false
		}
	}

	class func isOsmBooleanFalse(_ value: String?) -> Bool {
		switch value {
		case "false", "no", "0":
			return true
		default:
			return false
		}
	}

	class func isKey(_ key: String, variantOf baseKey: String) -> Bool {
		return key == baseKey || key.hasSuffix(":" + baseKey) || key.hasPrefix(baseKey + ":")
	}

	static let surveyDateSynonyms: Set<String> = [
		"check_date",
		"survey_date",
		"survey:date",
		"survey",
		"lastcheck",
		"last_checked",
		"updated",
		"checked_exists:date"
	]

	// editing
	static let tagsToAutomaticallyStrip: Set<String> =
		["tiger:upload_uuid",
		 "tiger:tlid",
		 "tiger:source",
		 "tiger:separated",
		 "geobase:datasetName",
		 "geobase:uuid",
		 "sub_sea:type",
		 "odbl",
		 "odbl:note",
		 "yh:LINE_NAME",
		 "yh:LINE_NUM",
		 "yh:STRUCTURE",
		 "yh:TOTYUMONO",
		 "yh:TYPE",
		 "yh:WIDTH_RANK"]

	static func IsInterestingKey(_ key: String) -> Bool {
		if key == "attribution" ||
			key == "created_by" ||
			key == "source" ||
			key == "odbl" ||
			key.hasPrefix("tiger:") ||
			key.hasPrefix("source:") ||
			key.hasPrefix("source_ref") ||
			OsmTags.tagsToAutomaticallyStrip.contains(key)
		{
			return false
		}
		return true
	}

	static func StringTruncatedTo255(_ s: String) -> String {
		if s.count < 256 {
			return s
		} else {
			return String(s.prefix(255))
		}
	}

	static func DictWithTagsTruncatedTo255(_ tags: [String: String]) -> [String: String] {
		var newDict = [String: String](minimumCapacity: tags.count)
		for (key, value) in tags {
			let keyInternal = StringTruncatedTo255(key)
			let valueInternal = StringTruncatedTo255(value)
			newDict[keyInternal] = valueInternal
		}
		return newDict
	}

	// result is nil only if allowConflicts==false
	static func Merge(ourTags: [String: String], otherTags: [String: String],
	                  allowConflicts: Bool) -> [String: String]?
	{
		guard !ourTags.isEmpty else { return otherTags }
		guard !otherTags.isEmpty else { return ourTags }

		var merged = ourTags
		for (otherKey, otherValue) in otherTags {
			let ourValue = merged[otherKey]
			if ourValue == nil || allowConflicts {
				merged[otherKey] = otherValue
			} else if ourValue == otherValue {
				// we already have it but replacement is the same
			} else if OsmTags.IsInterestingKey(otherKey) {
				// conflict, so return error
				return nil
			} else {
				// we don't allow conflicts, but its not an interesting key/value so just ignore the conflict
			}
		}
		return merged
	}

	static func convertWikiUrlToReference(withKey key: String, value url: String) -> String? {
		if key.hasPrefix("wikipedia") || key.hasSuffix(":wikipedia") {
			// if the value is for wikipedia then convert the URL to the correct format
			// format is https://en.wikipedia.org/wiki/Nova_Scotia
			let scanner = Scanner(string: url)
			var languageCode: NSString?
			var pageName: NSString?
			if scanner.scanString("https://", into: nil) || scanner.scanString("http://", into: nil),
			   scanner.scanUpTo(".", into: &languageCode),
			   scanner.scanString(".m", into: nil) || true,
			   scanner.scanString(".wikipedia.org/wiki/", into: nil),
			   scanner.scanUpTo("/", into: &pageName),
			   scanner.isAtEnd,
			   let languageCode = languageCode as String?,
			   let pageName = pageName as String?,
			   languageCode.count == 2, pageName.count > 0
			{
				return "\(languageCode):\(pageName)"
			}
		} else if key.hasPrefix("wikidata") || key.hasSuffix(":wikidata") {
			// https://www.wikidata.org/wiki/Q90000000
			let scanner = Scanner(string: url)
			var pageName: NSString?
			if scanner.scanString("https://", into: nil) || scanner.scanString("http://", into: nil),
			   scanner.scanString("www.wikidata.org/wiki/", into: nil) || scanner
			   .scanString("m.wikidata.org/wiki/", into: nil),
			   scanner.scanUpTo("/", into: &pageName),
			   scanner.isAtEnd,
			   let pageName = pageName as String?,
			   pageName.count > 0
			{
				return pageName
			}
		}
		return nil
	}

	static func convertWebsiteValueToHttps(withKey key: String, value url: String) -> String? {
		guard isKey(key, variantOf: "website") else {
			// not a website value
			return nil
		}
		if url.hasPrefix("http://") || url.hasPrefix("https://") {
			// great
			return nil
		}
		if url.contains("://") {
			// weird, so we'll ignore it
			return nil
		}
		return "https://" + url
	}

	static func fixUpOpeningHours(withKey key: String, value: String) -> String? {
		guard Self.isKey(key, variantOf: "opening_hours") else {
			return nil
		}
		var value = value
		// Replace days of week with correct capitalizations and normalize times
		let scanner = Scanner(string: value)
		scanner.charactersToBeSkipped = nil
		value = ""
		var timeSet = CharacterSet.decimalDigits
		timeSet.insert(":")
		while !scanner.isAtEnd {
			func fixTime(_ t: String) -> String? {
				let a = t.components(separatedBy: ":")
				if a.count == 1,
				   let hour = Int(a[0]),
				   hour >= 0,
				   hour <= 24
				{
					return String(format: "%02d:00", hour)
				} else if a.count == 2,
				          let hour = Int(a[0]),
				          let min = Int(a[1]),
				          hour >= 0,
				          hour <= 24,
				          min >= 0,
				          min < 60
				{
					return String(format: "%02d:%02d", hour, min)
				} else {
					return nil
				}
			}

			// check for time range
			var t1, dash, t2: NSString?
			if scanner.scanCharacters(from: timeSet, into: &t1),
			   let t1 = t1 as? String,
			   scanner.scanString("-", into: &dash),
			   scanner.scanCharacters(from: timeSet, into: &t2),
			   let t2 = t2 as? String,
			   let f1 = fixTime(t1),
			   let f2 = fixTime(t2)
			{
				value += f1 + "-" + f2
				continue
			}
			value += (t1 as? String) ?? ""
			value += (dash as? String) ?? ""
			value += (t2 as? String) ?? ""

			// check for a day
			var str: NSString?
			if scanner.scanCharacters(from: CharacterSet.letters, into: &str),
			   let str = str as String?
			{
				let days = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
				if let index = days.firstIndex(where: { $0.lowercased() == str.lowercased() }) {
					value += days[index]
				} else {
					value += str
				}
				continue
			}

			// consume anything else
			if scanner.scanUpToCharacters(from: CharacterSet.letters.union(timeSet), into: &str) {
				value += (str as String?) ?? ""
			}
		}
		// remove any repeating spaces
		value = value.replacingOccurrences(of: "  ", with: " ")

		// remove spaces following commas
		value = value.replacingOccurrences(of: ", ", with: ",")

		// put a space in front of days that follow a time and comma
		if #available(iOS 16.0, *) {
			let regex = try! Regex("[0-9][0-9]:[0-9][0-9],[MTWFS]")
			while let match = try? regex.firstMatch(in: value) {
				let spacePos = value.index(match.range.upperBound, offsetBy: -1)
				value.insert(" ", at: spacePos)
			}
		}

		return value
	}

	static func numericPortionOf(text: String?) -> String? {
		if let number = text?.split(separator: " ").first(where: { Double($0) != nil }) {
			return number.isEmpty ? nil : String(number)
		}
		return nil
	}

	static func alphabeticPortionOf(text: String?) -> String? {
		if let alphaList = text?.split(separator: " ").compactMap({ $0 != "" && Double($0) == nil ? $0 : nil }),
		   alphaList.count > 0
		{
			return alphaList.joined(separator: " ")
		}
		return nil
	}

	struct UnitValue {
		let label: String // localized label that will appear on a button (e.g. "m" or "ft")
		let values: [String] // possible OSM values, in order of preference
	}

	static func unitsFor(key: String) -> [UnitValue]? {
		switch key {
		case "distance":
			return [UnitValue(label: NSLocalizedString("km", comment: "Distance in kilometers, please abbreviate"),
			                  values: ["", "km"]),
			        UnitValue(label: NSLocalizedString("mi", comment: "Distance in miles, please abbreviate"),
			                  values: ["mi"])]

		case "ele",
		     "height",
		     "maxheight",
		     "building:height",
		     "roof:height",
		     "width",
		     "maxwidth",
		     "length",
		     "maxlength":
			return [UnitValue(label: NSLocalizedString("m", comment: "Height or width in meters, please abbreviate"),
			                  values: ["", "m"]),
			        UnitValue(label: NSLocalizedString("ft", comment: "Height or width in feet, please abbreviate"),
			                  values: ["ft"])]

		case "seamark:light:range",
		     "siren:range":
			return nil // defaults to nmi: nautical miles

		case "maxspeed",
		     "maxspeed:forward",
		     "maxspeed:backward":
			return [UnitValue(label: NSLocalizedString("km/h", comment: "kilometers per hour speed, please abbreviate"),
			                  values: [""]),
			        UnitValue(label: NSLocalizedString("mph", comment: "miles per hour speed, please abbreviate"),
			                  values: ["mph"])]

		case "maxweight":
			return [UnitValue(label: NSLocalizedString("t", comment: "Weight in metric tons, please abbreviate"),
			                  values: ["", "t"]),
			        UnitValue(label: NSLocalizedString("lbs", comment: "Weight in pounds, please abbreviate"),
			                  values: ["lbs"]),
			        UnitValue(label: NSLocalizedString("kg", comment: "Weight in kilograms, please abbreviate"),
			                  values: ["kg"]),
			        UnitValue(label: NSLocalizedString("st", comment: "Weight in short tons, please abbreviate"),
			                  values: ["st"]),
			        UnitValue(label: NSLocalizedString("lt", comment: "Weight in long tons, please abbreviate"),
			                  values: ["lt"])]

		case "power":
			return nil

		case "pressure":
			return nil

		default:
			return nil
		}
	}
}
