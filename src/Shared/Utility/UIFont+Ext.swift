//
//  UIFont+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/25/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

extension UIFont {
	func bold() -> UIFont {
		guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else {
			return self
		}
		return UIFont(descriptor: descriptor, size: 0)
	}
}
