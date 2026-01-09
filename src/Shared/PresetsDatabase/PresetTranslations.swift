//
//  PresetTranslations.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/2/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Swift

class PresetTranslations: Codable {
	var languageDict: [String: Language] = [:]
	var yesForLocale = "Yes"
	var noForLocale = "No"
	var unknownForLocale = "Unknown"

	static let shared = {
		let me = PresetTranslations()

		if isUnderDebugger() {
			// test all preset languages
			for lang in PresetLanguages.languageCodeList {
				do {
					try me.setLanguage(lang)
				} catch {
					print(error)
					MessageDisplay.shared.showInternalError(error, context: "Error initializing language: \(lang)")
				}
			}
		}

		let langCode = PresetLanguages.preferredPresetLanguageCode()
		do {
			try me.setLanguage(langCode)
		} catch {
			// never returns
			MessageDisplay.shared.showInternalError(error, context: "Error initializing language: \(langCode)")
		}
		return me
	}()

	var languageCodes: [String] = []
	func setLanguage(_ code: String) throws {
		// choose the set of translations we'll use
		if let dash = code.firstIndex(of: "-") {
			// If the language is a code like "en-US" we want to use both the "en" and "en-US" translations
			let baseCode = String(code.prefix(upTo: dash))
			languageCodes = Array([code, baseCode, "en"].removingDuplicatedItems())
		} else {
			languageCodes = Array([code, "en"].removingDuplicatedItems())
		}

		// ensure data files are loaded for them
		for lang in languageCodes where !languageDict.keys.contains(lang) {
			let data = try PresetsDatabase.dataForFile("translations/\(code).json")
			try addTranslation(from: data)
		}

		// get localized common words
		yesForLocale = languageCodes
			.compactMap { languageDict[$0]?.presets?.fields["internet_access"]?.options?["yes"]?.title }.first ?? "Yes"
		noForLocale = languageCodes
			.compactMap { languageDict[$0]?.presets?.fields["internet_access"]?.options?["no"]?.title }.first ?? "No"
		unknownForLocale = languageCodes.compactMap { languageDict[$0]?.presets?.fields["opening_hours"]?.placeholder }
			.first ?? "Unknown"
	}

	func addTranslation(from data: Data) throws {
		let trans = try JSONDecoder().decode([String: Language].self, from: data)
		for (key, value) in trans {
			languageDict[key] = value
		}
	}

	func name(for category: PresetCategory) -> String? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.categories[category.categoryID]?.name }.first
	}

	func name(for feature: PresetFeature) -> String? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.presets[feature.featureID]?.name }.first
	}

	func label(for field: PresetField) -> String? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.fields[field.identifier]?.label }.first
	}

	func placeholder(for field: PresetField) -> String? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.fields[field.identifier]?.placeholder }.first
	}

	func placeholders(for field: PresetField) -> [String: String]? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.fields[field.identifier]?.placeholders }.first
	}

	func options(for field: PresetField) -> [String: Option]? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.fields[field.identifier]?.options }.first
	}

	func types(for field: PresetField) -> [String: String]? {
		return languageCodes.compactMap { languageDict[$0]?.presets?.fields[field.identifier]?.types }.first
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

		enum CodingKeys: String, CodingKey {
			case categories
			case fields
			case presets
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			categories = try container.decode([String: Category].self, forKey: .categories)
			fields = try container.decode([String: Field].self, forKey: .fields)
			presets = try container.decode([String: Feature].self, forKey: .presets)
				// FIXME: remove once id-tagging-schema is fixed
				.compactMapValues { $0.name == nil ? nil : $0 }
		}
	}

	struct Category: Codable {
		let name: String
	}

	struct Feature: Codable {
		let name: String? // FIXME: only optional because iD-tagging-schema is temporarily broken
		let terms: String?
		let aliases: String?
	}

	struct Field: Codable {
		let label: String?
		let options: [String: Option]?
		let placeholder: String?
		let placeholders: [String: String]? // for address field
		let terms: String?
		let types: [String: String]? // for access field
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
			case let .shortText(string): return string
			case let .longText(strings): return strings.title
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
			                                       debugDescription: "Invalid data shape in Option")
		}

		func encode(to encoder: Encoder) throws {
			var singleValueContainer = encoder.singleValueContainer()
			switch self {
			case let .shortText(string):
				try singleValueContainer.encode(string)
			case let .longText(strings):
				try singleValueContainer.encode(strings)
			}
		}
	}
}
