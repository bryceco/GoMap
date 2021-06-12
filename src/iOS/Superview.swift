//
//  Superview.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/19/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

extension UIView {
	func superviewOfType<T:AnyObject>() -> T? {
		var view: UIView? = self
		while view != nil {
			if let t = view as? T {
				return t
			}
			view = view!.superview
		}
		return nil
	}
}
