//
//  PresetTranslations.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/2/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Swift

class PresetTranslations: Codable {
	var languages: [String: Language] = [:]

	func addTranslation(from data: Data) throws {
		let trans = try JSONDecoder().decode([String: Language].self, from: data)
		for (key,value) in trans {
			languages[key] = value
		}
	}

	func asPrettyJSON() -> String {
		do {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			let data = try encoder.encode(self)
			let text = String(decoding: data, as: UTF8.self)
			return text
		} catch {
			return "\(error)"
		}
	}

	struct Language: Codable {
		let presets: AllTranslations?
	}
	struct AllTranslations: Codable {
		let categories: [String: Category]
		let fields: [String: Field]
		let presets: [String: Feature]
	}
	struct Category: Codable {
		let name: String
	}
	enum Option: Codable {
		struct TitleDescription: Codable {
			let title: String?
			let description: String?
		}
		case shortText(String)
		case longText(TitleDescription)
		var title: String? {
			switch self {
				case .shortText(let string): return string
				case .longText(let strings): return strings.title
			}
		}
		init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			if let strings = try? container.decode(TitleDescription.self) {
				self = .longText(strings)
				return
			}
			if let strings = try? container.decode(String.self) {
				self = .shortText(strings)
				return
			}
			throw DecodingError.dataCorruptedError(in: container,
												   debugDescription: "Invalid data shape in Option" )
		}
		func encode(to encoder: Encoder) throws {
			var singleValueContainer = encoder.singleValueContainer()
			switch self {
			case .shortText(let string):
				try singleValueContainer.encode(string)
			case .longText(let strings):
				try singleValueContainer.encode(strings)
			}
		}
	}
	struct Field: Codable {
		let label: String?
		let options: [String: Option]?
		let placeholder: String?
		let terms: String?
	}
	struct Feature: Codable {
		let name: String
		let terms: String?
		let aliases: String?
	}
	struct Strings: Codable {
		let label: String
		let options: [String: String]?
		let placeholder: String?
	}
}
