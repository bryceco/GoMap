//
//  aes.swift
//  Go Map!!
//
//  Created by Bryce on 3/2/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import CommonCrypto
import Foundation

private let privateKey: [__uint8_t] = [250, 157, 60, 79, 142, 134, 229, 129, 138, 126, 210, 129, 29, 71, 160, 208]

final class aes {
    class func encryptData(_ data: Data, key: UnsafePointer<UInt8>) -> Data? {
        return self.aesOperation(CCOperation(kCCEncrypt), on: data, key: key)
    }

    class func decryptData(_ data: Data, key: UnsafePointer<UInt8>) -> Data? {
        return self.aesOperation(CCOperation(kCCDecrypt), on: data, key: key)
    }

    class func aesOperation( _ op: CCOperation, on data: Data, key: UnsafePointer<UInt8> ) -> Data? {
        var buffer = [UInt8](repeating: 0, count: data.count + kCCKeySizeAES128)
        var bufferLen: size_t = 0
        let status = CCCrypt(
            op,
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionPKCS7Padding),
            key,
            kCCKeySizeAES128,
            nil,
            (data as NSData).bytes, data.count,
			&buffer, buffer.count,
            &bufferLen)
		if status == kCCSuccess {
			return Data(bytes: buffer, count: bufferLen)
		}
		return nil
    }

    class func encryptString(_ string: String) -> String {
		if let data = string.data(using: .utf8),
		   let dec = aes.encryptData(data, key: privateKey)
		{
			return dec.base64EncodedString(options: [])
        }
		return ""
    }

    class func decryptString(_ string: String) -> String {
		if let data = Data(base64Encoded: string, options: []),
		   let dec = aes.decryptData(data, key: privateKey),
		   let string = String(data: dec, encoding: .utf8)
		{
					return string
        }
		return ""
    }
}
