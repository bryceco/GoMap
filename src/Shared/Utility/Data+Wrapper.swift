//
//  Data+Wrapper.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/22/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

extension Data {
	func asStruct<Type: Any>() -> Type? {
		if count == MemoryLayout<Type>.size {
			return withUnsafeBytes({ $0.load(as: Type.self) })
		}
		return nil
	}

	static func fromStruct(_ v: Any) -> Data {
		var v = v
		return Data(bytes: &v, count: MemoryLayout.size(ofValue: v))
	}
}
