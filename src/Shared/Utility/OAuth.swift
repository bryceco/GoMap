//
//  OAuth.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/25/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import Foundation
import SafariServices
import UIKit

let BASE_OAUTH_URL = URL(string: "https://master.apis.dev.openstreetmap.org/oauth2")!

let OAUTH_KEYCHAIN_IDENTIFIER = "OAuth_access_token"

enum OAuthError: LocalizedError {
	case httpError(Int)
	case errorMessasge(String)
	case badReturnUrl(String)

	public var errorDescription: String? {
		switch self {
		case let .httpError(error): return "http error \(error)"
		case .errorMessasge: return "The GPX track must contain at least 2 points"
		case .badReturnUrl: return "Invalid GPX file format"
		}
	}
}

class OAuth {
	static let shared = OAuth()
	static let client_id = "SGsePsBukg7xPkIaqNIQlAgiAa3vjauIFkbcsPXB2Tg"
	// static let client_secret = "9Wh6Q4fBZ93Ea6LRibiBE0GUNp70Ey3x7LrxBAVBDiQ"
	static let redirect_uri = "gomaposm://oauth/callback"
	static let scope = "read_prefs write_prefs read_gpx write_gpx write_notes write_api"

	private var safariVC: SFSafariViewController?
	private(set) var authorizationHeader: (name: String, value: String)?

	init() {
		if let token = KeyChain.getStringForIdentifier(OAUTH_KEYCHAIN_IDENTIFIER) {
			setAuthorizationToken(token: token)
		}
	}

	private func setAuthorizationToken(token: String) {
		authorizationHeader = (name: "Authorization", value: "Bearer \(token)")
		_ = KeyChain.setString(token, forIdentifier: OAUTH_KEYCHAIN_IDENTIFIER)
	}

	func isAuthorized() -> Bool {
		return authorizationHeader != nil
	}

	func removeAuthorization() {
		KeyChain.deleteString(forIdentifier: OAUTH_KEYCHAIN_IDENTIFIER)
		authorizationHeader = nil
	}

	private let baseDict = [
		"client_id": client_id,
		// "client_secret": client_secret,
		"redirect_uri": redirect_uri
	]

	private func url(withPath path: String, with dict: [String: String]) -> URL {
		var newDict = baseDict
		for (k, v) in dict {
			newDict[k] = v
		}
		var components = URLComponents(string: BASE_OAUTH_URL.appendingPathComponent(path).absoluteString)!
		components.queryItems = newDict.map({ k, v in URLQueryItem(name: k, value: v) })
		return components.url!
	}

	// This pops up the Safari page asking the user for login info
	private var callback: ((Result<Void, Error>) -> Void)?
	func requestAccessFromUser(onComplete callback: @escaping (Result<Void, Error>) -> Void) {
		self.callback = callback
		let url = url(withPath: "authorize", with: [
			"response_type": "code",
			"scope": Self.scope
		])
		safariVC = SFSafariViewController(url: url)
		AppDelegate.shared.mapView.mainViewController.present(safariVC!, animated: true)
	}

	// Once the user responds to the Safari popup the application is invoked and
	// the app delegate calls this function
	func redirectHandler(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
		safariVC?.dismiss(animated: true)
		safariVC = nil
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
			callback?(.failure(OAuthError.badReturnUrl(url.absoluteString)))
			callback = nil
			return
		}
		if let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
			print("auth code = \(code)")
			getAccessToken(for: code)
		} else {
			if let message = components.queryItems?.first(where: { $0.name == "error_description" })?.value {
				callback?(.failure(OAuthError.errorMessasge(message)))
			} else if let message = components.queryItems?.first(where: { $0.name == "error" })?.value {
				callback?(.failure(OAuthError.errorMessasge(message)))
			} else {
				callback?(.failure(OAuthError.errorMessasge("Unknown error during redirect")))
			}
		}
	}

	// Finally, this function connects to the server again to convert an authorization token into an access token
	private func getAccessToken(for code: String) {
		let url = url(withPath: "token", with: [
			"grant_type": "authorization_code",
			"code": code
		])
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.allHTTPHeaderFields = [
			"Content-Type": "application/x-www-form-urlencoded"
		]
		URLSession.shared.data(with: request, completionHandler: { result in
			switch result {
			case let .success(data):
				do {
					if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
					   let token = json["access_token"] as? String
					{
						// Success
						self.setAuthorizationToken(token: token)
						self.callback?(.success(()))
					} else {
						self.callback?(.failure(OAuthError.errorMessasge("Unknown error parsing json")))
					}
				} catch {
					self.callback?(.failure(error))
				}
			case let .failure(error):
				self.callback?(.failure(error))
			}
		})
	}

	// This return a URLRequest with authorization headers set correctly
	func urlRequest(url: URL) -> URLRequest? {
		guard let authorizationHeader = authorizationHeader else { return nil }
		var request = URLRequest(url: url)
		request.allHTTPHeaderFields = [
			authorizationHeader.name: authorizationHeader.value
		]
		return request
	}

	func urlRequest(string: String) -> URLRequest? {
		guard let url = URL(string: string) else { return nil }
		return urlRequest(url: url)
	}

	// If everything is working correctly this function will succeed in getting user details.
	func getUserDetails(callback: @escaping (Bool) -> Void) {
		if let request = urlRequest(string: "https://master.apis.dev.openstreetmap.org/api/0.6/user/details.json") {
			URLSession.shared.data(with: request, completionHandler: { result in
				if let data = try? result.get(),
				   let json = try? JSONSerialization.jsonObject(with: data)
				{
					print("details = \(json)")
					callback(true)
				} else {
					callback(false)
				}
			})
		} else {
			callback(false)
		}
	}
}
