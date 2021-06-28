//
//  URLSession+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/23/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

enum UrlSessionError: Error {
	case badStatusCode(Int, String?)
	case missingResponse
	case noData
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
				// the server might provide additional information in the payload
				var message: String?
				if let data = data, data.count > 0 {
					message = String(decoding: data, as: UTF8.self)
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
