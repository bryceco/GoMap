//
//  Superview.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/19/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

extension UIView {
	func superviewOfType<T: AnyObject>(_ type: T.Type) -> T? {
		var view: UIView? = self
		while view != nil {
			if let t = view as? T {
				return t
			}
			view = view!.superview
		}
		return nil
	}

	func ancestorOfType<T: UIResponder>(_ type: T.Type) -> T? {
		var responder: UIResponder? = self
		while let current = responder {
			if let match = current as? T {
				return match
			}
			responder = current.next
		}
		return nil
	}

	func subviewOfType<T: AnyObject>(_ type: T.Type, where pred: (T) -> Bool) -> T? {
		for view in subviews {
			if let v = view as? T,
			   pred(v)
			{
				return v
			}
			if let v = view.subviewOfType(type, where: pred) {
				return v
			}
		}
		return nil
	}
}
