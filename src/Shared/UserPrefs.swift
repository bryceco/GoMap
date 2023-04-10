//
//  UserPrefs.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/9/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

class UserPrefs {
	enum Pref: String {
		case userName = "userName"
		case appVersion = "appVersion"
		case mapViewButtonLayout = "buttonLayout"

		case hoursRecognizerLanguage = "HoursRecognizerLanguage"

		case poiTabIndex = "POITabIndex"
		case copyPasteTags = "copyPasteTags"
		case currentRegion = "CurrentRegion"

		// Next OSM ID
		case nextUnusedIdentifier = "nextUnusedIdentifier"

		case osmServerUrl = "OSM Server"
		case preferredLanguage = "preferredLanguage"

		// Uploads
		case recentCommitComments = "recentCommitComments"
		case recentSourceComments = "recentSourceComments"
		case uploadComment = "uploadComment"
		case uploadSource = "uploadSource"
		case userDidPreviousUpload = "userDidPreviousUpload"
		case uploadCountPerVersion = "uploadCount"

		// MapView
		case view_scale = "view.scale"
		case view_latitude = "view.latitude"
		case view_longitude = "view.longitude"
		case mapViewState = "mapViewState"
		case mapViewOverlays = "mapViewOverlays"
		case mapViewEnableBirdsEye = "mapViewEnableBirdsEye"
		case mapViewEnableRotation = "mapViewEnableRotation"
		case automaticCacheManagement = "automaticCacheManagement"
		case mapViewEnableUnnamedRoadHalo = "mapViewEnableUnnamedRoadHalo"
		case mapViewEnableBreadCrumb = "mapViewEnableBreadCrumb"
		case mapViewEnableTurnRestriction = "mapViewEnableTurnRestriction"
		case latestAerialCheckLatLon = "LatestAerialCheckLatLon"

		// Nominatim
		case searchHistory = "searchHistory"

		// GPX
		case gpxRecordsTracksInBackground = "GpxTrackBackgroundTracking"
		case gpxUploadedGpxTracks = "GpxUploads"
		case gpxTracksExpireAfterDays = "GpxTrackExpirationDays"

		// Quest stuff
		case questTypeEnabledDict = "QuestTypeEnabledDict"
		case questUserDefinedList = "QuestUserDefinedList"

		// Tile Server List
		case lastImageryDownloadDate = "lastImageryDownloadDate"
		case customAerialList = "AerialList"
		case currentAerialSelection = "AerialListSelection"
		case recentAerialsList = "AerialListRecentlyUsed"

		// Stuff for most recent POI features
		case mostRecentTypesMaximum = "mostRecentTypesMaximum"
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

	func synchronize() {
		UserDefaults.standard.synchronize()
	}

	// String
	func string(forKey key: Pref) -> String? {
		return UserDefaults.standard.string(forKey: key.rawValue)
	}

	func set(_ value: String?, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
	}

	// Integer
	func integer(forKey key: Pref) -> Int? {
		guard
			let value = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber
		else {
			return nil
		}
		return value.intValue
	}

	func set(_ value: Int, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
	}

	// Double
	func double(forKey key: Pref) -> Double? {
		guard
			let value = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber
		else {
			return nil
		}
		return value.doubleValue
	}

	func set(_ value: Double, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
	}

	// Bool
	func bool(forKey key: Pref) -> Bool? {
		guard
			let value = UserDefaults.standard.object(forKey: key.rawValue) as? NSNumber
		else {
			return nil
		}
		return value.boolValue
	}

	func set(_ value: Bool, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
	}

	// Object
	func object(forKey key: Pref) -> Any? {
		// This might be stored as an NSNumber object, need to test if it matters
		return UserDefaults.standard.object(forKey: key.rawValue)
	}

	func set(object value: Any?, forKey key: Pref) {
		UserDefaults.standard.set(value, forKey: key.rawValue)
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

		case .osmServerUrl:
			return false

		case .preferredLanguage:
			return true

		case .hoursRecognizerLanguage,
		     .copyPasteTags,
		     .currentRegion,
		     .poiTabIndex:
			return true

		// POI types
		case .mostRecentTypesMaximum,
		     .mostRecentTypes_point,
		     .mostRecentTypes_line,
		     .mostRecentTypes_area,
		     .mostRecentTypes_vertex,
		     .questTypeEnabledDict,
		     .questUserDefinedList:
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

	static func prefFor(geom: GEOMETRY) -> Self {
		switch geom {
		case .AREA: return .mostRecentTypes_area
		case .VERTEX: return .mostRecentTypes_vertex
		case .LINE: return .mostRecentTypes_line
		case .POINT: return .mostRecentTypes_point
		}
	}
}
