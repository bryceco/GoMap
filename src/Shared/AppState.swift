//
//  AppState.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/16/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

class Settings {
	@Notify var enableRotation: Bool = UserPrefs.shared.mapViewEnableRotation.value ?? true {
		didSet {
			UserPrefs.shared.mapViewEnableRotation.value = enableRotation
		}
	}

	@Notify var enableBirdsEye = UserPrefs.shared.mapViewEnableBirdsEye.value ?? false {
		didSet {
			UserPrefs.shared.mapViewEnableBirdsEye.value = enableBirdsEye
		}
	}

	var enableAutomaticCacheManagement: Bool = UserPrefs.shared.automaticCacheManagement.value ?? true {
		didSet {
			UserPrefs.shared.automaticCacheManagement.value = enableAutomaticCacheManagement
		}
	}

	@Notify var displayGpxTracks: Bool = UserPrefs.shared.mapViewEnableBreadCrumb.value ?? false {
		didSet {
			UserPrefs.shared.mapViewEnableBreadCrumb.value = displayGpxTracks
		}
	}

	@Notify var buttonLayout: MainViewButtonLayout = MainViewButtonLayout(rawValue: UserPrefs.shared.mapViewButtonLayout.value ?? -1) ?? .buttonsOnRight {
		didSet {
			UserPrefs.shared.mapViewButtonLayout.value = buttonLayout.rawValue
		}
	}

	@Notify var enableTurnRestriction = UserPrefs.shared.mapViewEnableTurnRestriction.value ?? false {
		didSet {
			UserPrefs.shared.mapViewEnableTurnRestriction.value = enableTurnRestriction
		}
	}


}

final class AppState {
	static let shared = AppState()

	let settings = Settings()
	let tileServerList = TileServerList()

	let gpxTracks = GpxTracks()

	func save() {
		tileServerList.save()
		gpxTracks.saveActiveTrack()
	}
}
