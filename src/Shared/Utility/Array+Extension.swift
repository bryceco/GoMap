//
//  Array+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/8/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

extension Array where Element: Equatable {

	// Collapse consecutive duplicated items in the array into a single item
	func removingDuplicatedItems() -> AnyIterator<Element> {
		var iterator = self.makeIterator()
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

