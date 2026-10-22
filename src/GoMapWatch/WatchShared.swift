//
//  WatchShared.swift
//  GoMapWatch
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import SwiftUI

let gpxTraceSymbol = "point.bottomleft.forward.to.point.topright.scurvepath"

extension Color {
	static let goMapGreen = Color(red: 0x4C / 255.0, green: 0xD9 / 255.0, blue: 0x64 / 255.0)
	static let goMapYellow = Color(red: 0xFF / 255.0, green: 0xCC / 255.0, blue: 0x00 / 255.0)
	static let goMapSlate = Color(red: 0x34 / 255.0, green: 0x49 / 255.0, blue: 0x5E / 255.0)
	static let gpxTrace = goMapGreen
}

enum GpxComplicationStore {
	static let appGroup = "group.com.bryceco.GoMap"
	static let widgetKind = "GpxComplication"
	private static let key = "gpxState"

	static func load() -> GpxWatchState {
		guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key),
		      let state = try? JSONDecoder().decode(GpxWatchState.self, from: data)
		else {
			return GpxWatchState()
		}
		return state
	}

	static func save(_ state: GpxWatchState) {
		var state = state
		state.outline = []
		guard let data = try? JSONEncoder().encode(state) else { return }
		UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
	}
}
