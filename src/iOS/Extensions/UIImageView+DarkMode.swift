//
//  UIImageView+DarkMode.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 3/12/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit

extension UIImageView {
    /// Sets up the image view's `tintColor` to support Dark Mode.
    /// This can be used to tint icons that would otherwise be black when Dark Mode is enabled.
    @objc func setupTintColorForDarkMode() {
        guard #available(iOS 13.0, *) else {
            /// Dark Mode is only available with iOS 13.
            /// Default to black.
            tintColor = .black
            
            return
        }
        
        tintColor = .label
    }
}
