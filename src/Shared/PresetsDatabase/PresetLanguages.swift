//
//  PresetLanguages.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/11/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation

final class PresetLanguages {

	static let codeList: [String] = {
		let path = Bundle.main.resourcePath! + "/presets/translations"
		var list = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
		list = list.map({ $0.replacingOccurrences(of: ".json", with: "") })
		list.sort(by: { code1, code2 -> Bool in
			let s1 = PresetLanguages.languageNameForCode(code1) ?? ""
			let s2 = PresetLanguages.languageNameForCode(code2) ?? ""
			return s1.caseInsensitiveCompare(s2) == ComparisonResult.orderedAscending
		})
		return list
	}()

	init() {
	}

	func preferredLanguageIsDefault() -> Bool {
		let code = UserDefaults.standard.object(forKey: "preferredLanguage") as? String
		return code == nil
	}

	func preferredLanguageCode() -> String {
		var code = UserDefaults.standard.object(forKey: "preferredLanguage") as? String
		if code == nil {
			let userPrefs = NSLocale.preferredLanguages
			let matches = Bundle.preferredLocalizations(from: PresetLanguages.codeList, forPreferences: userPrefs)
			code = matches.first ?? "en"
		}
		return code!
	}

	func setPreferredLanguageCode(_ code: String?) {
		UserDefaults.standard.set(code, forKey: "preferredLanguage")
	}

	func languageCodes() -> [String] {
		return PresetLanguages.codeList
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
