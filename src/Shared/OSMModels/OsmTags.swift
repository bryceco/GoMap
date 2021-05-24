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
}
