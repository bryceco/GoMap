//
//  WikiPage.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/26/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

class WikiPage {
	static let shared = WikiPage()

	private func wikiPageTitleLanguageFor(languageCode code: String) -> String {
		if code == "" {
			return ""
		}
		let special = [
			"en": "",
			"de": "DE:",
			"es": "ES:",
			"fr": "FR:",
			"it": "IT:",
			"ja": "JA:",
			"nl": "NL:",
			"ru": "RU:",
			"zh-CN": "Zh-hans:",
			"zh-HK": "Zh-hant:",
			"zh-TW": "Zh-hant:"
		]
		if let result = special[code] {
			return result
		}

		let result = code.prefix(1).uppercased() + code.dropFirst().lowercased() + ":"
		return result
	}

	private func wikiLanguageCodeFor(languageCode code: String) -> String {
		let special = [
			"zh-CN": "zh-hans",
			"zh-HK": "zh-hant",
			"zh-TW": "zh-hant"
		]
		if let result = special[code] {
			return result
		}
		return code.lowercased()
	}

	private func ifUrlExists(_ url: URL) async -> Bool {
		let request = NSMutableURLRequest(url: url)
		request.httpMethod = "HEAD"
		request.cachePolicy = .returnCacheDataElseLoad
		if let (_, response) = try? await URLSession.shared.data(for: request as URLRequest),
		   let httpResponse = response as? HTTPURLResponse
		{
			switch httpResponse.statusCode {
			case 200, 301, 302:
				return true
			default:
				break
			}
		}
		return false
	}

	private func encodedTag(_ tag: String) -> String {
		return tag.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
	}

	func urlFor(pageTitle: String) -> URL {
		let baseURL = URL(string: "https://wiki.openstreetmap.org/wiki/")!
		let url = baseURL.appendingPathComponent(pageTitle)
		return url
	}

	func bestWikiPage(
		forKey tagKey: String,
		value tagValue: String,
		language: String) async -> URL?
	{
		let language = wikiPageTitleLanguageFor(languageCode: language)
		let tagKey = encodedTag(tagKey)
		let tagValue = encodedTag(tagValue)
		var pageList: [String] = []

		pageList.append("\(language)Tag:\(tagKey)=\(tagValue)")
		if language != "" {
			pageList.append("Tag:\(tagKey)=\(tagValue)")
		}

		pageList.append("\(language)Key:\(tagKey)")
		if language != "" {
			pageList.append("Key:\(tagKey)")
		}

		let baseURL = URL(string: "https://wiki.openstreetmap.org/wiki/")!
		var urlDict: [String: URL] = [:]

		await withTaskGroup(of: (String, URL)?.self) { group in
			for page in pageList {
				group.addTask {
					let url = baseURL.appendingPathComponent(page)
					let exists = await self.ifUrlExists(url)
					if exists {
						return (page, url)
					} else {
						return nil
					}
				}
			}
			for await page in group {
				if let page {
					urlDict[page.0] = page.1
				}
			}
		}

		for page in pageList {
			if let url = urlDict[page] {
				return url
			}
		}
		return nil
	}

	private class KeyValueDescription {
		let description: String
		let imagePath: String
		let pageTitle: String

		init(description: String, imagePath: String, pageTitle: String) {
			self.description = description
			self.imagePath = imagePath
			self.pageTitle = pageTitle
		}
	}

	struct KeyValueMetadata {
		let key: String
		let value: String
		let pageTitle: String
		let description: String
		let imagePath: String
		var image: UIImage?

		init(key: String, value: String, pageTitle: String, description: String, imagePath: String, image: UIImage?) {
			self.key = key
			self.value = value
			self.pageTitle = pageTitle
			self.description = description
			self.imagePath = imagePath
			self.image = image
		}
	}

	private let descriptionCache = PersistentWebCache<KeyValueDescription>(name: "wikiTagStore",
	                                                                       memorySize: 10_000000,
	                                                                       daysToKeep: 45.0)
	private let imageCache = PersistentWebCache<UIImage>(name: "wikiImageStore",
	                                                     memorySize: 10_000000,
	                                                     daysToKeep: 45.0)
	private let equals = "=".addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics) ?? ""

	func resetCache() {
		descriptionCache.removeAllObjects()
		imageCache.removeAllObjects()
	}

	private func propertyListFor(property: String, inEntity entity: [String: Any]) -> [[String: Any]]? {
		let claims = entity["claims"] as? [String: Any]
		return claims?[property] as? [[String: Any]]
	}

	private func valueFor(property: String, inEntity entity: [String: Any], langQID: String) -> String? {
		guard
			let propertyList = propertyListFor(property: property, inEntity: entity)
		else { return nil }

		// find the property containing the requested language
		let locale = propertyList.first(where: {
			if let qualifiers = $0["qualifiers"] as? [String: Any],
			   let P26 = qualifiers["P26"] as? [[String: Any]], // indicates language qualifier
			   let datavalue = P26.first?["datavalue"] as? [String: Any],
			   let value = datavalue["value"] as? [String: Any],
			   let languageIdent = value["id"] as? String
			{
				return languageIdent == langQID
			}
			return false
		})

		// find the preferred property
		let preferred = propertyList.first(where: { ($0["rank"] as? String) == "preferred" }) ?? propertyList.first

		// extract the value
		if let best = locale ?? preferred,
		   let mainsnak = best["mainsnak"] as? [String: Any],
		   let datavalue = mainsnak["datavalue"] as? [String: Any],
		   let value = datavalue["value"] as? String
		{
			return value
		}

		return nil
	}

	private func valuesForP31(inEntity entity: [String: Any]) -> [String: String]? {
		guard
			let propertyList = propertyListFor(property: "P31", inEntity: entity)
		else { return nil }

		// extract the text for each language
		var result: [String: String] = [:]
		for item in propertyList {
			guard let mainsnak = item["mainsnak"] as? [String: Any],
			      let datavalue = mainsnak["datavalue"] as? [String: Any],
			      let value = datavalue["value"] as? [String: Any],
			      let language = value["language"] as? String,
			      let text = value["text"] as? String
			else { continue }
			result[language] = text
		}
		return result
	}

	private func entity(in entities: [String: Any]?, withTitlePrefix prefixList: [String]) -> [String: Any]? {
		return entities?.values.first(where: {
			if let q = $0 as? [String: Any],
			   let links = q["sitelinks"] as? [String: Any],
			   let wiki = links["wiki"] as? [String: Any],
			   let title = wiki["title"] as? String
			{
				return prefixList.contains(where: { title.hasPrefix($0) })
			}
			return false
		}) as? [String: Any]
	}

	private func descriptionForJson(data: Data, language: String, imageWidth: Int) -> KeyValueDescription? {
		guard
			let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
			let entities = json["entities"] as? [String: Any]
		else { return nil }

		// fetch the language code in use, if any
		let langWiki = wikiLanguageCodeFor(languageCode: language)
		var langQID = ""
		if let entity = entity(in: entities, withTitlePrefix: ["Locale:"]) {
			langQID = entity["id"] as? String ?? ""
		}

		guard let entity = entity(in: entities, withTitlePrefix: ["Key:", "Tag:"]) else { return nil }

		// fetch the description text
		var description = ""
		if let descriptions = entity["descriptions"] as? [String: Any],
		   let descDict = (descriptions[langWiki] ?? descriptions["en"]) as? [String: Any]
		{
			description = descDict["value"] as? String ?? ""
		}

		// try to fetch image path from Wikimedia
		var imageName = ""
		var imagePath = ""
		if let name = valueFor(property: "P4", inEntity: entity, langQID: langQID) {
			imageName = encodedTag(name)
			imagePath = "https://commons.wikimedia.org/w/index.php"
		}
		// try to fetch image path from Openstreetmap
		if imageName == "",
		   let name = valueFor(property: "P28", inEntity: entity, langQID: langQID)
		{
			imageName = encodedTag(name)
			imagePath = "https://wiki.openstreetmap.org/w/index.php"
		}
		if imagePath != "" {
			imagePath = "\(imagePath)?title=Special:Redirect/file/\(imageName)&width=\(imageWidth)"
		}

		// determine the wiki page titles
		let pageTitles = valuesForP31(inEntity: entity) ?? [:]
		let pageTitle = pageTitles[langWiki] ?? pageTitles["en"] ?? ""

		if description == "", imagePath == "", pageTitle == "" {
			return nil
		}
		return KeyValueDescription(description: description,
		                           imagePath: imagePath,
		                           pageTitle: pageTitle)
	}

	private func imageFor(meta: KeyValueMetadata,
	                      completion: @escaping (KeyValueMetadata) -> Void) -> KeyValueMetadata?
	{
		if let image = imageCache.object(
			withKey: meta.imagePath,
			fallbackURL: {
				URL(string: meta.imagePath)
			},
			objectForData: { data in
				UIImage(data: data)
			},
			completion: { result in
				guard let image = try? result.get() else { return }
				let kv = KeyValueMetadata(key: meta.key,
				                          value: meta.value,
				                          pageTitle: meta.pageTitle,
				                          description: meta.description,
				                          imagePath: meta.imagePath,
				                          image: image)
				completion(kv)
			})
		{
			let kv = KeyValueMetadata(key: meta.key,
			                          value: meta.value,
			                          pageTitle: meta.pageTitle,
			                          description: meta.description,
			                          imagePath: meta.imagePath,
			                          image: image)
			return kv
		}
		return nil
	}

	// Returns description and image information about a key/value pair. If the
	// data is cached it is returned immediately, otherwise it is returned via callback.
	func wikiDataFor(key: String, value: String, language: String, imageWidth: Int,
	                 update: @escaping (KeyValueMetadata?) -> Void) -> KeyValueMetadata?
	{
		let meta = descriptionCache.object(
			withKey: language + ":" + key + "=" + value,
			fallbackURL: {
				let otherLang = self.wikiLanguageCodeFor(languageCode: language)
				let languages = otherLang == "" ? "en" : ("en%7C" + otherLang)
				let tagTitle = value == ""
					? "Key:" + self.encodedTag(key)
					: "Tag:" + self.encodedTag(key) + self.equals + self.encodedTag(value)
				let langTitle = otherLang != "" ? "%7CLocale:" + otherLang : ""
				let path = "https://wiki.openstreetmap.org/w/api.php?" +
					["action=wbgetentities",
					 "sites=wiki",
					 ("titles=" + tagTitle + langTitle).replacingOccurrences(of: "_", with: "%20"),
					 "languages=" + languages.replacingOccurrences(of: "_", with: "%20"),
					 "format=json"]
					.joined(separator: "&")
				return URL(string: path)
			},
			objectForData: { data in
				self.descriptionForJson(data: data, language: language, imageWidth: imageWidth)
			},
			completion: { result in
				guard let result = try? result.get() else {
					update(nil)
					return
				}
				let kv = KeyValueMetadata(key: key,
				                          value: value,
				                          pageTitle: result.pageTitle,
				                          description: result.description,
				                          imagePath: result.imagePath,
				                          image: nil)
				if let image = self.imageFor(meta: kv, completion: update) {
					update(image)
				} else {
					update(kv)
				}
			})
		guard let meta = meta else { return nil }

		if let image = imageCache.object(
			withKey: meta.imagePath,
			fallbackURL: {
				URL(string: meta.imagePath)
			},
			objectForData: { data in
				UIImage(data: data)
			},
			completion: { result in
				let kv = KeyValueMetadata(key: key,
				                          value: value,
				                          pageTitle: meta.pageTitle,
				                          description: meta.description,
				                          imagePath: meta.imagePath,
				                          image: try? result.get())
				update(kv)
			})
		{
			let kv = KeyValueMetadata(key: key,
			                          value: value,
			                          pageTitle: meta.pageTitle,
			                          description: meta.description,
			                          imagePath: meta.imagePath,
			                          image: image)
			return kv
		}
		return nil
	}
}
