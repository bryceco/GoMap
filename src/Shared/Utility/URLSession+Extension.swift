//
//  URLSession+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/23/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

enum UrlSessionError: LocalizedError {
	case badStatusCode(Int, String)
	case missingResponse

	public var errorDescription: String? {
		switch self {
		case let .badStatusCode(rc, text):
			switch rc {
			case 410: return "The object no longer exists"
			default: return "Server returned status \(rc): \(text)"
			}
		case .missingResponse: return "UrlSessionError.missingResponse"
		}
	}
}

enum URLError2: Error {
	case invalidURL(String)

	var localizedDescription: String {
		switch self {
		case let .invalidURL(urlString):
			return "Invalid URL: \(urlString)"
		}
	}
}

extension URLSession {
	// Wraps up all the various failure conditions in a single result
	func data(with request: URLRequest) async throws -> Data {
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse
		else {
			throw UrlSessionError.missingResponse
		}
		guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300
		else {
			// The server might provide additional information in the payload.
			// We could potentially look at httpResponse.allHeaderFields or
			// httpResponse.value(forHTTPHeaderField: "Content-Type") to
			// determine how to decode the payload.
			var message = ""
			if data.count > 0 {
				message = String(decoding: data, as: UTF8.self)
			} else {
				message = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
			}
			throw UrlSessionError.badStatusCode(httpResponse.statusCode, message)
		}
		return data
	}

	func data(with url: URL) async throws -> Data {
		var request = URLRequest(url: url)
		request.setUserAgent()
		return try await URLSession.shared.data(with: request)
	}
}

extension URLRequest {
	static func appUserAgent() -> String
	{
		let appName = AppDelegate.appName
		let appVersion = AppDelegate.appVersion
		let systemVersion = UIDevice.current.systemVersion
		let deviceModel = UIDevice.current.model
		return "\(appName)/\(appVersion) (\(deviceModel); iOS \(systemVersion))"
	}

	static let appUserAgentString = appUserAgent()

	mutating func setUserAgent() {
		setValue(Self.appUserAgentString, forHTTPHeaderField: "User-Agent")
	}
}
