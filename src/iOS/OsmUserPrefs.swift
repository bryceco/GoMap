//
//  OsmUserPrefs.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/6/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

class OsmUserPrefs: CustomStringConvertible, CustomDebugStringConvertible {
	private let PREFIX = "gomap-"
	private let MAX_LENGTH = 255
	private var preferences: [String: String] = [:]
	private var oldPreferenceKeys: [String] = []

	func set(key: String, value: String) {
		preferences[PREFIX + key] = value
	}

	func get(key: String) -> String? {
		return preferences[PREFIX + key]
	}

	var description: String {
		var text = "OsmUserPrefs = [\n"
		for (k, v) in preferences {
			text += "    \(k) = \(v)\n"
		}
		text += "]"
		return text
	}

	var debugDescription: String {
		return description
	}

	private static func allPreferences(data callback: @escaping (Data?) -> Void) {
		let url = OSM_API_URL + "api/0.6/user/preferences.json"
		guard let request = AppDelegate.shared.oAuth2.urlRequest(string: url) else {
			callback(nil)
			return
		}
		URLSession.shared.data(with: request, completionHandler: { result in
			DispatchQueue.main.async(execute: {
				guard let data = try? result.get() else {
					callback(nil)
					return
				}
				callback(data)
			})
		})
	}

	private static func allPreferences(dict callback: @escaping ([String: String]?) -> Void) {
		Self.allPreferences(data: { data in
			guard let data = data,
			      let json = try? JSONSerialization.jsonObject(with: data),
			      let json = json as? [String: Any],
			      let prefs = json["preferences"] as? [String: String]
			else {
				callback(nil)
				return
			}
			callback(prefs)
		})
	}

	private static func parse(key: String) -> (key: String, ident: Int?) {
		let suffix = key.suffix(4)
		if suffix.count == 4,
		   suffix.hasPrefix("-"),
		   let id = Int(suffix.dropFirst())
		{
			return (String(key.dropLast(4)), id)
		} else {
			return (key, nil)
		}
	}

	private static func index(key: String, ident: Int) -> String {
		return key + "-" + String(format: "%03d", ident)
	}

	func download(_ callback: @escaping (Bool) -> Void) {
		Self.allPreferences(dict: { dict in
			guard var dict = dict else {
				self.preferences = [:]
				self.oldPreferenceKeys = []
				callback(false)
				return
			}
			self.preferences.removeAll()
			self.oldPreferenceKeys = dict.keys.filter({ $0.hasPrefix(self.PREFIX) })

			while let key2 = dict.keys.first {
				guard key2.hasPrefix(self.PREFIX) else {
					dict.removeValue(forKey: key2)
					continue
				}
				let (key, ident) = Self.parse(key: key2)
				if ident != nil {
					var value = ""
					for ident in 0... {
						let index = Self.index(key: key, ident: ident)
						guard let v = dict[index] else { break }
						value += v
						dict.removeValue(forKey: index)
					}
					self.preferences[key] = value.removingPercentEncoding!

					// Also remove the initial key to ensure we make forward progress.
					// This is only necessary if the store is corrupt.
					dict.removeValue(forKey: key2)
				} else {
					self.preferences[key] = dict[key]?.removingPercentEncoding
					dict.removeValue(forKey: key)
				}
			}
			callback(true)
		})
	}

	func upload(_ callback: @escaping (Bool) -> Void) {
		var dict = preferences.mapValues({
			$0.addingPercentEncoding(withAllowedCharacters: CharacterSet.asciiExceptPercent)!
		})
		while let item = dict.first(where: { $0.value.count > MAX_LENGTH }) {
			dict.removeValue(forKey: item.key)

			// chop value into multiple pieces
			var value = item.value
			var ident = 0
			while !value.isEmpty {
				let v = String(value.prefix(MAX_LENGTH))
				value = String(value.dropFirst(MAX_LENGTH))
				let index = Self.index(key: item.key, ident: ident)
				dict[index] = v
				ident += 1
			}
		}

		for key in oldPreferenceKeys {
			if dict[key] == nil {
				dict[key] = ""
			}
		}

		for (key, value) in dict {
			let url = OSM_API_URL + "api/0.6/user/preferences/\(key)"
			guard var request = AppDelegate.shared.oAuth2.urlRequest(string: url) else {
				callback(false)
				return
			}
			if value.isEmpty {
				request.httpMethod = "DELETE"
			} else {
				request.httpMethod = "PUT"
				request.httpBody = value.data(using: .utf8)
			}
			URLSession.shared.data(with: request, completionHandler: { _ in })
		}
		oldPreferenceKeys = dict.compactMap { $0.key.hasPrefix(self.PREFIX) && !$0.value.isEmpty ? $0.key : nil }

		callback(true)
	}
}
