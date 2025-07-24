//
//  MainActor+Extension.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/23/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import Foundation

extension MainActor {
	static func runAfter(nanoseconds: UInt64, operation: @escaping @MainActor() -> Void) {
		Task { @MainActor in
			try? await Task.sleep(nanoseconds: nanoseconds)
			operation()
		}
	}
}
