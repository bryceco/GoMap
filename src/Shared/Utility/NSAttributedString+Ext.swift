//
//  NSAttributedString+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/28/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation
import UIKit

extension NSMutableAttributedString {
	/// Takes a string containing HTML code, such as an error message returned by a server, and
	/// converts it to an NSAttributedString
	convenience init?(withHtmlString html: String,
	                  textColor: UIColor,
	                  backgroundColor backColor: UIColor)
	{
		do {
			guard html.hasPrefix("<"),
			      let data = html.data(using: .utf8)
			else { return nil }
			let encoding = NSNumber(value: String.Encoding.utf8.rawValue)
			try self.init(data: data,
			              options: [.documentType: NSAttributedString.DocumentType.html,
			                        .characterEncoding: encoding],
			              documentAttributes: nil)

			// change text color
			let range = NSRange(location: 0, length: length)
			addAttribute(.foregroundColor, value: textColor, range: range)
			addAttribute(.backgroundColor, value: backColor, range: range)
			// center align
			let paragraphStyle = NSMutableParagraphStyle()
			paragraphStyle.alignment = .center
			addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
		} catch {
			return nil
		}
	}
}
