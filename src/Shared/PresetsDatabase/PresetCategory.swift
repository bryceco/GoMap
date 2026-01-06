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
	let members: [PresetFeature]
	let iconName: String

	lazy var icon: UIImage? = UIImage(named: iconName)?.scaledTo(width: 50.0, height: nil)

	init(withID categoryID: String, json: Any, presets: [String: PresetFeature]) {
		let dict = json as! [String: Any]
		self.categoryID = categoryID
		self.iconName = dict["icon"] as! String
		members = (dict["members"] as! [String]).map({
			presets[$0]!
		})
	}
}
