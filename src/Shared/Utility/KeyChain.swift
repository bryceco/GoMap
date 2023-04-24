//
//  KeyChain.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import CommonCrypto
import Foundation
import Security

private let APP_NAME = "Go Map"

final class KeyChain {
	class func searchDictionary(forIdentifier identifier: String) -> [String: Any] {
		guard let encodedIdentifier = identifier.data(using: .utf8) else { return [:] }
		// Setup dictionary to access keychain.
		return [
			// Specify we are using a password (rather than a certificate, internet password, etc).
			kSecClass as String: kSecClassGenericPassword,
			// Uniquely identify this keychain accessor.
			kSecAttrService as String: APP_NAME,
			// Uniquely identify the account who will be accessing the keychain.
			kSecAttrGeneric as String: encodedIdentifier,
			kSecAttrAccount as String: encodedIdentifier
		]
	}

	class func getStringForIdentifier(_ identifier: String) -> String? {
		// Setup dictionary to access keychain.
		var searchDictionary = self.searchDictionary(forIdentifier: identifier)
		// Limit search results to one.
		searchDictionary[kSecMatchLimit as String] = kSecMatchLimitOne
		// Specify we want NSData/CFData returned.
		searchDictionary[kSecReturnData as String] = kCFBooleanTrue!

		// Search.
		var foundData: AnyObject?
		let status = SecItemCopyMatching(searchDictionary as CFDictionary, &foundData)
		if status == noErr,
		   let data = foundData as? Data,
		   let string = String(data: data, encoding: .utf8)
		{
			return string
		}
		return nil
	}

	private class func update(_ value: String, forIdentifier identifier: String) -> Bool {
		// Setup dictionary to access keychain.
		let searchDictionary = self.searchDictionary(forIdentifier: identifier)
		guard let valueData = value.data(using: .utf8) else { return false }
		let updateDictionary = [kSecValueData as String: valueData]

		// Update.
		let status = SecItemUpdate(searchDictionary as CFDictionary,
		                           updateDictionary as CFDictionary)
		return status == errSecSuccess
	}

	class func setString(_ value: String, forIdentifier identifier: String) -> Bool {
		var searchDictionary = self.searchDictionary(forIdentifier: identifier)
		guard let valueData = value.data(using: .utf8) else { return false }
		searchDictionary[kSecValueData as String] = valueData

		// Protect the keychain entry so it's only valid when the device is unlocked.
		searchDictionary[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

		// Add it
		let status = SecItemAdd(searchDictionary as CFDictionary, nil)

		// If the addition was successful, return. Otherwise, attempt to update existing key or quit (return NO).
		if status == errSecSuccess {
			return true
		} else if status == errSecDuplicateItem {
			return update(value, forIdentifier: identifier)
		}
		return false
	}

	class func deleteString(forIdentifier identifier: String) {
		let searchDictionary = self.searchDictionary(forIdentifier: identifier)

		// Delete.
		SecItemDelete(searchDictionary as CFDictionary)
	}
}
