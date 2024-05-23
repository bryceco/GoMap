//
//  UserPrefs.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/9/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

final class UserPrefs {
	enum Pref: String, CaseIterable {
		case userName
		case appVersion
		case mapViewButtonLayout = "buttonLayout"

		case hoursRecognizerLanguage = "HoursRecognizerLanguage"

		case poiTabIndex = "POITabIndex"
		case copyPasteTags
		case currentRegion = "CurrentRegion"

		// Next OSM ID
		case nextUnusedIdentifier

		case osmServerUrl = "OSM Server"
		case preferredLanguage

		// Uploads
		case recentCommitComments
		case recentSourceComments
		case uploadComment
		case uploadSource
		case userDidPreviousUpload
		case uploadCountPerVersion = "uploadCount"

		// MapView
		case view_scale = "view.scale"
		case view_latitude = "view.latitude"
		case view_longitude = "view.longitude"
		case mapViewState
		case mapViewOverlays
		case mapViewEnableBirdsEye
		case mapViewEnableRotation
		case automaticCacheManagement
		case mapViewEnableUnnamedRoadHalo
		case mapViewEnableBreadCrumb
		case mapViewEnableDataOverlay
		case mapViewEnableTurnRestriction
		case latestAerialCheckLatLon = "LatestAerialCheckLatLon"

		// Nominatim
		case searchHistory

		// GPX
		case gpxRecordsTracksInBackground = "GpxTrackBackgroundTracking"
		case gpxUploadedGpxTracks = "GpxUploads"
		case gpxTracksExpireAfterDays = "GpxTrackExpirationDays"

		// GeoJSON
		case geoJsonFileList = "GeoJsonFileList"
		case tileOverlaySelections

		// Quest stuff
		case questTypeEnabledDict = "QuestTypeEnabledDict"
		case questUserDefinedList = "QuestUserDefinedList"

		// Tile Server List
		case lastImageryDownloadDate
		case customAerialList = "AerialList"
		case currentAerialSelection = "AerialListSelection"
		case recentAerialsList = "AerialListRecentlyUsed"

		// POI presets
		case userDefinedPresetKeys

		// Stuff for most recent POI features
		case mostRecentTypesMaximum
		case mostRecentTypes_point = "mostRecentTypes.point"
		case mostRecentTypes_line = "mostRecentTypes.line"
		case mostRecentTypes_area = "mostRecentTypes.area"
		case mostRecentTypes_vertex = "mostRecentTypes.vertex"

		// Editor filters
		case editor_enableObjectFilters = "editor.enableObjectFilters"
		case editor_showLevel = "editor.showLevel"
		case editor_showLevelRange = "editor.showLevelRange"
		case editor_showPoints = "editor.showPoints"
		case editor_showTrafficRoads = "editor.showTrafficRoads"
		case editor_showServiceRoads = "editor.showServiceRoads"
		case editor_showPaths = "editor.showPaths"
		case editor_showBuildings = "editor.showBuildings"
		case editor_showLanduse = "editor.showLanduse"
		case editor_showBoundaries = "editor.showBoundaries"
		case editor_showWater = "editor.showWater"
		case editor_showRail = "editor.showRail"
		case editor_showPower = "editor.showPower"
		case editor_showPastFuture = "editor.showPastFuture"
		case editor_showOthers = "editor.showOthers"
	}

	static let shared = UserPrefs()
	private var onChangeDelegates: [Pref: [(Pref) -> Void]] = [:]

	init() {
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(Self.ubiquitousKeyValueStoreDidChange(_:)),
		                                       name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
		                                       object: NSUbiquitousKeyValueStore.default)
	}

	func onChange(_ key: Pref, callback: @escaping ((Pref) -> Void)) {
		var list = onChangeDelegates[key] ?? []
		list.append(callback)
		onChangeDelegates[key] = list
	}

	@objc func ubiquitousKeyValueStoreDidChange(_ notification: NSNotification) {
		let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
		let changes = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]

		switch reason {
		case NSUbiquitousKeyValueStoreServerChange:
			print("Server change")
		case NSUbiquitousKeyValueStoreInitialSyncChange:
			print("Initial sync change")
		case NSUbiquitousKeyValueStoreQuotaViolationChange:
			print("Quota violation")
		case NSUbiquitousKeyValueStoreAccountChange:
			print("Account change")
		default:
			print("other reason")
		}

		DispatchQueue.main.async {
			for key in changes ?? [] {
				guard let pref = Pref(rawValue: key) else { continue }
				for callback in self.onChangeDelegates[pref] ?? [] {
					callback(pref)
				}
			}
		}
	}

	func synchronize() {
		UserDefaults.standard.synchronize()
		NSUbiquitousKeyValueStore.default.synchronize()
	}

	func copyUserDefaultsToUbiquitousStore() {
		guard NSUbiquitousKeyValueStore.default.dictionaryRepresentation.count == 0 else {
			return
		}
		for pref in Pref.allCases where pref.sharedAcrossDevices {
			if let obj = UserDefaults.standard.object(forKey: pref.rawValue) {
				NSUbiquitousKeyValueStore.default.set(obj, forKey: pref.rawValue)
			}
		}
	}

	// String
	func string(forKey key: Pref) -> String? {
		return object(forKey: key) as? String
	}

	func set(_ value: String?, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
		if key.sharedAcrossDevices {
			NSUbiquitousKeyValueStore.default.set(value, forKey: key.rawValue)
		}
	}

	// Integer
	func integer(forKey key: Pref) -> Int? {
		guard let number = object(forKey: key) as? NSNumber else {
			return nil
		}
		return number.intValue
	}

	func set(_ value: Int, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
		if key.sharedAcrossDevices {
			NSUbiquitousKeyValueStore.default.set(value, forKey: key.rawValue)
		}
	}

	// Double
	func double(forKey key: Pref) -> Double? {
		guard let number = object(forKey: key) as? NSNumber else {
			return nil
		}
		return number.doubleValue
	}

	func set(_ value: Double, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
		if key.sharedAcrossDevices {
			NSUbiquitousKeyValueStore.default.set(value, forKey: key.rawValue)
		}
	}

	// Bool
	func bool(forKey key: Pref) -> Bool? {
		guard let number = object(forKey: key) as? NSNumber else {
			return nil
		}
		return number.boolValue
	}

	func set(_ value: Bool, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
		if key.sharedAcrossDevices {
			NSUbiquitousKeyValueStore.default.set(value, forKey: key.rawValue)
		}
	}

	// Object
	func object(forKey key: Pref) -> Any? {
		if key.sharedAcrossDevices,
		   let obj = NSUbiquitousKeyValueStore.default.object(forKey: key.rawValue)
		{
			return obj
		}
		return UserDefaults.standard.object(forKey: key.rawValue)
	}

	func set(object value: Any?, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
		if key.sharedAcrossDevices {
			NSUbiquitousKeyValueStore.default.set(value, forKey: key.rawValue)
		}
	}
}

extension UserPrefs.Pref {
	var sharedAcrossDevices: Bool {
		switch self {
		case .userName,
		     .appVersion,
		     .uploadCountPerVersion,
		     .nextUnusedIdentifier:
			return false

		case .gpxTracksExpireAfterDays,
		     .gpxRecordsTracksInBackground,
		     .gpxUploadedGpxTracks:
			return false

		case .geoJsonFileList,
		     .mapViewEnableDataOverlay,
		     .tileOverlaySelections:
			return false

		case .osmServerUrl:
			return false

		case .preferredLanguage:
			return true

		case .hoursRecognizerLanguage,
		     .copyPasteTags,
		     .poiTabIndex:
			return true

		// POI types
		case .userDefinedPresetKeys:
			return true
		case .mostRecentTypesMaximum,
		     .mostRecentTypes_point,
		     .mostRecentTypes_line,
		     .mostRecentTypes_area,
		     .mostRecentTypes_vertex:
			return true

		// Object filters
		case .editor_enableObjectFilters,
		     .editor_showLevel,
		     .editor_showLevelRange,
		     .editor_showPoints,
		     .editor_showTrafficRoads,
		     .editor_showServiceRoads,
		     .editor_showPaths,
		     .editor_showBuildings,
		     .editor_showLanduse,
		     .editor_showBoundaries,
		     .editor_showWater,
		     .editor_showRail,
		     .editor_showPower,
		     .editor_showPastFuture,
		     .editor_showOthers:
			return false

		// MapView
		case .view_scale,
		     .view_latitude,
		     .view_longitude,
		     .currentRegion,
		     .mapViewState,
		     .mapViewOverlays,
		     .mapViewEnableBirdsEye,
		     .mapViewEnableRotation,
		     .automaticCacheManagement,
		     .mapViewEnableUnnamedRoadHalo,
		     .mapViewEnableBreadCrumb,
		     .mapViewEnableTurnRestriction,
		     .mapViewButtonLayout,
		     .latestAerialCheckLatLon:
			return false

		case .lastImageryDownloadDate,
		     .currentAerialSelection,
		     .recentAerialsList:
			return false

		case .questTypeEnabledDict,
		     .questUserDefinedList:
			return true

		// User-defined imagery
		case .customAerialList:
			return true

		case .searchHistory:
			return true

		case .uploadComment,
		     .uploadSource,
		     .recentCommitComments,
		     .recentSourceComments,
		     .userDidPreviousUpload:
			return true
		}
	}

	static func mostRecentPrefFor(geom: GEOMETRY) -> Self {
		switch geom {
		case .AREA: return .mostRecentTypes_area
		case .VERTEX: return .mostRecentTypes_vertex
		case .LINE: return .mostRecentTypes_line
		case .POINT: return .mostRecentTypes_point
		}
	}
}
