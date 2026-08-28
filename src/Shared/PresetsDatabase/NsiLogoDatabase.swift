//
//  NsiLogoDatabase.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/6/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

class NsiLogoDatabase {
	static let shared = NsiLogoDatabase()

	var logoCache = PersistentWebCache<UIImage>(name: "presetLogoCache",
	                                            memorySize: 5 * 1_000000,
	                                            daysToKeep: 30.0)

	// MARK: NSI Logo icon retrieval

	private func retrieveLogoFromBundle(featureID: String, whenFinished: @escaping (UIImage) -> Void) {
		// use built-in logo files
		DispatchQueue.global(qos: .default).async(execute: {
			var name = featureID.replacingOccurrences(of: "/", with: "_")
			name = "presets/brandIcons/" + name
			let path = Bundle.main.path(forResource: name, ofType: "jpg") ?? Bundle.main
				.path(forResource: name, ofType: "png") ?? Bundle.main
				.path(forResource: name, ofType: "gif") ?? Bundle.main
				.path(forResource: name, ofType: "bmp") ?? nil
			if let image = UIImage(contentsOfFile: path ?? "") {
				DispatchQueue.main.async(execute: {
					whenFinished(image)
				})
			}
		})
	}

	private func retrieveLogoFromServer(featureID: String, whenFinished: @escaping (UIImage) -> Void) -> UIImage? {
		let logo = logoCache.object(withKey: featureID, fallbackURL: {
			// Logos are stored under brandIcons2/ mirroring the featureID path, always as .png.
			// e.g. featureID "brands/amenity/fast_food/mcdonalds-c9aa1b"
			//   -> https://gomaposm.com/brandIcons2/brands/amenity/fast_food/mcdonalds-c9aa1b.png
			let url = "https://gomaposm.com/brandIcons2/" + featureID + ".png"
			return URL(string: url)
		}, objectForData: { data in
			if let image = UIImage(data: data) {
				return image
			} else {
				return UIImage()
			}
		}, completion: { result in
			if let image = try? result.get() {
				DispatchQueue.main.async(execute: {
					whenFinished(image)
				})
			}
		})
		return logo
	}

	func retrieveLogoForNsiItem(featureID: String, whenFinished: @escaping (UIImage) -> Void) -> UIImage? {
#if true
		return retrieveLogoFromServer(featureID: featureID, whenFinished: whenFinished)
#else
		retrieveLogoFromBundle(featureID: featureID, whenFinished: whenFinished)
#endif
	}
}
