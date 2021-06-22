//
//  EditorFilters.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/24/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation

final class EditorFilters {
	var onChange: (() -> Void)?

	var enableObjectFilters = false { // turn all filters on/on
		didSet {
			UserDefaults.standard.set(enableObjectFilters, forKey: "editor.enableObjectFilters")
			onChange?()
		}
	}

	var showLevel = false { didSet { save("Level", showLevel) }}
	var showPoints = false { didSet { save("Points", showPoints) }}
	var showTrafficRoads = false { didSet { save("TrafficRoads", showTrafficRoads) }}
	var showServiceRoads = false { didSet { save("ServiceRoads", showServiceRoads) }}
	var showPaths = false { didSet { save("Paths", showPaths) }}
	var showBuildings = false { didSet { save("Buildings", showBuildings) }}
	var showLanduse = false { didSet { save("Landuse", showLanduse) }}
	var showBoundaries = false { didSet { save("Boundaries", showBoundaries) }}
	var showWater = false { didSet { save("Water", showWater) }}
	var showRail = false { didSet { save("Rail", showRail) }}
	var showPower = false { didSet { save("Power", showPower) }}
	var showPastFuture = false { didSet { save("PastFuture", showPastFuture) }}
	var showOthers = false { didSet { save("Others", showOthers) }}

	var showLevelRange: String = "" { // range of levels for building level
		didSet {
			UserDefaults.standard.set(self.showLevelRange, forKey: "editor.showLevelRange")
			onChange?()
		}
	}

	func save(_ name: String, _ value: Bool) {
		UserDefaults.standard.setValue(value, forKey: "editor.show\(name)")
		onChange?()
	}

	init() {
		let defaults = UserDefaults.standard
		defaults.register(defaults: [
			"editor.enableObjectFilters": NSNumber(value: false),
			"editor.showLevel": NSNumber(value: false),
			"editor.showLevelRange": "",
			"editor.showPoints": NSNumber(value: true),
			"editor.showTrafficRoads": NSNumber(value: true),
			"editor.showServiceRoads": NSNumber(value: true),
			"editor.showPaths": NSNumber(value: true),
			"editor.showBuildings": NSNumber(value: true),
			"editor.showLanduse": NSNumber(value: true),
			"editor.showBoundaries": NSNumber(value: true),
			"editor.showWater": NSNumber(value: true),
			"editor.showRail": NSNumber(value: true),
			"editor.showPower": NSNumber(value: true),
			"editor.showPastFuture": NSNumber(value: true),
			"editor.showOthers": NSNumber(value: true)
		])

		enableObjectFilters = defaults.bool(forKey: "editor.enableObjectFilters")
		showLevel = defaults.bool(forKey: "editor.showLevel")
		showLevelRange = defaults.object(forKey: "editor.showLevelRange") as? String ?? ""
		showPoints = defaults.bool(forKey: "editor.showPoints")
		showTrafficRoads = defaults.bool(forKey: "editor.showTrafficRoads")
		showServiceRoads = defaults.bool(forKey: "editor.showServiceRoads")
		showPaths = defaults.bool(forKey: "editor.showPaths")
		showBuildings = defaults.bool(forKey: "editor.showBuildings")
		showLanduse = defaults.bool(forKey: "editor.showLanduse")
		showBoundaries = defaults.bool(forKey: "editor.showBoundaries")
		showWater = defaults.bool(forKey: "editor.showWater")
		showRail = defaults.bool(forKey: "editor.showRail")
		showPower = defaults.bool(forKey: "editor.showPower")
		showPastFuture = defaults.bool(forKey: "editor.showPastFuture")
		showOthers = defaults.bool(forKey: "editor.showOthers")
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
		"proposed",
		"construction",
		"abandoned",
		"dismantled",
		"disused",
		"razed",
		"demolished",
		"obliterated"
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
	func predicateForFilters() -> ((OsmBaseObject) -> Bool) {
		var predLevel: ((OsmBaseObject) -> Bool)?

		if showLevel {
			// set level predicate dynamically since it depends on the the text range
			let levelFilter = FilterObjectsViewController.levels(for: showLevelRange)
			if levelFilter.count != 0 {
				predLevel = { object in
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
							assert(false)
						}
					}
					return false
				}
			}
		}
		let predPoints: ((OsmBaseObject) -> Bool) = { object in
			if let node = object as? OsmNode {
				return node.wayCount == 0
			}
			return false
		}
		let predTrafficRoads: ((OsmBaseObject) -> Bool) = { object in
			if let tag = object.tags["highway"] {
				return object.isWay() != nil && self.traffic_roads.contains(tag)
			}
			return false
		}
		let predServiceRoads: ((OsmBaseObject) -> Bool) = { object in
			if let tag = object.tags["highway"] {
				return object.isWay() != nil && self.service_roads.contains(tag)
			}
			return false
		}
		let predPaths: ((OsmBaseObject) -> Bool) = { object in
			if let tags = object.tags["highway"] {
				return object.isWay() != nil && self.paths.contains(tags)
			}
			return false
		}
		let predBuildings: ((OsmBaseObject) -> Bool) = { object in
			if let v = object.tags["building"], v != "no" {
				return true
			}
			if let v = object.tags["parking"], self.parking_buildings.contains(v) {
				return true
			}
			return object.tags["building:part"] != nil ||
				object.tags["amenity"] == "shelter"
		}
		let predWater: ((OsmBaseObject) -> Bool) = { object in
			if let natural = object.tags["natural"],
			   self.natural_water.contains(natural)
			{
				return true
			}
			if let landuse = object.tags["landuse"],
			   self.landuse_water.contains(landuse)
			{
				return true
			}
			return object.tags["waterway"] != nil
		}
		let predLanduse: ((OsmBaseObject) -> Bool) = { object in
			((object.isWay()?.isArea() ?? false) ||
				(object.isRelation()?.isMultipolygon() ?? false))
				&& !predBuildings(object) && !predWater(object)
		}
		let predBoundaries: ((OsmBaseObject) -> Bool) = { object in
			if object.tags["boundary"] != nil {
				guard let highway = object.tags["highway"] else { return true }
				return !(self.traffic_roads.contains(highway) ||
					self.service_roads.contains(highway) ||
					self.paths.contains(highway))
			}
			return false
		}
		let predRail: ((OsmBaseObject) -> Bool) = { object in
			if object.tags["railway"] != nil || (object.tags["landuse"] == "railway") {
				guard let highway = object.tags["highway"] else { return true }
				return !(self.traffic_roads.contains(highway) ||
					self.service_roads.contains(highway) ||
					self.paths.contains(highway))
			}
			return false
		}
		let predPower: ((OsmBaseObject) -> Bool) = { object in
			object.tags["power"] != nil
		}
		let predPastFuture: ((OsmBaseObject) -> Bool) = { object in
			// contains a past/future tag, but not in active use as a road/path/cycleway/etc..
			if let highway = object.tags["highway"],
			   self.traffic_roads.contains(highway) ||
			   self.service_roads.contains(highway) ||
			   self.paths.contains(highway)
			{
				return false
			}
			for (key, value) in object.tags {
				if self.past_futures.contains(key) || self.past_futures.contains(value) {
					return true
				}
			}
			return false
		}

		let predicate: ((OsmBaseObject) -> Bool) = { [self] object in
			if let predLevel = predLevel,
			   !predLevel(object)
			{
				return false
			}
			var matchAny = false
			func MATCH(_ matchAny: inout Bool, _ showOthers: Bool, _ pred: (OsmBaseObject) -> Bool,
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
				MATCH(&matchAny, showOthers, predPower, showPower) ||
				MATCH(&matchAny, showOthers, predWater, showWater)
			{
				return true
			}

			if self.showOthers, !matchAny {
				if object.isWay() != nil, object.parentRelations.count == 1,
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
