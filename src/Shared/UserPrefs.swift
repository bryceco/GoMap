//
//  UserPrefs.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/9/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import Foundation

private protocol PrefProtocol {
	associatedtype T
	var key: String { get }
	var ubiquitous: Bool { get }
	var value: T? { get set }
	func didChange()
}

class Pref<T>: PrefProtocol {
	let key: String
	let ubiquitous: Bool

	init(key: String, ubiquitous: Bool = false) {
		assert(key != "")
		self.key = key
		self.ubiquitous = ubiquitous
	}

	var value: T? {
		get {
			if ubiquitous,
			   let obj = NSUbiquitousKeyValueStore.default.object(forKey: key),
			   let obj2 = obj as! T?
			{
				return obj2
			}
			return UserDefaults.standard.value(forKey: key) as! T?
		}
		set {
			UserDefaults.standard.set(newValue, forKey: key)
			if ubiquitous {
				NSUbiquitousKeyValueStore.default.set(newValue, forKey: key)
			}
		}
	}

	private var onChangeCallbacks: [(Pref<T>) -> Void] = []

	func onChangePerform(_ callback: @escaping ((Pref<T>) -> Void)) {
		onChangeCallbacks.append(callback)
	}

	func didChange() {
		for callback in onChangeCallbacks {
			callback(self)
		}
	}
}

final class UserPrefs {
	public static let shared = UserPrefs()

	let userName = Pref<String>(key: "userName")
	let appVersion = Pref<String>(key: "appVersion")
	let mapViewButtonLayout = Pref<Int>(key: "buttonLayout")
	let hoursRecognizerLanguage = Pref<String>(key: "HoursRecognizerLanguage", ubiquitous: true)

	let poiTabIndex = Pref<Int>(key: "POITabIndex", ubiquitous: true)
	let copyPasteTags = Pref<[String: String]>(key: "copyPasteTags", ubiquitous: true)
	let currentRegion = Pref<Data>(key: "CurrentRegion")

	// Next OSM ID
	let nextUnusedIdentifier = Pref<Int>(key: "nextUnusedIdentifier")

	let osmServerUrl = Pref<String>(key: "OSM Server")
	let preferredLanguage = Pref<String>(key: "preferredLanguage", ubiquitous: true)

	// Uploads
	let recentCommitComments = Pref<[String]>(key: "recentCommitComments", ubiquitous: true)
	let recentSourceComments = Pref<[String]>(key: "recentSourceComments", ubiquitous: true)
	let uploadComment = Pref<String>(key: "uploadComment", ubiquitous: true)
	let uploadSource = Pref<String>(key: "uploadSource", ubiquitous: true)
	let userDidPreviousUpload = Pref<Bool>(key: "userDidPreviousUpload", ubiquitous: true)
	let uploadCountPerVersion = Pref<Int>(key: "uploadCount")

	// MapView
	let view_scale = Pref<Double>(key: "view.scale")
	let view_latitude = Pref<Double>(key: "view.latitude")
	let view_longitude = Pref<Double>(key: "view.longitude")
	let mapViewState = Pref<Int>(key: "mapViewState")
	let mapViewOverlays = Pref<Int>(key: "mapViewOverlays")
	let mapViewEnableBirdsEye = Pref<Bool>(key: "mapViewEnableBirdsEye")
	let mapViewEnableRotation = Pref<Bool>(key: "mapViewEnableRotation")
	let automaticCacheManagement = Pref<Bool>(key: "automaticCacheManagement")
	let mapViewEnableBreadCrumb = Pref<Bool>(key: "mapViewEnableBreadCrumb")
	let mapViewEnableDataOverlay = Pref<Bool>(key: "mapViewEnableDataOverlay")
	let mapViewEnableTurnRestriction = Pref<Bool>(key: "mapViewEnableTurnRestriction")
	let latestAerialCheckLatLon = Pref<Data>(key: "LatestAerialCheckLatLon")
	let maximizeFrameRate = Pref<Bool>(key: "maximizeFrameRate")

	// Nominatim
	let searchHistory = Pref<[String]>(key: "searchHistory", ubiquitous: true)

	// GPX
	let gpxRecordsTracksInBackground = Pref<Bool>(key: "GpxTrackBackgroundTracking")
	let gpxUploadedGpxTracks = Pref<[String: NSNumber]>(key: "GpxUploads")
	let gpxTracksExpireAfterDays = Pref<Int>(key: "GpxTrackExpirationDays")

	// GeoJSON
	let geoJsonFileList = Pref<[String: Bool]>(key: "GeoJsonFileList")
	let tileOverlaySelections = Pref<[String]>(key: "tileOverlaySelections")

	// Quest stuff
	let questTypeEnabledDict = Pref<[String: Bool]>(key: "QuestTypeEnabledDict", ubiquitous: true)
	let questUserDefinedList = Pref<Data>(key: "QuestUserDefinedList", ubiquitous: true)

	// Tile Server List
	let lastImageryDownloadDate = Pref<Date>(key: "lastImageryDownloadDate")
	let customAerialList = Pref<[[String: Any]]>(key: "AerialList", ubiquitous: true)
	let currentAerialSelection = Pref<String>(key: "AerialListSelection")
	let recentAerialsList = Pref<[String]>(key: "AerialListRecentlyUsed")

	// Basemap server
	let currentBasemapSelection = Pref<String>(key: "BasemapSelectionId")

	// POI presets
	let userDefinedPresetKeys = Pref<Data>(key: "userDefinedPresetKeys", ubiquitous: true)
	let preferredUnitsForKeys = Pref<[String: String]>(key: "preferredUnitsForKeys", ubiquitous: true)

	// Stuff for most recent POI features
	let mostRecentTypesMaximum = Pref<Int>(key: "mostRecentTypesMaximum", ubiquitous: true)
	let mostRecentTypes_point = Pref<[String]>(key: "mostRecentTypes.point", ubiquitous: true)
	let mostRecentTypes_line = Pref<[String]>(key: "mostRecentTypes.line", ubiquitous: true)
	let mostRecentTypes_area = Pref<[String]>(key: "mostRecentTypes.area", ubiquitous: true)
	let mostRecentTypes_vertex = Pref<[String]>(key: "mostRecentTypes.vertex", ubiquitous: true)

	// Editor filters
	let editor_enableObjectFilters = Pref<Bool>(key: "editor.enableObjectFilters")
	let editor_showLevel = Pref<Bool>(key: "editor.showLevel")
	let editor_showLevelRange = Pref<String>(key: "editor.showLevelRange")
	let editor_showPoints = Pref<Bool>(key: "editor.showPoints")
	let editor_showTrafficRoads = Pref<Bool>(key: "editor.showTrafficRoads")
	let editor_showServiceRoads = Pref<Bool>(key: "editor.showServiceRoads")
	let editor_showPaths = Pref<Bool>(key: "editor.showPaths")
	let editor_showBuildings = Pref<Bool>(key: "editor.showBuildings")
	let editor_showLanduse = Pref<Bool>(key: "editor.showLanduse")
	let editor_showBoundaries = Pref<Bool>(key: "editor.showBoundaries")
	let editor_showWater = Pref<Bool>(key: "editor.showWater")
	let editor_showRail = Pref<Bool>(key: "editor.showRail")
	let editor_showPower = Pref<Bool>(key: "editor.showPower")
	let editor_showPastFuture = Pref<Bool>(key: "editor.showPastFuture")
	let editor_showOthers = Pref<Bool>(key: "editor.showOthers")

	private var allPrefs: [any PrefProtocol] = []

	init() {
		allPrefs = Mirror(reflecting: self).children.compactMap { $0.value as? any PrefProtocol }

		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(Self.ubiquitousKeyValueStoreDidChange(_:)),
		                                       name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
		                                       object: NSUbiquitousKeyValueStore.default)
		synchronize()
	}

	@objc func ubiquitousKeyValueStoreDidChange(_ notification: NSNotification) {
		let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
		let changes = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
#if DEBUG
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
#endif

		DispatchQueue.main.async {
			for key in changes ?? [] {
				guard let pref = self.allPrefs.first(where: { $0.key == key }) else {
					continue
				}
				pref.didChange()
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
		for pref in allPrefs where pref.ubiquitous {
			if let obj = UserDefaults.standard.object(forKey: pref.key) {
				NSUbiquitousKeyValueStore.default.set(obj, forKey: pref.key)
			}
		}
	}

	func mostRecentPrefFor(geom: GEOMETRY) -> Pref<[String]> {
		switch geom {
		case .AREA: return mostRecentTypes_area
		case .VERTEX: return mostRecentTypes_vertex
		case .LINE: return mostRecentTypes_line
		case .POINT: return mostRecentTypes_point
		}
	}
}
