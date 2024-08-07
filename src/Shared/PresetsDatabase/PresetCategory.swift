//
//  PresetCategory.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

// A top-level group such as road, building, for building hierarchical menus
final class PresetCategory {
	let categoryID: String
	let name: String
	let members: [PresetFeature]

	var friendlyName: String? {
		return name
	}

	var icon: UIImage? {
		return nil
	}

	init(withID categoryID: String, json: Any, presets: [String: PresetFeature]) {
		let dict = json as! [String: Any]
		self.categoryID = categoryID
		name = dict["name"] as? String ?? categoryID
		members = (dict["members"] as! [String]).map({
			presets[$0]!
		})
	}
}
