//
//  EXIF.swift
//  PhotoShare
//
//  Created by Bryce Cogswell on 3/23/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation
import ImageIO

public struct EXIFInfo {
	let latitude: Double
	let longitude: Double
	let altitude: Double?
	let direction: Double?

	init?(url: URL) {
		guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
		      let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
		      let gpsData = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
		      let latitudeRef = gpsData[kCGImagePropertyGPSLatitudeRef as String] as? String,
		      let latitude = gpsData[kCGImagePropertyGPSLatitude as String] as? Double,
		      let longitudeRef = gpsData[kCGImagePropertyGPSLongitudeRef as String] as? String,
		      let longitude = gpsData[kCGImagePropertyGPSLongitude as String] as? Double
		else {
			return nil
		}
		if let altitude = gpsData[kCGImagePropertyGPSAltitude as String] as? Double,
		   let altitudeRef = gpsData[kCGImagePropertyGPSAltitudeRef as String] as? Int
		{
			self.altitude = altitudeRef == 1 ? -altitude : altitude
		} else {
			altitude = nil
		}
		direction = gpsData[kCGImagePropertyGPSImgDirection as String] as? Double
		self.latitude = latitudeRef == "S" ? -latitude : latitude
		self.longitude = longitudeRef == "W" ? -longitude : longitude
	}
}
