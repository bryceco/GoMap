//
//  Data+Wrapper.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/22/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

extension Data {
	func asStruct<Type: Any>() -> Type? {
		if count == MemoryLayout<Type>.size {
			return withUnsafeBytes({ $0.load(as: Type.self) })
		}
		return nil
	}

	static func fromStruct<Type>(_ v: Type) -> Data {
		withUnsafePointer(to: v) { v2 in
			Data(bytes: v2, count: MemoryLayout.size(ofValue: v))
		}
	}
}
