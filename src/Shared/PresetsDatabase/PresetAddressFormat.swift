//
//  PresetAddressFormat.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/22/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

struct PresetAddressFormat: Decodable {
	let countryCodes: [String]?
	let addressKeys: [[String]]

	enum CodingKeys: String, CodingKey {
		case countryCodes
		case addressKeys = "format"
	}
}
