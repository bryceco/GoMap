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

let OAUTH_KEYCHAIN_IDENTIFIER = "OAuth_access_token"

enum OAuthError: LocalizedError {
	case errorMessasge(String)
	case badRedirectUrl(String)
	case stateMismatch

	public var errorDescription: String? {
		switch self {
		case let .errorMessasge(message): return "OAuth error: \(message)"
		case .badRedirectUrl: return "OAuth error: bad redirect URL"
		case .stateMismatch: return "OAuth error: state mismatch"
		}
	}
}

class OAuth2 {
	struct OAuthServer {
		let authURL: String // used for OAuth connections
		let apiURL: String // used for API connections
		let client_id: String
	}

	let servers = [
		// the production server
		OAuthServer(authURL: "https://www.openstreetmap.org/",
		            apiURL: "https://api.openstreetmap.org/",
		            client_id: "mzRn5Z-X0nSptHgA3o5g30HeaaljTXfv0GMOLhmwqeo"),
		// the dev server
		OAuthServer(authURL: "https://master.apis.dev.openstreetmap.org/",
		            apiURL: "https://api06.dev.openstreetmap.org/",
		            client_id: "SGsePsBukg7xPkIaqNIQlAgiAa3vjauIFkbcsPXB2Tg")
	]
	static let redirect_uri = "gomaposm://oauth/callback"
	static let scope = "read_prefs write_prefs read_gpx write_gpx write_notes write_api"

	private var safariVC: SFSafariViewController?
	private var state = ""
	private(set) var authorizationHeader: (name: String, value: String)?

	var server: OAuthServer { servers.first(where: { $0.apiURL == OSM_API_URL }) ?? servers[0] }
	var client_id: String { server.client_id }
	var serverURL: String { server.authURL }
	var oauthUrl: URL { return URL(string: serverURL)!.appendingPathComponent("oauth2") }

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

	private func url(withPath path: String, with dict: [String: String]) -> URL {
		var components = URLComponents(string: oauthUrl.appendingPathComponent(path).absoluteString)!
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
		let url = url(withPath: "authorize", with: [
			"client_id": client_id,
			"redirect_uri": Self.redirect_uri,
			"response_type": "code",
			"scope": Self.scope,
			"state": state
		])
		safariVC = SFSafariViewController(url: url)
		vc.present(safariVC!, animated: true)
	}

	// Once the user responds to the Safari popup the application is invoked and
	// the app delegate calls this function
	func redirectHandler(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
		safariVC?.dismiss(animated: true)
		safariVC = nil
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
		URLSession.shared.data(with: request, completionHandler: { result in
			switch result {
			case let .success(data):
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
			case let .failure(error):
				self.doCallback(.failure(error))
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
	func getUserDetails(callback: @escaping ([String: Any]?) -> Void) {
		let url = serverURL + "api/0.6/user/details.json"
		if let request = urlRequest(string: url) {
			URLSession.shared.data(with: request, completionHandler: { result in
				DispatchQueue.main.async {
					if let data = try? result.get(),
					   let json = try? JSONSerialization.jsonObject(with: data),
					   let dict = json as? [String: Any],
					   let user = dict["user"] as? [String: Any]
					{
						callback(user)
					} else {
						callback(nil)
					}
				}
			})
		} else {
			callback(nil)
		}
	}

	func getUserPermissions(callback: @escaping ([String]?) -> Void) {
		let url = serverURL + "api/0.6/permissions.json"
		if let request = urlRequest(string: url) {
			URLSession.shared.data(with: request, completionHandler: { result in
				DispatchQueue.main.async {
					if let data = try? result.get(),
					   let json = try? JSONSerialization.jsonObject(with: data),
					   let dict = json as? [String: Any],
					   let perms = dict["permissions"] as? [String]
					{
						callback(perms)
					} else {
						callback(nil)
					}
				}
			})
		} else {
			callback(nil)
		}
	}
}
