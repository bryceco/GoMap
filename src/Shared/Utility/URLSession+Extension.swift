//
//  URLSession+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/23/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

enum UrlSessionError: LocalizedError {
	case badStatusCode(Int, String)
	case missingResponse
	case noData

	public var errorDescription: String? {
		switch self {
		case let .badStatusCode(rc, text):
			switch rc {
			case 410: return "The object no longer exists"
			default: return "Server returned status \(rc): \(text)"
			}
		case .missingResponse: return "UrlSessionError.missingResponse"
		case .noData: return "UrlSessionError.noData"
		}
	}
}

extension URLSession {
	// Wraps up all the various failure conditions in a single result
	func data(with request: URLRequest, completionHandler: @escaping (Result<Data, Error>) -> Void) {
		let task = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
			if let error = error {
				completionHandler(.failure(error))
				return
			}
			guard let httpResponse = response as? HTTPURLResponse
			else {
				completionHandler(.failure(UrlSessionError.missingResponse))
				return
			}
			guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300
			else {
				// The server might provide additional information in the payload.
				// We could potentially look at httpResponse.allHeaderFields or
				// httpResponse.value(forHTTPHeaderField: "Content-Type") to
				// determine how to decode the payload.
				var message = ""
				if let data = data, data.count > 0 {
					message = String(decoding: data, as: UTF8.self)
				} else {
					message = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
				}
				completionHandler(.failure(UrlSessionError.badStatusCode(httpResponse.statusCode, message)))
				return
			}
			guard let data = data else {
				completionHandler(.failure(UrlSessionError.noData))
				return
			}
			completionHandler(.success(data))
		})
		task.resume()
	}

	func data(with url: URL, completionHandler: @escaping (Result<Data, Error>) -> Void) {
		let request = URLRequest(url: url)
		URLSession.shared.data(with: request, completionHandler: completionHandler)
	}
}
