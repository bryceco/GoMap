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

	var logoCache = PersistentWebCache<UIImage>(name: "presetLogoCache", memorySize: 5 * 1_000000)

	// MARK: NSI Logo icon retrieval

	private func retrieveLogoFromBundle(_ feature: PresetFeature, whenFinished: @escaping () -> Void) {
		// use built-in logo files
		if feature.nsiLogo == nil {
			feature.nsiLogo = feature.iconUnscaled
			DispatchQueue.global(qos: .default).async(execute: {
				var name = feature.featureID.replacingOccurrences(of: "/", with: "_")
				name = "presets/brandIcons/" + name
				let path = Bundle.main.path(forResource: name, ofType: "jpg") ?? Bundle.main
					.path(forResource: name, ofType: "png") ?? Bundle.main
					.path(forResource: name, ofType: "gif") ?? Bundle.main
					.path(forResource: name, ofType: "bmp") ?? nil
				if let image = UIImage(contentsOfFile: path ?? "") {
					DispatchQueue.main.async(execute: {
						feature.nsiLogo = image
						whenFinished()
					})
				}
			})
		}
	}

	private func retrieveLogoFromServer(_ feature: PresetFeature, whenFinished: @escaping () -> Void) {
		feature.nsiLogo = feature.iconUnscaled
		let logo = logoCache.object(withKey: feature.featureID, fallbackURL: {
			// fetch icons from our private server
			let name: String = feature.featureID.replacingOccurrences(of: "/", with: "_")
			let url = "http://gomaposm.com/brandIcons/" + name
			return URL(string: url)
		}, objectForData: { data in
			if let image = UIImage(data: data) {
				return EditorMapLayer.ImageScaledToSize(image, 60.0)
			} else {
				return UIImage()
			}
		}, completion: { result in
			if let image = try? result.get() {
				DispatchQueue.main.async(execute: {
					feature.nsiLogo = image
					whenFinished()
				})
			}
		})
		if logo != nil {
			feature.nsiLogo = logo
		}
	}

	func retrieveLogoForNsiItem(_ feature: PresetFeature, whenFinished: @escaping () -> Void) {
#if true
		retrieveLogoFromServer(feature, whenFinished: whenFinished)
#else
		retrieveLogoFromBundle(feature, whenFinished: whenFinished)
#endif
	}
}
