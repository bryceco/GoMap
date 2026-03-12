//
//  AppEnvironment.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/12/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

enum AppEnvironment {

    /// Returns true when running on a Mac (Catalyst, Designed for iPad, or native Mac idiom).
    static var isRunningOnMac: Bool {
        if #available(iOS 14.0, *),
           ProcessInfo.processInfo.isiOSAppOnMac
        {
            return true
        }
        return ProcessInfo.processInfo.isMacCatalystApp
    }

    /// Returns false when running on a Mac, where no on-screen keyboard is shown.
    static var usesOnScreenKeyboard: Bool {
        if #available(iOS 14.0, *),
           UIDevice.current.userInterfaceIdiom == .mac
        {
            return false
        }
        return !isRunningOnMac
    }

    static var hasRearCamera: Bool {
        return !isRunningOnMac
    }
}
