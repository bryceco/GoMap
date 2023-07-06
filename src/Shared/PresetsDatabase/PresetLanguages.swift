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
		let path = Bundle.main.resourcePath! + "/presets/translations"
		var list = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
		list = list.map({ $0.replacingOccurrences(of: ".json", with: "") })
		list.sort(by: { code1, code2 -> Bool in
			let s1 = PresetLanguages.languageNameForCode(code1) ?? ""
			let s2 = PresetLanguages.languageNameForCode(code2) ?? ""
			return s1.caseInsensitiveCompare(s2) == .orderedAscending
		})
		return list
	}()

	class func preferredLanguageIsDefault() -> Bool {
		let code = UserDefaults.standard.object(forKey: "preferredLanguage") as? String
		return code == nil
	}

	static let preferredLanguageCode_ = {
		if let pref = Locale.preferredLanguages.first {
			// the language code includes a region that we don't want, so rebuild it without it
			let locale = Locale(identifier: pref)
			let code = [locale.languageCode, locale.scriptCode]
				.compactMap { $0 }
				.joined(separator: "-")
			return code
		}
		return "en"
	}()
	class func preferredLanguageCode() -> String {
		return Self.preferredLanguageCode_
	}

	class func preferredPresetLanguageCode() -> String {
		if let code = UserDefaults.standard.object(forKey: "preferredLanguage") as? String {
			return code
		}
		let matches = Bundle.preferredLocalizations(from: PresetLanguages.languageCodeList,
		                                            forPreferences: NSLocale.preferredLanguages)
		return matches.first ?? "en"
	}

	// code is either a language core, or nil if the default is requested
	class func setPreferredLanguageCode(_ code: String?) {
		UserDefaults.standard.set(code, forKey: "preferredLanguage")
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
