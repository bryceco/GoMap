//
//  PresetLanguages.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/11/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

// This class provides a list of all languages that iD presets have been translated into,
// which is a larger list than the languages the app has been translated into.
final class PresetLanguages {
	static let languageCodeList: [String] = {
		guard
			let url = Bundle.main.resourceURL?.appendingPathComponent("presets/translations"),
			let files = try? FileManager.default.contentsOfDirectory(atPath: url.path)
		else {
			return []
		}
		var list = files
			.map({ $0.replacingOccurrences(of: ".json", with: "") })
			.filter { languageNameForCode($0) != nil } // ignore non-real languages
		list.sort(by: { code1, code2 -> Bool in
			let s1 = PresetLanguages.languageNameForCode(code1) ?? ""
			let s2 = PresetLanguages.languageNameForCode(code2) ?? ""
			return s1.caseInsensitiveCompare(s2) == .orderedAscending
		})
		return list
	}()

	class func preferredLanguageIsDefault() -> Bool {
		let code = UserPrefs.shared.preferredLanguage.value
		return code == nil
	}

	private static let preferredLanguageCodes_: [String] = Locale.preferredLanguages.map {
		// the language code includes a region that we don't want, so rebuild it without it
		let locale = Locale(identifier: $0)
		let code = [locale.languageCode, locale.scriptCode]
			.compactMap { $0 }
			.joined(separator: "-")
		return code
	}

	class func preferredLanguageCodes() -> [String] {
		return Self.preferredLanguageCodes_
	}

	class func preferredLanguageCode() -> String {
		return Self.preferredLanguageCodes().first ?? "en"
	}

	class func preferredPresetLanguageCode() -> String {
		if let code = UserPrefs.shared.preferredLanguage.value,
		   PresetLanguages.languageCodeList.contains(code)
		{
			return code
		}
		let matches = Bundle.preferredLocalizations(from: PresetLanguages.languageCodeList,
		                                            forPreferences: NSLocale.preferredLanguages)
		return matches.first ?? "en"
	}

	// code is either a language code, or nil if the default is requested
	class func setPreferredLanguageCode(_ code: String?) {
		UserPrefs.shared.preferredLanguage.value = code
	}

	class func languageNameForCode(_ code: String) -> String? {
		let locale = NSLocale(localeIdentifier: code)
		let name = locale.displayName(forKey: .identifier, value: code)
		return name
	}

	class func localLanguageNameForCode(_ code: String) -> String? {
		let locale = NSLocale.current as NSLocale
		let name = locale.displayName(forKey: .identifier, value: code)
		return name
	}
}
