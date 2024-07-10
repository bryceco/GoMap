//
//  DarkModeImage.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/10/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

class DarkModeImage {
	static let shared = DarkModeImage()

	let context = CIContext()

	@available(iOS 13.0, *)
	func darkModeImageFor(data: Data) -> UIImage? {
		guard let orig = CIImage(data: data) else { return nil }
		let image = orig

		let filter = CIFilter.colorControls()
		filter.saturation = 1.0
		filter.brightness = -0.4
		filter.contrast = 1.0

		filter.inputImage = image
		guard let image = filter.outputImage else { return nil }

		guard let cgImage = context.createCGImage(image, from: orig.extent) else { return nil }
		return UIImage(cgImage: cgImage)
	}

	// Uses the CSS color inversion trick
	@available(iOS 13.0, *)
	func cssDarkModeImageFor(data: Data) -> UIImage? {
		guard let orig = CIImage(data: data) else { return nil }
		let image = orig

		let invertFilter = CIFilter.colorInvert()
		invertFilter.inputImage = image
		guard let image = invertFilter.outputImage else { return nil }

		let hueAdjustFilter = CIFilter.hueAdjust()
		hueAdjustFilter.inputImage = image
		hueAdjustFilter.angle = .pi
		guard let image = hueAdjustFilter.outputImage else { return nil }

		guard let cgImage = context.createCGImage(image, from: orig.extent) else { return nil }
		return UIImage(cgImage: cgImage)
	}
}
