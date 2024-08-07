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
	                                            daysToKeep: 90.0)

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
			// fetch icons from our private server
			let name: String = featureID.replacingOccurrences(of: "/", with: "_")
			let url = "http://gomaposm.com/brandIcons/" + name
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
