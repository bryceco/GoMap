//
//  URLSession+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/23/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit
import UniformTypeIdentifiers

enum UrlSessionError: LocalizedError {
	case badStatusCode(Int, String)
	case expectedHttpResponse

	public var errorDescription: String? {
		switch self {
		case let .badStatusCode(rc, text):
			switch rc {
			case 410: return "The object no longer exists"
			default: return "Server returned status \(rc): \(text)"
			}
		case .expectedHttpResponse: return "UrlSessionError.missingResponse"
		}
	}
}

extension URLSession {
	// Wraps up the various failure conditions as a thrown error
	func data(with request: URLRequest) async throws -> Data {
		let (data, response) = try await self.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw UrlSessionError.expectedHttpResponse
		}
		guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
			let message = await message(for: data, response: httpResponse)
			throw UrlSessionError.badStatusCode(httpResponse.statusCode, message)
		}
		return data
	}

	private func message(for data: Data, response: HTTPURLResponse) async -> String {
		if data.count == 0 {
			// return text appropriate for the status code
			return HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
		}

		// Check if server returned an HTML page
		if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
		   contentTypeIsHTML(contentType),
		   let attributed = await parseHTML(data)
		{
			return attributed.string
		}

		// The server returned some other data.
		return String(decoding: data, as: UTF8.self)
	}

	private func contentTypeIsHTML(_ contentType: String) -> Bool {
		guard #available(iOS 14.0, *) else {
			return contentType.lowercased().contains("text/html")
		}
		return UTType(mimeType: contentType)?.conforms(to: .html) == true
	}

	@MainActor
	private func parseHTML(_ data: Data) -> NSAttributedString? {
		guard let attributed = try? NSAttributedString(
			data: data,
			options: [
				.documentType: NSAttributedString.DocumentType.html,
				.characterEncoding: String.Encoding.utf8.rawValue
			],
			documentAttributes: nil)
		else { return nil }

		let mutable = NSMutableAttributedString(attributedString: attributed)
		let full = NSRange(location: 0, length: mutable.length)
		mutable.removeAttribute(.foregroundColor, range: full)
		mutable.removeAttribute(.backgroundColor, range: full)
		return mutable
	}

	func data(with url: URL) async throws -> Data {
		var request = URLRequest(url: url)
		request.setUserAgent()
		request.setReferrer()
		return try await self.data(with: request)
	}
}

extension URLRequest {
	static func appUserAgent() -> String {
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

	mutating func setReferrer() {
		if url?.host?.hasSuffix(".mapbox.com") ?? false {
			setValue("https://www.openstreetmap.org/", forHTTPHeaderField: "Referer")
		}
	}
}
