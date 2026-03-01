//
//  UITraitCollection+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/28/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

extension UITraitCollection {
	/// Returns false when running on a Mac (Catalyst, Designed for iPad, or native Mac idiom),
	/// where no on-screen keyboard is shown.
	var usesOnScreenKeyboard: Bool {
		if ProcessInfo.processInfo.isMacCatalystApp {
			return false
		}
		if #available(iOS 14.0, *),
		   ProcessInfo.processInfo.isiOSAppOnMac || userInterfaceIdiom == .mac
		{
			return false
		}
		return true
	}
}
