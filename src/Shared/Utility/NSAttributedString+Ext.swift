//
//  NSAttributedString+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/28/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

extension NSAttributedString {
	convenience init?(withHtmlData data: Data) {
		guard
			let attr = try? NSMutableAttributedString(data: data,
			                                          options: [
			                                          	.documentType: NSAttributedString.DocumentType.html,
			                                          	.characterEncoding: String.Encoding.utf8.rawValue
			                                          ],
			                                          documentAttributes: nil)
		else {
			return nil
		}
		attr.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: attr.length))
		attr.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: attr.length))
		self.init(attributedString: attr)
	}

	convenience init?(withHtmlString string: String) {
		guard let data = string.data(using: .utf8) else { return nil }
		self.init(withHtmlData: data)
	}
}
