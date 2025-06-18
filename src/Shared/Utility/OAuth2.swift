//
//  OAuth2.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/25/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation
import SafariServices
import UIKit

enum OAuthError: LocalizedError {
	case errorMessasge(String)
	case badRedirectUrl(String)
	case stateMismatch
	case missingInformation

	public var errorDescription: String? {
		switch self {
		case let .errorMessasge(message): return "OAuth error: \(message)"
		case .badRedirectUrl: return "OAuth error: bad redirect URL"
		case .stateMismatch: return "OAuth error: state mismatch"
		case .missingInformation: return "OAuth error: missing information"
		}
	}
}

class OAuth2 {
	static let redirect_uri = "gomaposm://oauth/callback"

	private var safariVC: SFSafariViewController?
	private var state = ""
	private(set) var authorizationHeader: (name: String, value: String)?

	let serverURL: URL
	let basePath: String
	let authPath: String
	let client_id: String
	let scope: String // "read_prefs write_prefs read_gpx write_gpx write_notes write_api"

	var keychainIdentifier: String {
		let OAUTH_KEYCHAIN_IDENTIFIER = "OAuth_access_token"
		if serverURL.host == "www.openstreetmap.org" {
			return OAUTH_KEYCHAIN_IDENTIFIER
		}
		return "\(OAUTH_KEYCHAIN_IDENTIFIER):\(serverURL.host!)"
	}

	init(serverURL: URL,
	     basePath: String,
	     authPath: String,
	     client_id: String,
	     scope: String)
	{
		self.serverURL = serverURL
		self.basePath = basePath
		self.authPath = authPath
		self.client_id = client_id
		self.scope = scope
		if let token = KeyChain.getStringForIdentifier(keychainIdentifier) {
			setAuthorizationToken(token: token)
		}
	}

	private func setAuthorizationToken(token: String) {
		authorizationHeader = (name: "Authorization", value: "Bearer \(token)")
		_ = KeyChain.setString(token, forIdentifier: keychainIdentifier)
	}

	func isAuthorized() -> Bool {
		return authorizationHeader != nil
	}

	func removeAuthorization() {
		KeyChain.deleteString(forIdentifier: keychainIdentifier)
		authorizationHeader = nil
	}

	private func url(withPath path: String, with dict: [String: String]) -> URL {
		let url = serverURL.appendingPathComponent(basePath).appendingPathComponent(path)
		var components = URLComponents(url: url,
		                               resolvingAgainstBaseURL: true)!
		components.queryItems = dict.map({ k, v in URLQueryItem(name: k, value: v) })
		return components.url!
	}

	private var authCallback: ((Result<Void, Error>) -> Void)?

	func doCallback(_ result: Result<Void, Error>) {
		DispatchQueue.main.async {
			if case .failure = result {
				self.removeAuthorization()
			}
			self.authCallback?(result)
			self.authCallback = nil
		}
	}

	// This pops up the Safari page asking the user for login info
	func requestAccessFromUser(
		withVC vc: UIViewController,
		onComplete callback: @escaping (Result<Void, Error>) -> Void)
	{
		authCallback = callback
		state = "\(Int.random(in: 0..<1000_000000))-\(Int.random(in: 0..<1000_000000))"
		let url = url(withPath: authPath, with: [
			"client_id": client_id,
			"redirect_uri": Self.redirect_uri,
			"response_type": "code",
			"scope": scope,
			"state": state
		])
		safariVC = SFSafariViewController(url: url)
		vc.present(safariVC!, animated: true)
	}

	// Once the user responds to the Safari popup the application is invoked and
	// the app delegate calls this function
	func redirectHandler(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
		defer {
			safariVC?.dismiss(animated: true)
			safariVC = nil
		}
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
			doCallback(.failure(OAuthError.badRedirectUrl(url.absoluteString)))
			return
		}
		guard
			let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
			let state = components.queryItems?.first(where: { $0.name == "state" })?.value
		else {
			if let message = components.queryItems?.first(where: { $0.name == "error_description" })?.value {
				let message = message.replacingOccurrences(of: "+", with: " ")
				doCallback(.failure(OAuthError.errorMessasge(message)))
			} else if let message = components.queryItems?.first(where: { $0.name == "error" })?.value {
				doCallback(.failure(OAuthError.errorMessasge(message)))
			} else {
				doCallback(.failure(OAuthError.errorMessasge("Unknown error during redirect")))
			}
			return
		}
		guard state == self.state else {
			doCallback(.failure(OAuthError.stateMismatch))
			return
		}
		getAccessToken(for: code)
	}

	// Finally, this function connects to the server again to convert an authorization token into an access token
	private func getAccessToken(for code: String) {
		let url = url(withPath: "token", with: [
			"client_id": client_id,
			"redirect_uri": Self.redirect_uri,
			"grant_type": "authorization_code",
			"code": code
		])
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.allHTTPHeaderFields = [
			"Content-Type": "application/x-www-form-urlencoded"
		]
		Task {
			do {
				let data = try await URLSession.shared.data(with: request)
				await MainActor.run {
					do {
						if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
						   let token = json["access_token"] as? String
						{
							// Success
							self.setAuthorizationToken(token: token)
							self.doCallback(.success(()))
						} else {
							self.doCallback(.failure(OAuthError.errorMessasge("Unknown error parsing json")))
						}
					} catch {
						self.doCallback(.failure(error))
					}
				}
			} catch {
				await MainActor.run {
					self.doCallback(.failure(error))
				}
			}
		}
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
	func getUserDetails() async throws -> [String: Any] {
		let url = serverURL.appendingPathComponent("api/0.6/user/details.json")
		guard let request = urlRequest(url: url) else {
			throw URLError(.badURL)
		}
		let data = try await URLSession.shared.data(with: request)
		let json = try JSONSerialization.jsonObject(with: data)
		guard let dict = json as? [String: Any],
		      let user = dict["user"] as? [String: Any]
		else {
			throw OAuthError.missingInformation
		}
		return user
	}
}
