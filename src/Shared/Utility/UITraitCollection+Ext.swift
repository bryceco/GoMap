//
//  UITraitCollection+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/28/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

extension UITraitCollection {

	/// Returns true when running on a Mac (Catalyst, Designed for iPad, or native Mac idiom),
	var isRunningOnMac: Bool {
		if #available(iOS 14.0, *),
		   ProcessInfo.processInfo.isiOSAppOnMac
		{
			return true
		}
		return ProcessInfo.processInfo.isMacCatalystApp
	}

	/// Returns false when running on a Mac (Catalyst, Designed for iPad, or native Mac idiom),
	/// where no on-screen keyboard is shown.
	var usesOnScreenKeyboard: Bool {
		if #available(iOS 14.0, *),
		   userInterfaceIdiom == .mac
		{
			return false
		}
		return !isRunningOnMac
	}

	var hasRearCamera: Bool {
		return !isRunningOnMac
	}
}
