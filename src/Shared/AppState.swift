//
//  AppState.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/16/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

final class AppState {
	static let shared = AppState()

	let tileServerList = TileServerList()

	let gpxTracks = GpxTracks()

	func save() {
		tileServerList.save()
		gpxTracks.saveActiveTrack()
	}
}
