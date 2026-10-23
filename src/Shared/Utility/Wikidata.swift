//
//  Wikidata.swift
//  Go Map!!
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

struct WikidataItem {
	let id: String
	let label: String
	let description: String?
}

enum Wikidata {
	private static let apiURL = URL(string: "https://www.wikidata.org/w/api.php")!

	static func isQID(_ value: String) -> Bool {
		return value.range(of: "^Q[1-9][0-9]*$", options: .regularExpression) != nil
	}

	static func search(_ text: String, language: String) async throws -> [WikidataItem] {
		let language = language.lowercased()
		let results = try await search(text, wikidataLanguage: language)
		if results == nil,
		   let base = language.split(separator: "-").first,
		   base != language
		{
			return try await search(text, wikidataLanguage: String(base)) ?? []
		}
		return results ?? []
	}

	private static func search(_ text: String, wikidataLanguage language: String) async throws -> [WikidataItem]? {
		let url = apiURL.appendingQueryItems([
			"action": "wbsearchentities",
			"format": "json",
			"formatversion": "2",
			"type": "item",
			"limit": "10",
			"search": text,
			"language": language,
			"uselang": language
		])
		let data = try await URLSession.shared.data(with: url)
		guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
		if let error = json["error"] as? [String: Any],
		   error["code"] as? String == "badvalue"
		{
			return nil
		}
		guard let results = json["search"] as? [[String: Any]] else { return [] }
		return results.compactMap { result in
			guard let id = result["id"] as? String else { return nil }
			return WikidataItem(id: id,
			                    label: result["label"] as? String ?? id,
			                    description: result["description"] as? String)
		}
	}
}
