//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
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

class KeyChain: NSObject {
    class func searchDictionary(forIdentifier identifier: String) -> [CFString : Any]? {
        let encodedIdentifier = identifier.data(using: .utf8)
        // Setup dictionary to access keychain.
        if let encodedIdentifier = encodedIdentifier {
            return [
            // Specify we are using a password (rather than a certificate, internet password, etc).
                kSecClass: kSecClassGenericPassword,
            // Uniquely identify this keychain accessor.
                kSecAttrService: APP_NAME,
            // Uniquely identify the account who will be accessing the keychain.
                kSecAttrGeneric: encodedIdentifier,
                kSecAttrAccount: encodedIdentifier
            ]
        }
        return nil
    }

    class func getStringForIdentifier(_ identifier: String) -> String {
        // Setup dictionary to access keychain.
        let searchDictionary = self.searchDictionary(forIdentifier: identifier) as? NSMutableDictionary ?? [:]
        searchDictionary.addEntries(from: [
            // Limit search results to one.
                kSecMatchLimit: kSecMatchLimitOne,
            // Specify we want NSData/CFData returned.
                kSecReturnData: kCFBooleanTrue
            ])
        // Search.
        var foundDict: CFTypeRef? = nil
        var status: OSStatus? = nil
        status = SecItemCopyMatching(searchDictionary, &foundDict)
        if status != noErr {
            return ""
        }
        let data = foundDict as? Data
        if data == nil {
            return ""
        }
        if let data = data {
            if let retString = String(data: data, encoding: .utf8) {
                return retString
            }
        }
        return ""
    }

    class func update(_ value: String, forIdentifier identifier: String) -> Bool {
        // Setup dictionary to access keychain.
        let searchDictionary = self.searchDictionary(forIdentifier: identifier)
        let valueData = value.data(using: .utf8)
        var updateDictionary: [CFString : Any] = [:]
        if let valueData = valueData {
            updateDictionary = [
                kSecValueData: valueData
            ]
        }

        // Update.
        var status: OSStatus? = nil
        if let dictionary = searchDictionary as CFDictionary?, let dictionary1 = updateDictionary as CFDictionary? {
            status = SecItemUpdate(
                dictionary,
                dictionary1)
        }

        return status == errSecSuccess
    }

    class func setString(_ value: String, forIdentifier identifier: String) -> Bool {
        let searchDictionary = self.searchDictionary(forIdentifier: identifier) as? NSMutableDictionary ?? [:]
        let valueData = value.data(using: .utf8)
        searchDictionary[kSecValueData] = valueData

        // Protect the keychain entry so it's only valid when the device is unlocked.
        searchDictionary[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked

        // Add.
        var status: OSStatus? = nil
        status = SecItemAdd(searchDictionary, nil)

        // If the addition was successful, return. Otherwise, attempt to update existing key or quit (return NO).
        if status == errSecSuccess {
            return true
        } else if status == errSecDuplicateItem {
            return self.update(value, forIdentifier: identifier)
        } else {
            return false
        }
    }

    class func deleteString(forIdentifier identifier: String) {
        let searchDictionary = self.searchDictionary(forIdentifier: identifier) as? NSMutableDictionary ?? [:]

        // Delete.
        SecItemDelete(searchDictionary)
    }
}
