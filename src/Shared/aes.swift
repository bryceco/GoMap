//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  aes.swift
//  Go Map!!
//
//  Created by Bryce on 3/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import CommonCrypto
import Foundation

let key: [__uint8_t] = [250, 157, 60, 79, 142, 134, 229, 129, 138, 126, 210, 129, 29, 71, 160, 208]

@objcMembers
class aes: NSObject {
    class func encryptData(_ data: Data, key: UnsafePointer<UInt8>) -> Data {
        return self.aesOperation(CCOperation(kCCEncrypt), on: data, key: key)
    }

    class func decryptData(_ data: Data, key: UnsafePointer<UInt8>) -> Data {
        return self.aesOperation(CCOperation(kCCDecrypt), on: data, key: key)
    }

    class func aesOperation(
        _ op: CCOperation,
        on data: Data,
        key: UnsafePointer<UInt8>
    ) -> Data {
        var buffer = [UInt8](repeating: 0, count: data.count + kCCKeySizeAES128)
        var bufferLen: size_t = 0
        CCCrypt(
            op,
            
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            key,
            kCCKeySizeAES128,
            nil,
            (data as NSData).bytes,
            data.count,
            &buffer,
            MemoryLayout.size(ofValue: buffer),
            &bufferLen)
        return Data(bytes: buffer, count: bufferLen)
    }

    class func encryptString(_ string: String) -> String {
        let data = string.data(using: .utf8)
        var dec: Data? = nil
        if let data = data {
            dec = aes.encryptData(data, key: key)
        }
        return dec?.base64EncodedString(options: []) ?? ""
    }

    class func decryptString(_ string: String) -> String {
        let data = Data(base64Encoded: string, options: [])
        var dec: Data? = nil
        if let data = data {
            dec = aes.decryptData(data, key: key)
        }
        if let dec = dec {
            return String(data: dec, encoding: .utf8) ?? ""
        }
        return ""
    }
}
