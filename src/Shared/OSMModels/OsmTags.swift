//
//  OsmTags.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

// not used as a class yet, maybe someday
final class OsmTags : NSObject {

	static private let PrettyTagExpr: NSRegularExpression = {
		do {
			let e = try NSRegularExpression(
					pattern: "^[abcdefghijklmnopqrstuvwxyz_:;]+$",
					options: [])
			 return e
		} catch {
			 abort()
		}
	}()

	class func PrettyTag(_ tag: String) -> String {
		if PrettyTagExpr.matches(in: tag, options: [], range: NSRange(location: 0, length: tag.count)).count > 0 {
			return tag.replacingOccurrences(of: "_", with: " ").capitalized
		}
		return tag
	}

	@objc class func isOsmBooleanTrue(_ value: String?) -> Bool {
		switch value {
			case "true", "yes", "1":
				return true
			default:
				return false
		}
	}

	@objc class func isOsmBooleanFalse(_ value: String?) -> Bool {
		switch value {
			case "false", "no", "0":
				return true
			default:
				return false
		}
	}


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

	@objc
	static func IsInterestingKey(_ key: String) -> Bool {
		if key == "attribution" ||
			key == "created_by" ||
			key == "source" ||
			key == "odbl"	||
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
		guard s.count < 256 else {
			return s
		}
		return String(s.prefix( 255 ))
	}

	static func DictWithTagsTruncatedTo255(_ tags: [String : String]) -> [String : String] {
		var newDict = [String : String](minimumCapacity: (tags.count))
		for (key, value) in tags {
			let keyInternal = StringTruncatedTo255(key)
			let valueInternal = StringTruncatedTo255(value)
			newDict[keyInternal] = valueInternal
		}
		return newDict
	}

	// result is nil only if allowConflicts==false
	static func Merge(ourTags: [String : String], otherTags: [String : String], allowConflicts: Bool) -> [String : String]? {
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
}
