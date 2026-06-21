//
//  EditorFilters.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/24/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

final class EditorFilters {
	let onChange = NotificationService<Void>()

	var enableObjectFilters = false { // turn all filters on/on
		didSet {
			UserPrefs.shared.editor_enableObjectFilters.value = enableObjectFilters
			onChange.notify()
		}
	}

	let prefs = UserPrefs.shared
	var showLevel = true { didSet { save(prefs.editor_showLevel, showLevel) }}
	var showPoints = true { didSet { save(prefs.editor_showPoints, showPoints) }}
	var showTrafficRoads = true { didSet { save(prefs.editor_showTrafficRoads, showTrafficRoads) }}
	var showServiceRoads = true { didSet { save(prefs.editor_showServiceRoads, showServiceRoads) }}
	var showPaths = true { didSet { save(prefs.editor_showPaths, showPaths) }}
	var showBuildings = true { didSet { save(prefs.editor_showBuildings, showBuildings) }}
	var showLanduse = true { didSet { save(prefs.editor_showLanduse, showLanduse) }}
	var showBoundaries = true { didSet { save(prefs.editor_showBoundaries, showBoundaries) }}
	var showWater = true { didSet { save(prefs.editor_showWater, showWater) }}
	var showRail = true { didSet { save(prefs.editor_showRail, showRail) }}
	var showPower = true { didSet { save(prefs.editor_showPower, showPower) }}
	var showPastFuture = true { didSet { save(prefs.editor_showPastFuture, showPastFuture) }}
	var showOthers = true { didSet { save(prefs.editor_showOthers, showOthers) }}

	var showLevelRange = "" { // range of levels for building level
		didSet {
			UserPrefs.shared.editor_showLevelRange.value = self.showLevelRange
			onChange.notify()
		}
	}

	func save(_ pref: Pref<Bool>, _ value: Bool) {
		pref.value = value
		onChange.notify()
	}

	init() {
		let prefs = UserPrefs.shared
		enableObjectFilters = prefs.editor_enableObjectFilters.value ?? false
		showLevel = prefs.editor_showLevel.value ?? true
		showLevelRange = prefs.editor_showLevelRange.value ?? ""
		showPoints = prefs.editor_showPoints.value ?? true
		showTrafficRoads = prefs.editor_showTrafficRoads.value ?? true
		showServiceRoads = prefs.editor_showServiceRoads.value ?? true
		showPaths = prefs.editor_showPaths.value ?? true
		showBuildings = prefs.editor_showBuildings.value ?? true
		showLanduse = prefs.editor_showLanduse.value ?? true
		showBoundaries = prefs.editor_showBoundaries.value ?? true
		showWater = prefs.editor_showWater.value ?? true
		showRail = prefs.editor_showRail.value ?? true
		showPower = prefs.editor_showPower.value ?? true
		showPastFuture = prefs.editor_showPastFuture.value ?? true
		showOthers = prefs.editor_showOthers.value ?? true
	}

	private let traffic_roads: Set<String> = [
		"motorway",
		"motorway_link",
		"trunk",
		"trunk_link",
		"primary",
		"primary_link",
		"secondary",
		"secondary_link",
		"tertiary",
		"tertiary_link",
		"residential",
		"unclassified",
		"living_street"
	]
	private let service_roads: Set<String> = [
		"service",
		"road",
		"track"
	]
	private let paths: Set<String> = [
		"path",
		"footway",
		"cycleway",
		"bridleway",
		"steps",
		"pedestrian",
		"corridor"
	]
	private let past_futures: Set<String> = [
		"proposed", "planned",
		"construction",
		"disused",
		"abandoned", "was",
		"dismantled", "razed", "demolished", "destroyed", "removed", "obliterated",
		"intermittent"
	]
	// Keys whose values may legitimately match past_futures without indicating lifecycle status
	private let past_futures_whitelist: [String: String] = [
		"craft": "construction",
		"company": "construction"
	]
	private let parking_buildings: Set<String> = [
		"multi-storey",
		"sheds",
		"carports",
		"garage_boxes"
	]
	private let natural_water: Set<String> = [
		"water",
		"coastline",
		"bay"
	]
	private let landuse_water: Set<String> = [
		"pond",
		"basin",
		"reservoir",
		"salt_pond"
	]
	private let landuse_amenity: Set<String> = [
		"bicycle_parking",
		"college",
		"grave_yard",
		"hospital",
		"marketplace",
		"motorcycle_parking",
		"parking",
		"place_of_worship",
		"prison",
		"school",
		"university"
	]

	func predicateForFilters() -> ((OsmBaseObject) -> Bool) {

		// set level predicate dynamically since it depends on the the text range
		var predLevel: ((OsmBaseObject) -> Bool)?
		if showLevel,
		   let levelFilter = FilterObjectsViewController.levels(for: showLevelRange),
		   levelFilter.count != 0
		{
			predLevel = levelPredFilter

			func levelPredFilter(_ object: OsmBaseObject) -> Bool {
				guard let objectLevel = object.tags["level"] else {
					return true
				}
				var floorSet: [String]?
				var floor = 0.0
				if objectLevel.contains(";") {
					floorSet = objectLevel.components(separatedBy: ";")
				} else {
					floor = Double(objectLevel) ?? 0.0
				}
				for filterRange in levelFilter {
					if filterRange.count == 1 {
						// filter is a single floor
						let filterValue = filterRange[0]
						if let floorSet = floorSet {
							// object spans multiple floors
							for s in floorSet {
								let f = Double(s) ?? 0.0
								if f == filterValue {
									return true
								}
							}
						} else {
							if floor == filterValue {
								return true
							}
						}
					} else if filterRange.count == 2 {
						// filter is a range
						let filterLow = filterRange[0]
						let filterHigh = filterRange[1]
						if let floorSet = floorSet {
							// object spans multiple floors
							for s in floorSet {
								let f = Double(s) ?? 0.0
								if f >= filterLow, f <= filterHigh {
									return true
								}
							}
						} else {
							// object is a single value
							if floor >= filterLow, floor <= filterHigh {
								return true
							}
						}
					} else {
						assertionFailure()
					}
				}
				return false
			}
		}
		func predPoints(_ object: OsmBaseObject) -> Bool {
			if let node = object as? OsmNode {
				return node.wayCount == 0
			}
			return false
		}
		func predTrafficRoads(_ object: OsmBaseObject) -> Bool {
			if let tag = object.tags["highway"] {
				return object.isWay() != nil && traffic_roads.contains(tag)
			}
			return false
		}
		func predServiceRoads(_ object: OsmBaseObject) -> Bool {
			if let tag = object.tags["highway"] {
				return object.isWay() != nil && service_roads.contains(tag)
			}
			return false
		}
		func predPaths(_ object: OsmBaseObject) -> Bool {
			if let tag = object.tags["highway"] {
				return object.isWay() != nil && paths.contains(tag)
			}
			return false
		}
		func predBuildings(_ object: OsmBaseObject) -> Bool {
			if let v = object.tags["building"], v != "no" {
				return true
			}
			if let v = object.tags["parking"], parking_buildings.contains(v) {
				return true
			}
			return object.tags["building:part"] != nil ||
				object.tags["amenity"] == "shelter"
		}
		func predWater(_ object: OsmBaseObject) -> Bool {
			if let natural = object.tags["natural"], natural_water.contains(natural) {
				return true
			}
			if let landuse = object.tags["landuse"], landuse_water.contains(landuse) {
				return true
			}
			return object.tags["waterway"] != nil
		}
		func predLanduse(_ object: OsmBaseObject) -> Bool {
			if object.geometry() != .AREA {
				return false
			}
			let hasLanduseTag =
				(object.tags["amenity"].map { landuse_amenity.contains($0) } ?? false) ||
				object.tags["landuse"] != nil ||
				object.tags["leisure"] != nil ||
				object.tags["natural"] != nil
			return hasLanduseTag &&
				!predBuildings(object) &&
				object.tags["building:part"] == nil &&
				object.tags["indoor"] == nil &&
				object.tags["piste:type"] == nil &&
				!predWater(object)
		}
		func predBoundaries(_ object: OsmBaseObject) -> Bool {
			let hasBoundaryTag =
				((object is OsmWay) && object.tags["boundary"] != nil) ||
				(object is OsmRelation && object.tags["type"] == "boundary")
			guard hasBoundaryTag else { return false }
			if let highway = object.tags["highway"],
			   traffic_roads.contains(highway) ||
			   service_roads.contains(highway) ||
			   paths.contains(highway)
			{
				return false
			}
			return object.tags["waterway"] == nil &&
				object.tags["railway"] == nil &&
				object.tags["landuse"] == nil &&
				object.tags["natural"] == nil &&
				object.tags["building"] == nil &&
				object.tags["power"] == nil
		}
		func predRail(_ object: OsmBaseObject) -> Bool {
			if object.tags["railway"] != nil || object.tags["landuse"] == "railway" {
				guard let highway = object.tags["highway"] else { return true }
				return !(traffic_roads.contains(highway) ||
					service_roads.contains(highway) ||
					paths.contains(highway))
			}
			return false
		}
		func predPower(_ object: OsmBaseObject) -> Bool {
			object.tags["power"] != nil
		}
		func predPastFuture(_ object: OsmBaseObject) -> Bool {
			// contains a past/future tag, but not in active use as a road/path/cycleway/etc..
			if let highway = object.tags["highway"],
			   traffic_roads.contains(highway) ||
			   service_roads.contains(highway) ||
			   paths.contains(highway)
			{
				return false
			}
			for (key, value) in object.tags {
				// legacy tagging, e.g. highway=construction
				if past_futures.contains(value),
				   past_futures_whitelist[key] != value
				{
					return true
				}
				let parts = key.split(separator: ":")
				if parts.count > 1,
				   past_futures.contains(String(parts[0]))
				{
					// lifecycle tagging, e.g. demolished:building=yes
					return true
				}
			}
			return false
		}

		let predicate: ((OsmBaseObject) -> Bool) = { [self] object in
			// always show new/modified objects
			if object.isModified() {
				return true
			}
			if let predLevel = predLevel,
			   !predLevel(object)
			{
				return false
			}
			var matchAny = false
			func MATCH(_ matchAny: inout Bool,
			           _ showOthers: Bool,
			           _ pred: (OsmBaseObject) -> Bool,
			           _ show: Bool) -> Bool
			{
				if show || showOthers {
					let match = pred(object)
					if match && show {
						return true
					}
					matchAny = matchAny || match
				}
				return false
			}
			if MATCH(&matchAny, showOthers, predPoints, showPoints) ||
				MATCH(&matchAny, showOthers, predTrafficRoads, showTrafficRoads) ||
				MATCH(&matchAny, showOthers, predServiceRoads, showServiceRoads) ||
				MATCH(&matchAny, showOthers, predPaths, showPaths) ||
				MATCH(&matchAny, showOthers, predPastFuture, showPastFuture) ||
				MATCH(&matchAny, showOthers, predBuildings, showBuildings) ||
				MATCH(&matchAny, showOthers, predLanduse, showLanduse) ||
				MATCH(&matchAny, showOthers, predBoundaries, showBoundaries) ||
				MATCH(&matchAny, showOthers, predWater, showWater) ||
				MATCH(&matchAny, showOthers, predRail, showRail) ||
				MATCH(&matchAny, showOthers, predPower, showPower)
			{
				return true
			}

			if self.showOthers, !matchAny {
				if object.isWay() != nil,
				   object.parentRelations.count == 1,
				   object.parentRelations[0].isMultipolygon()
				{
					return false // follow parent filter instead
				}
				return true
			}
			return false
		}
		return predicate
	}
}
