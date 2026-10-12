//
//  Superview.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/19/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

extension UIView {
	func superview<T: AnyObject>(ofType type: T.Type) -> T? {
		var view: UIView? = self
		while view != nil {
			if let t = view as? T {
				return t
			}
			view = view!.superview
		}
		return nil
	}

	func ancestor<T: UIResponder>(ofType type: T.Type) -> T? {
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

extension UIResponder {
	/// Walks up the responder chain and returns the first responder of the given type.
	func nearestResponder<T>(ofType _: T.Type) -> T? {
		for responder in sequence(first: self as UIResponder, next: \.next) {
			if let match = responder as? T {
				return match
			}
		}
		return nil
	}
}
