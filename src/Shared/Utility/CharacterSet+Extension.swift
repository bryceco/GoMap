//
//  CharacterSet+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/7/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

public extension CharacterSet {
	static var asciiExceptPercent: CharacterSet = {
		var set = CharacterSet()
		for i in 32...127 {
			set.insert(UnicodeScalar(i)!)
		}
		set.remove("%")
		return set
	}()
}
