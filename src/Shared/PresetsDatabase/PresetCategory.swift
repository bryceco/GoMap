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

	var friendlyName: String? {
		let dict = PresetsDatabase.shared.jsonCategories[categoryID] as? [String : Any]
		return dict?["name"] as? String
	}

	var icon: UIImage? {
		return nil
	}

	init(categoryID: String) {
		self.categoryID = categoryID
		self.members = {
			guard let dict = PresetsDatabase.shared.jsonCategories[categoryID] as? [String : Any],
				  let members = dict["members"] as? [String]
				else { return [] }
			var result: [PresetFeature] = []
			for featureID in members {
				if let feature = PresetsDatabase.shared.presetFeatureForFeatureID(featureID) {
					result.append(feature)
				}
			}
			return result
		}()
	}
}

