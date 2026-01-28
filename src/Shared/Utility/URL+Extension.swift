//
//  URL+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/27/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

extension URL {
	/// Appends query items to the URL.
	/// - Parameter queryItems: Dictionary of query parameter names and values
	/// - Returns: A new URL with the query items appended
	func appendingQueryItems(_ queryItems: [String: String]) -> URL {
		var components = URLComponents(url: self, resolvingAgainstBaseURL: true)!
		let items = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
		components.queryItems = items
		return components.url!
	}
}
