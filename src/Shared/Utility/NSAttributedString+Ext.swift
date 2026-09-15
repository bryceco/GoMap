//
//  NSAttributedString+Ext.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/28/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

extension NSAttributedString {
	convenience init?(withHtmlData data: Data) async {
		// The synchronous NSMutableAttributedString(data:options:) with .html uses an
		// in-process WebKit lock (_WebThreadLock) that deadlocks on iOS 18+ even when
		// called from the main thread. loadFromHTML parses HTML out-of-process and is
		// safe to call from any context.
		let result: NSAttributedString? = await withCheckedContinuation { continuation in
			NSAttributedString.loadFromHTML(data: data, options: [:]) { attrStr, _, _ in
				continuation.resume(returning: attrStr)
			}
		}
		guard let attr = result else { return nil }
		let mutable = NSMutableAttributedString(attributedString: attr)
		mutable.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: mutable.length))
		mutable.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: mutable.length))
		self.init(attributedString: mutable)
	}

	convenience init?(withHtmlString string: String) async {
		guard let data = string.data(using: .utf8) else { return nil }
		await self.init(withHtmlData: data)
	}
}
