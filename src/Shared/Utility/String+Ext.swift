//
//  String+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/5/22.
//  Copyright © 2022 Bryce. All rights reserved.
//

import Foundation

extension String {
	func addingPercentEncodingForNonASCII() -> String {
		return utf8.map({
			$0 > 32 && $0 < 128
				? String(Character(UnicodeScalar($0)))
				: "%" + String($0, radix: 16, uppercase: true)
		}).joined(separator: "")
	}
}
