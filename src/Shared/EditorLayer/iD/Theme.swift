// Copyright (c) 2017, iD Contributors
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted, provided that the above
// copyright notice and this permission notice appear in all copies.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
// REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
// INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
// LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
// OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
// PERFORMANCE OF THIS SOFTWARE.

//
//  Theme.swift
//  Go Map!!
//
//  Created by Boris Verkhovskiy on 2024-03-30.
//

import Foundation
import UIKit
import Collections

extension RenderInfo {
	static func match(primary: String?, status: String?, classes: [String]) -> RenderInfo {
		let r = RenderInfo()
		if classes.contains("barrier-hedge") || classes.contains("landuse-flowerbed") || classes.contains("landuse-forest") || classes.contains("landuse-grass") || classes.contains("landuse-recreation_ground") || classes.contains("landuse-village_green") || classes.contains("leisure-garden") || classes.contains("leisure-golf_course") || classes.contains("leisure-nature_reserve") || classes.contains("leisure-park") || classes.contains("leisure-pitch") || classes.contains("leisure-track") || primary == "natural" || classes.contains("natural-wood") || classes.contains("golf-tee") || classes.contains("golf-fairway") || classes.contains("golf-rough") || classes.contains("golf-green") {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if classes.contains("amenity-fountain") || classes.contains("leisure-swimming_pool") || classes.contains("natural-bay") || classes.contains("natural-strait") || classes.contains("natural-water") {
			r.lineColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if classes.contains("leisure-track") || classes.contains("natural-beach") || classes.contains("natural-sand") || classes.contains("natural-scrub") || classes.contains("amenity-childcare") || classes.contains("amenity-kindergarten") || classes.contains("amenity-school") || classes.contains("amenity-college") || classes.contains("amenity-university") || classes.contains("amenity-research_institute") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if classes.contains("landuse-residential") || status == "construction" {
			r.lineColor = UIColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 1.0)
			r.areaColor = UIColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 0.3)
		}
		if classes.contains("landuse-retail") || classes.contains("landuse-commercial") || classes.contains("landuse-landfill") || primary == "military" || classes.contains("landuse-military") {
			r.lineColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
			r.areaColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if classes.contains("landuse-industrial") || classes.contains("power-plant") {
			r.lineColor = UIColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 1.0)
			r.areaColor = UIColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 0.3)
		}
		if classes.contains("natural-wetland") {
			r.lineColor = UIColor(red: 0.6, green: 0.882, blue: 0.667, alpha: 1.0)
			r.areaColor = UIColor(red: 0.6, green: 0.882, blue: 0.667, alpha: 0.3)
		}
		if classes.contains("landuse-cemetery") || classes.contains("landuse-farmland") || classes.contains("landuse-meadow") || classes.contains("landuse-orchard") || classes.contains("landuse-vineyard") {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if classes.contains("landuse-farmyard") || classes.contains("leisure-horse_riding") {
			r.lineColor = UIColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 1.0)
			r.areaColor = UIColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 0.3)
		}
		if classes.contains("amenity-parking") || classes.contains("landuse-railway") || classes.contains("landuse-quarry") || classes.contains("man_made-adit") || classes.contains("man_made-groyne") || classes.contains("man_made-breakwater") || classes.contains("natural-bare_rock") || classes.contains("natural-cave_entrance") || classes.contains("natural-cliff") || classes.contains("natural-rock") || classes.contains("natural-scree") || classes.contains("natural-stone") || classes.contains("natural-shingle") || classes.contains("waterway-dam") || classes.contains("waterway-weir") {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if classes.contains("amenity-parking") || classes.contains("landuse-railway") || classes.contains("landuse-quarry") || classes.contains("man_made-adit") || classes.contains("man_made-groyne") || classes.contains("man_made-breakwater") || classes.contains("natural-bare_rock") || classes.contains("natural-cliff") || classes.contains("natural-cave_entrance") || classes.contains("natural-rock") || classes.contains("natural-scree") || classes.contains("natural-stone") || classes.contains("natural-shingle") || classes.contains("waterway-dam") || classes.contains("waterway-weir") {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if classes.contains("natural-cave_entrance") || classes.contains("natural-glacier") {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if primary == "highway" {
			r.lineColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.lineWidth = 8.0
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
			r.casingWidth = 10.0
		}
		if classes.contains("highway-motorway") || classes.contains("highway-motorway_link") || classes.contains("motorway") {
			r.lineColor = UIColor(red: 0.812, green: 0.125, blue: 0.506, alpha: 1.0)
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if classes.contains("highway-trunk") || classes.contains("highway-trunk_link") || classes.contains("trunk") {
			r.lineColor = UIColor(red: 0.867, green: 0.184, blue: 0.133, alpha: 1.0)
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if classes.contains("highway-primary") || classes.contains("highway-primary_link") || classes.contains("primary") {
			r.lineColor = UIColor(red: 0.976, green: 0.596, blue: 0.024, alpha: 1.0)
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if classes.contains("highway-secondary") || classes.contains("highway-secondary_link") || classes.contains("secondary") {
			r.lineColor = UIColor(red: 0.953, green: 0.953, blue: 0.071, alpha: 1.0)
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if classes.contains("highway-tertiary") || classes.contains("highway-tertiary_link") || classes.contains("tertiary") {
			r.lineColor = UIColor(red: 1.0, green: 0.976, blue: 0.702, alpha: 1.0)
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if classes.contains("highway-residential") || classes.contains("residential") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if classes.contains("highway-unclassified") || classes.contains("unclassified") {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if classes.contains("highway-living_street") || classes.contains("highway-bus_guideway") || classes.contains("highway-service") || classes.contains("highway-track") || classes.contains("highway-road") {
			r.lineWidth = 5.0
			r.casingWidth = 7.0
		}
		if classes.contains("highway-path") || classes.contains("highway-footway") || classes.contains("highway-cycleway") || classes.contains("highway-bridleway") || classes.contains("highway-corridor") || classes.contains("highway-steps") {
			r.lineWidth = 3.0
			r.casingWidth = 5.0
		}
		if classes.contains("highway-living_street") || classes.contains("living_street") {
			r.lineColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		}
		if classes.contains("highway-corridor") || classes.contains("corridor") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineDashPattern = [2, 8]
			r.casingColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if classes.contains("highway-pedestrian") || classes.contains("pedestrian") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 3.5
			r.lineCap = .butt
			r.lineDashPattern = [8, 8]
			r.casingColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if classes.contains("highway-road") || classes.contains("road") {
			r.lineColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if classes.contains("highway-service") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if classes.contains("highway-bus_guideway") || classes.contains("service") {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if classes.contains("highway-track") || classes.contains("track") {
			r.lineColor = UIColor(red: 0.773, green: 0.71, blue: 0.624, alpha: 1.0)
			r.casingColor = UIColor(red: 0.455, green: 0.435, blue: 0.435, alpha: 1.0)
		}
		if classes.contains("highway-path") || classes.contains("highway-footway") || classes.contains("highway-cycleway") || classes.contains("highway-bridleway") {
			r.lineCap = .butt
			r.lineDashPattern = [6, 6]
		}
		if classes.contains("crossing") || classes.contains("footway-access_aisle") || classes.contains("public_transport-platform") || classes.contains("highway-platform") || classes.contains("railway-platform") || classes.contains("railway-platform_edge") || classes.contains("man_made-pier") {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if classes.contains("highway-path") {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if classes.contains("highway-footway") || classes.contains("highway-cycleway") || classes.contains("highway-bridleway") {
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if classes.contains("highway-path") || classes.contains("highway-footway") || classes.contains("highway-bus_stop") {
			r.lineColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
		}
		if classes.contains("highway-cycleway") {
			r.lineColor = UIColor(red: 0.345, green: 0.663, blue: 0.929, alpha: 1.0)
		}
		if classes.contains("highway-bridleway") {
			r.lineColor = UIColor(red: 0.878, green: 0.427, blue: 0.373, alpha: 1.0)
		}
		if classes.contains("leisure-track") {
			r.lineColor = UIColor(red: 0.898, green: 0.722, blue: 0.169, alpha: 1.0)
		}
		if classes.contains("highway-steps") {
			r.lineColor = UIColor(red: 0.506, green: 0.824, blue: 0.361, alpha: 1.0)
			r.lineCap = .butt
			r.lineDashPattern = [3, 3]
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if primary == "aeroway" {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
			r.lineDashPattern = nil
		}
		if classes.contains("aeroway-runway") {
			r.areaColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6)
		}
		if classes.contains("aeroway-taxiway") || classes.contains("taxiway") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
			r.lineWidth = 5.0
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
			r.casingWidth = 7.0
		}
		if classes.contains("aeroway-runway") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [24, 48]
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 10.0
			r.casingCap = .square
		}
		if primary == "railway" {
			r.lineColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0)
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [12, 12]
			r.casingColor = UIColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1.0)
			r.casingWidth = 7.0
		}
		if classes.contains("railway-subway") {
			r.lineColor = UIColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0)
			r.casingColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1.0)
		}
		if classes.contains("waterway-dock") || classes.contains("waterway-boatyard") || classes.contains("waterway-fuel") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if primary == "waterway" {
			r.lineWidth = 5.0
			r.casingWidth = 7.0
		}
		if classes.contains("waterway-river") {
			r.lineWidth = 8.0
			r.casingWidth = 10.0
		}
		if classes.contains("waterway-ditch") {
			r.lineColor = UIColor(red: 0.2, green: 0.6, blue: 0.667, alpha: 1.0)
		}
		if primary == "aerialway" || classes.contains("attraction-summer_toboggan") || classes.contains("attraction-water_slide") || classes.contains("golf-cartpath") || classes.contains("man_made-pipeline") || classes.contains("natural-tree_row") || classes.contains("roller_coaster-track") || classes.contains("roller_coaster-support") || classes.contains("piste") {
			r.lineWidth = 5.0
			r.casingWidth = 7.0
		}
		if classes.contains("route-ferry") {
			r.lineColor = UIColor(red: 0.345, green: 0.663, blue: 0.929, alpha: 1.0)
			r.lineWidth = 3.0
			r.lineCap = .butt
			r.lineDashPattern = [12, 8]
		}
		if primary == "aerialway" {
			r.lineColor = UIColor(red: 0.8, green: 0.333, blue: 0.333, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if classes.contains("piste") {
			r.lineColor = UIColor(red: 0.667, green: 0.6, blue: 0.867, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if classes.contains("attraction-summer_toboggan") {
			r.lineColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if classes.contains("attraction-water_slide") {
			r.lineColor = UIColor(red: 0.667, green: 0.878, blue: 0.796, alpha: 1.0)
			r.casingColor = UIColor(red: 0.239, green: 0.424, blue: 0.443, alpha: 1.0)
		}
		if classes.contains("roller_coaster-track") {
			r.lineColor = UIColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0)
			r.lineWidth = 3.0
			r.lineCap = .butt
			r.lineDashPattern = [5, 1]
			r.casingColor = UIColor(red: 0.439, green: 0.439, blue: 0.439, alpha: 1.0)
		}
		if classes.contains("roller_coaster-support") {
			r.lineColor = UIColor(red: 0.439, green: 0.439, blue: 0.439, alpha: 1.0)
		}
		if classes.contains("golf-cartpath") {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if primary == "power" {
			r.lineColor = UIColor(red: 0.576, green: 0.576, blue: 0.576, alpha: 1.0)
			r.lineWidth = 2.0
		}
		if classes.contains("man_made-pipeline") {
			r.lineColor = UIColor(red: 0.796, green: 0.816, blue: 0.847, alpha: 1.0)
			r.lineCap = .butt
			r.lineDashPattern = [80, 1.25]
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if primary == "boundary" {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [20, 5, 5, 5]
			r.casingColor = UIColor(red: 0.51, green: 0.71, blue: 0.996, alpha: 1.0)
			r.casingWidth = 6.0
		}
		if classes.contains("boundary-protected_area") || classes.contains("boundary-national_park") {
			r.casingColor = UIColor(red: 0.69, green: 0.886, blue: 0.596, alpha: 1.0)
		}
		if classes.contains("man_made-groyne") || classes.contains("man_made-breakwater") {
			r.lineWidth = 3.0
			r.lineCap = .round
			r.lineDashPattern = [15, 5, 1, 5]
		}
		if classes.contains("bridge") {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 16.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if classes.contains("tunnel") || classes.contains("location-underground") {
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if classes.contains("location-underwater") {
			r.lineCap = .butt
			r.lineDashPattern = nil
		}
		if classes.contains("embankment") || classes.contains("cutting") {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 22.0
			r.casingCap = .butt
			r.casingDashPattern = [2, 4]
		}
		if classes.contains("unpaved") {
			r.casingColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.casingCap = .butt
			r.casingDashPattern = [4, 4]
		}
		if classes.contains("semipaved") {
			r.casingCap = .butt
			r.casingDashPattern = [6, 2]
		}
		if primary == "building" {
			r.lineColor = UIColor(red: 0.878, green: 0.431, blue: 0.373, alpha: 1.0)
			r.areaColor = UIColor(red: 0.878, green: 0.431, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-beachvolleyball")) || (classes.contains("leisure-pitch") && classes.contains("sport-baseball")) || (classes.contains("leisure-pitch") && classes.contains("sport-softball")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if classes.contains("landuse-grass") && classes.contains("golf-green") {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-basketball")) || (classes.contains("leisure-pitch") && classes.contains("sport-skateboard")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if classes.contains("highway-service") && classes.contains("service-driveway") {
			r.lineWidth = 4.25
			r.casingWidth = 6.25
		}
		if classes.contains("highway-service") && classes.contains("service") {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if classes.contains("highway-service") && classes.contains("service-parking_aisle") {
			r.lineColor = UIColor(red: 0.8, green: 0.792, blue: 0.78, alpha: 1.0)
		}
		if classes.contains("highway-service") && classes.contains("service-driveway") {
			r.lineColor = UIColor(red: 1.0, green: 0.965, blue: 0.894, alpha: 1.0)
		}
		if classes.contains("highway-service") && classes.contains("service-emergency_access") {
			r.lineColor = UIColor(red: 0.867, green: 0.698, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-footway") && classes.contains("public_transport-platform")) || (classes.contains("highway-footway") && classes.contains("man_made-pier")) || (primary == "highway" && classes.contains("crossing")) || (primary == "highway" && classes.contains("footway-access_aisle")) {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if classes.contains("highway-path") && classes.contains("bridge-boardwalk") {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if classes.contains("highway-footway") && classes.contains("footway-sidewalk") {
			r.lineColor = UIColor(red: 0.831, green: 0.706, blue: 0.706, alpha: 1.0)
		}
		if primary == "highway" && classes.contains("crossing-unmarked") {
			r.lineDashPattern = [6, 4]
		}
		if primary == "highway" && classes.contains("crossing-marked") {
			r.lineDashPattern = [6, 3]
		}
		if classes.contains("highway-footway") && classes.contains("crossing-marked") {
			r.lineColor = UIColor(red: 0.298, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if classes.contains("highway-footway") && classes.contains("crossing-unmarked") {
			r.lineColor = UIColor(red: 0.467, green: 0.416, blue: 0.416, alpha: 1.0)
		}
		if classes.contains("highway-cycleway") && classes.contains("crossing-marked") {
			r.lineColor = UIColor(red: 0.267, green: 0.376, blue: 0.467, alpha: 1.0)
		}
		if primary == "highway" && classes.contains("footway-access_aisle") {
			r.lineColor = UIColor(red: 0.298, green: 0.267, blue: 0.267, alpha: 1.0)
			r.lineDashPattern = [4, 2]
		}
		if (primary == "railway" && classes.contains("railway-platform_edge")) || (primary == "railway" && classes.contains("railway-platform")) {
			r.lineDashPattern = nil
			r.casingWidth = 0.0
		}
		if primary == "railway" && status != nil {
			r.casingColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
		}
		if primary == "railway" && status == "disused" {
			r.casingColor = UIColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1.0)
		}
		if primary == "waterway" && !classes.contains("waterway-dam") {
			r.lineColor = UIColor(red: 0.467, green: 0.867, blue: 0.867, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if classes.contains("barrier") && primary != "waterway" {
			r.lineWidth = 3.0
			r.lineCap = .round
			r.lineDashPattern = [15, 5, 1, 5]
		}
		if (classes.contains("barrier") && classes.contains("barrier-wall")) || (classes.contains("barrier") && classes.contains("barrier-retaining_wall")) || (classes.contains("barrier") && classes.contains("barrier-city_wall")) {
			r.lineCap = .butt
			r.lineDashPattern = [16, 3, 9, 3]
		}
		if (primary == "railway" && classes.contains("bridge")) || (classes.contains("highway-living_street") && classes.contains("bridge")) || (classes.contains("highway-path") && classes.contains("bridge")) || (classes.contains("highway-corridor") && classes.contains("bridge")) || (classes.contains("highway-pedestrian") && classes.contains("bridge")) || (classes.contains("highway-service") && classes.contains("bridge")) || (classes.contains("highway-track") && classes.contains("bridge")) || (classes.contains("highway-steps") && classes.contains("bridge")) || (classes.contains("highway-footway") && classes.contains("bridge")) || (classes.contains("highway-cycleway") && classes.contains("bridge")) || (classes.contains("highway-bridleway") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("bridge") && classes.contains("unpaved")) || (classes.contains("bridge") && classes.contains("semipaved")) {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
		}
		if status != nil && status != "disused" {
			r.lineCap = .butt
			r.lineDashPattern = [7, 3]
			r.casingCap = .butt
			r.casingDashPattern = [7, 3]
		}
		if primary == "railway" && status != nil && !classes.contains("service") {
			r.lineColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0)
		}
		if classes.contains("barrier") && !classes.contains("barrier-hedge") && primary != "waterway" {
			r.lineColor = UIColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0)
		}
		if primary == "highway" && status != nil && status == "construction" {
			r.lineColor = UIColor(red: 0.988, green: 0.424, blue: 0.078, alpha: 1.0)
			r.lineWidth = 8.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingWidth = 10.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-path")) || (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-footway")) || (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-cycleway")) || (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-bridleway")) || (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-steps")) {
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-path")) || (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-footway")) || (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-cycleway")) || (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-bridleway")) || (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-steps")) {
			r.lineWidth = 3.0
			r.casingWidth = 4.5
		}
		if (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-path")) || (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-footway")) || (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-cycleway")) || (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-bridleway")) || (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-steps")) {
			r.casingWidth = 10.0
		}

		return r
	}
}
