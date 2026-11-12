//
//  GoMapWatchApp.swift
//  GoMapWatch
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI

@main
struct GoMapWatchApp: App {
	@StateObject private var model = WatchGpxModel()

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(model)
		}
	}
}
