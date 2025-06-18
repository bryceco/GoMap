//
//  UIImage+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/18/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//
import UIKit

extension UIImage {
	func scaledTo(width: CGFloat?, height: CGFloat?) -> UIImage {
		var size = size
		if size.width == 0 || size.height == 0 {
			size = CGSize(width: 1.0, height: 1.0)
		}
		let scaleX = (width ?? CGFloat.greatestFiniteMagnitude) / size.width
		let scaleY = (height ?? CGFloat.greatestFiniteMagnitude) / size.height
		let scale = min(scaleX, scaleY)
		if abs(scale - 1.0) < 0.001 {
			return self
		}
		let newSize = CGSize(width: size.width * scale,
		                     height: size.height * scale)
		UIGraphicsBeginImageContextWithOptions(
			newSize,
			false,
			UIScreen.main.scale)
		draw(in: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
		let imageCopy = UIGraphicsGetImageFromCurrentImageContext()!
		UIGraphicsEndImageContext()
		return imageCopy
	}
}
