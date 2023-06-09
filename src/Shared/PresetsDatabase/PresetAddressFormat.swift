//
//  PresetAddressFormat.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/22/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

struct PresetAddressFormat {
	let countryCodes: [String]?
	let addressKeys: [String]

	init(withJson json: [String: Any]) {
		countryCodes = json["countryCodes"] as! [String]?
		addressKeys = (json["format"] as! [[String]]).flatMap({ $0 })
	}
}
