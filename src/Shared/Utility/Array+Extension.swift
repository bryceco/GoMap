//
//  Array+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/8/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

// Collapse consecutive duplicated items in the array into a single item
extension Array where Element: Equatable {
	func removingDuplicatedItems() -> AnyIterator<Element> {
		var iterator = makeIterator()
		var previousElement: Element?

		return AnyIterator {
			while let element = iterator.next() {
				if element != previousElement {
					previousElement = element
					return element
				}
			}
			return nil
		}
	}
}

// Combine an array of NSAttributedString with a separator
extension Array where Element == NSAttributedString {
	func joined(by separator: NSAttributedString) -> NSAttributedString {
		let result = NSMutableAttributedString()
		for (index, attributedString) in self.enumerated() {
			if index > 0 { result.append(separator) }
			result.append(attributedString)
		}
		return result
	}

	func joined(by separator: String = "") -> NSAttributedString {
		return self.joined(by: NSAttributedString(string: separator))
	}
}
