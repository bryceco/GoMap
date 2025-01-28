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

extension RenderInfo {
	static func has(_ tags: [String: String], _ key: String) -> Bool {
		let value = tags[key]
		return value != nil && value != "no"
	}

	static func match(primary: String?, primaryValue: String?, status: String?, surface: String?,
	                  tags: [String: String]) -> RenderInfo
	{
		let r = RenderInfo(key: primary ?? "", value: primaryValue)
		if (tags["barrier"] == "hedge") || (primary == "landuse" && primaryValue == "flowerbed") ||
			(primary == "landuse" && primaryValue == "forest") || (primary == "landuse" && primaryValue == "grass") ||
			(primary == "landuse" && primaryValue == "recreation_ground") ||
			(primary == "landuse" && primaryValue == "village_green") ||
			((primary == "leisure" && primaryValue == "garden") || tags["leisure"] == "garden") ||
			((primary == "leisure" && primaryValue == "golf_course") || tags["leisure"] == "golf_course") ||
			((primary == "leisure" && primaryValue == "nature_reserve") || tags["leisure"] == "nature_reserve") ||
			((primary == "leisure" && primaryValue == "park") || tags["leisure"] == "park") ||
			((primary == "leisure" && primaryValue == "pitch") || tags["leisure"] == "pitch") ||
			((primary == "leisure" && primaryValue == "track") || tags["leisure"] == "track") ||
			(primary == "natural") ||
			(primary == "natural" && primaryValue == "wood") || (tags["golf"] == "tee") ||
			(tags["golf"] == "fairway") ||
			(tags["golf"] == "rough") || (tags["golf"] == "green")
		{
			r.lineColor = DynamicColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (primary == "amenity" && primaryValue == "fountain") ||
			((primary == "leisure" && primaryValue == "swimming_pool") || tags["leisure"] == "swimming_pool") ||
			(primary == "natural" && primaryValue == "bay") || (primary == "natural" && primaryValue == "strait") ||
			(primary == "natural" && primaryValue == "water")
		{
			r.lineColor = DynamicColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if ((primary == "leisure" && primaryValue == "track") || tags["leisure"] == "track") ||
			(primary == "natural" && primaryValue == "beach") || (primary == "natural" && primaryValue == "sand") ||
			(primary == "natural" && primaryValue == "scrub") ||
			(primary == "amenity" && primaryValue == "childcare") ||
			(primary == "amenity" && primaryValue == "kindergarten") ||
			(primary == "amenity" && primaryValue == "school") || (primary == "amenity" && primaryValue == "college") ||
			(primary == "amenity" && primaryValue == "university") ||
			(primary == "amenity" && primaryValue == "research_institute")
		{
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
			r.areaColor = DynamicColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (primary == "landuse" && primaryValue == "residential") || (status == "construction") {
			r.lineColor = DynamicColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 0.3)
		}
		if (primary == "landuse" && primaryValue == "retail") ||
			(primary == "landuse" && primaryValue == "commercial") ||
			(primary == "landuse" && primaryValue == "landfill") || (primary == "military") ||
			(primary == "landuse" && primaryValue == "military")
		{
			r.lineColor = DynamicColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if (primary == "landuse" && primaryValue == "industrial") || (primary == "power" && primaryValue == "plant") {
			r.lineColor = DynamicColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 0.3)
		}
		if primary == "natural" && primaryValue == "wetland" {
			r.lineColor = DynamicColor(red: 0.6, green: 0.882, blue: 0.667, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.6, green: 0.882, blue: 0.667, alpha: 0.3)
		}
		if (primary == "landuse" && primaryValue == "cemetery") ||
			(primary == "landuse" && primaryValue == "farmland") ||
			(primary == "landuse" && primaryValue == "meadow") || (primary == "landuse" && primaryValue == "orchard") ||
			(primary == "landuse" && primaryValue == "vineyard")
		{
			r.lineColor = DynamicColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (primary == "landuse" && primaryValue == "farmyard") ||
			((primary == "leisure" && primaryValue == "horse_riding") || tags["leisure"] == "horse_riding")
		{
			r.lineColor = DynamicColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 0.3)
		}
		if (primary == "amenity" && primaryValue == "parking") || (primary == "landuse" && primaryValue == "railway") ||
			(primary == "landuse" && primaryValue == "quarry") ||
			((primary == "man_made" && primaryValue == "adit") || tags["man_made"] == "adit") ||
			((primary == "man_made" && primaryValue == "groyne") || tags["man_made"] == "groyne") ||
			((primary == "man_made" && primaryValue == "breakwater") || tags["man_made"] == "breakwater") ||
			(primary == "natural" && primaryValue == "bare_rock") ||
			(primary == "natural" && primaryValue == "cave_entrance") ||
			(primary == "natural" && primaryValue == "cliff") || (primary == "natural" && primaryValue == "rock") ||
			(primary == "natural" && primaryValue == "scree") || (primary == "natural" && primaryValue == "stone") ||
			(primary == "natural" && primaryValue == "shingle") || (primary == "waterway" && primaryValue == "dam") ||
			(primary == "waterway" && primaryValue == "weir")
		{
			r.lineColor = DynamicColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (primary == "amenity" && primaryValue == "parking") || (primary == "landuse" && primaryValue == "railway") ||
			(primary == "landuse" && primaryValue == "quarry") ||
			((primary == "man_made" && primaryValue == "adit") || tags["man_made"] == "adit") ||
			((primary == "man_made" && primaryValue == "groyne") || tags["man_made"] == "groyne") ||
			((primary == "man_made" && primaryValue == "breakwater") || tags["man_made"] == "breakwater") ||
			(primary == "natural" && primaryValue == "bare_rock") ||
			(primary == "natural" && primaryValue == "cliff") ||
			(primary == "natural" && primaryValue == "cave_entrance") ||
			(primary == "natural" && primaryValue == "rock") || (primary == "natural" && primaryValue == "scree") ||
			(primary == "natural" && primaryValue == "stone") || (primary == "natural" && primaryValue == "shingle") ||
			(primary == "waterway" && primaryValue == "dam") || (primary == "waterway" && primaryValue == "weir")
		{
			r.areaColor = DynamicColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (primary == "natural" && primaryValue == "cave_entrance") ||
			(primary == "natural" && primaryValue == "glacier")
		{
			r.lineColor = DynamicColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
			r.areaColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if primary == "highway" {
			r.lineColor = DynamicColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.lineWidth = 4.0
			r.casingColor = DynamicColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
			r.casingWidth = 5.0
		}
		if (primary == "highway" && primaryValue == "motorway") ||
			(primary == "highway" && primaryValue == "motorway_link") || has(tags, "motorway")
		{
			r.lineColor = DynamicColor(red: 0.812, green: 0.125, blue: 0.506, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "trunk") ||
			(primary == "highway" && primaryValue == "trunk_link") ||
			has(tags, "trunk")
		{
			r.lineColor = DynamicColor(red: 0.867, green: 0.184, blue: 0.133, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "primary") ||
			(primary == "highway" && primaryValue == "primary_link") || has(tags, "primary")
		{
			r.lineColor = DynamicColor(red: 0.976, green: 0.596, blue: 0.024, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "secondary") ||
			(primary == "highway" && primaryValue == "secondary_link") || has(tags, "secondary")
		{
			r.lineColor = DynamicColor(red: 0.953, green: 0.953, blue: 0.071, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "tertiary") ||
			(primary == "highway" && primaryValue == "tertiary_link") || has(tags, "tertiary")
		{
			r.lineColor = DynamicColor(red: 1.0, green: 0.976, blue: 0.702, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "residential") || has(tags, "residential") {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "unclassified") || has(tags, "unclassified") {
			r.lineColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "living_street") ||
			(primary == "highway" && primaryValue == "bus_guideway") ||
			(primary == "highway" && primaryValue == "service") || (primary == "highway" && primaryValue == "track") ||
			(primary == "highway" && primaryValue == "road")
		{
			r.lineWidth = 2.5
			r.casingWidth = 3.5
		}
		if (primary == "highway" && primaryValue == "path") || (primary == "highway" && primaryValue == "footway") ||
			(primary == "highway" && primaryValue == "cycleway") ||
			(primary == "highway" && primaryValue == "bridleway") ||
			(primary == "highway" && primaryValue == "corridor") ||
			(primary == "highway" && primaryValue == "ladder") ||
			(primary == "highway" && primaryValue == "steps")
		{
			r.lineWidth = 1.5
			r.casingWidth = 2.5
		}
		if (primary == "highway" && primaryValue == "living_street") || has(tags, "living_street") {
			r.lineColor = DynamicColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.casingColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "corridor") || has(tags, "corridor") {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineDashPattern = [1, 4]
			r.casingColor = DynamicColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && primaryValue == "pedestrian") || has(tags, "pedestrian") {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.75
			r.lineCap = .butt
			r.lineDashPattern = [4, 4]
			r.casingColor = DynamicColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && primaryValue == "road") || has(tags, "road") {
			r.lineColor = DynamicColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if primary == "highway" && primaryValue == "service" {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "bus_guideway") || has(tags, "service") {
			r.lineColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "track") || has(tags, "track") {
			r.lineColor = DynamicColor(red: 0.773, green: 0.71, blue: 0.624, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.455, green: 0.435, blue: 0.435, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "path") || (primary == "highway" && primaryValue == "footway") ||
			(primary == "highway" && primaryValue == "cycleway") ||
			(primary == "highway" && primaryValue == "bridleway")
		{
			r.lineCap = .butt
			r.lineDashPattern = [3, 3]
		}
		if has(tags, "crossing") || (tags["footway"] == "access_aisle") || (tags["public_transport"] == "platform") ||
			(primary == "highway" && primaryValue == "platform") ||
			(primary == "railway" && primaryValue == "platform") ||
			(primary == "railway" && primaryValue == "platform_edge") ||
			((primary == "man_made" && primaryValue == "pier") || tags["man_made"] == "pier")
		{
			r.lineColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if primary == "highway" && primaryValue == "path" {
			r.casingColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && primaryValue == "footway") ||
			(primary == "highway" && primaryValue == "cycleway") ||
			(primary == "highway" && primaryValue == "bridleway")
		{
			r.casingColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && primaryValue == "path") || (primary == "highway" && primaryValue == "footway") ||
			(primary == "highway" && primaryValue == "bus_stop")
		{
			r.lineColor = DynamicColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
		}
		if primary == "highway" && primaryValue == "cycleway" {
			r.lineColor = DynamicColor(red: 0.345, green: 0.663, blue: 0.929, alpha: 1.0)
		}
		if primary == "highway" && primaryValue == "bridleway" {
			r.lineColor = DynamicColor(red: 0.878, green: 0.427, blue: 0.373, alpha: 1.0)
		}
		if (primary == "leisure" && primaryValue == "track") || tags["leisure"] == "track" {
			r.lineColor = DynamicColor(red: 0.898, green: 0.722, blue: 0.169, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "steps") || (primary == "highway" && primaryValue == "ladder") {
			r.lineColor = DynamicColor(red: 0.506, green: 0.824, blue: 0.361, alpha: 1.0)
			r.lineCap = .butt
			r.lineDashPattern = [1.5, 1.5]
			r.casingColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if primary == "aeroway" {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 0.5
			r.lineDashPattern = nil
		}
		if primary == "aeroway" && primaryValue == "runway" {
			r.areaColor = DynamicColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6)
		}
		if (primary == "aeroway" && primaryValue == "taxiway") || has(tags, "taxiway") {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
			r.lineWidth = 2.5
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
			r.casingWidth = 3.5
		}
		if primary == "aeroway" && primaryValue == "runway" {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
			r.lineCap = .butt
			r.lineDashPattern = [12, 24]
			r.casingColor = DynamicColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 5.0
			r.casingCap = .square
		}
		if primary == "railway" {
			r.lineColor = DynamicColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0)
			r.lineWidth = 1.0
			r.lineCap = .butt
			r.lineDashPattern = [6, 6]
			r.casingColor = DynamicColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1.0)
			r.casingWidth = 3.5
		}
		if primary == "railway" && primaryValue == "subway" {
			r.lineColor = DynamicColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1.0)
		}
		if (primary == "waterway" && primaryValue == "dock") || (primary == "waterway" && primaryValue == "boatyard") ||
			(primary == "waterway" && primaryValue == "fuel")
		{
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 0.5
			r.areaColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if primary == "waterway" {
			r.lineWidth = 2.5
			r.casingWidth = 3.5
		}
		if (primary == "waterway" && primaryValue == "river") || (primary == "waterway" && primaryValue == "flowline") {
			r.casingWidth = 5.0
		}
		if primary == "waterway" && primaryValue == "river" {
			r.lineWidth = 4.0
		}
		if primary == "waterway" && primaryValue == "flowline" {
			r.lineOpacity = 0.5
			r.lineWidth = 4.0
		}
		if primary == "waterway" && primaryValue == "ditch" {
			r.lineColor = DynamicColor(red: 0.2, green: 0.6, blue: 0.667, alpha: 1.0)
		}
		if (primary == "aerialway") || (primary == "attraction" && primaryValue == "summer_toboggan") ||
			(primary == "attraction" && primaryValue == "water_slide") || (tags["golf"] == "cartpath") ||
			((primary == "man_made" && primaryValue == "pipeline") || tags["man_made"] == "pipeline") ||
			(primary == "natural" && primaryValue == "tree_row") ||
			(primary == "roller_coaster" && primaryValue == "track") ||
			(primary == "roller_coaster" && primaryValue == "support") || (primary == "piste:type")
		{
			r.lineWidth = 2.5
			r.casingWidth = 3.5
		}
		if primary == "route" && primaryValue == "ferry" {
			r.lineColor = DynamicColor(red: 0.345, green: 0.663, blue: 0.929, alpha: 1.0)
			r.lineWidth = 1.5
			r.lineCap = .butt
			r.lineDashPattern = [6, 4]
		}
		if primary == "aerialway" {
			r.lineColor = DynamicColor(red: 0.8, green: 0.333, blue: 0.333, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if primary == "piste:type" {
			r.lineColor = DynamicColor(red: 0.667, green: 0.6, blue: 0.867, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if primary == "attraction" && primaryValue == "summer_toboggan" {
			r.lineColor = DynamicColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if primary == "attraction" && primaryValue == "water_slide" {
			r.lineColor = DynamicColor(red: 0.667, green: 0.878, blue: 0.796, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.239, green: 0.424, blue: 0.443, alpha: 1.0)
		}
		if primary == "roller_coaster" && primaryValue == "track" {
			r.lineColor = DynamicColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0)
			r.lineWidth = 1.5
			r.lineCap = .butt
			r.lineDashPattern = [2.5, 0.5]
			r.casingColor = DynamicColor(red: 0.439, green: 0.439, blue: 0.439, alpha: 1.0)
		}
		if primary == "roller_coaster" && primaryValue == "support" {
			r.lineColor = DynamicColor(red: 0.439, green: 0.439, blue: 0.439, alpha: 1.0)
		}
		if tags["golf"] == "cartpath" {
			r.lineColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if primary == "power" {
			r.lineColor = DynamicColor(red: 0.576, green: 0.576, blue: 0.576, alpha: 1.0)
			r.lineWidth = 1.0
		}
		if (primary == "man_made" && primaryValue == "pipeline") || tags["man_made"] == "pipeline" {
			r.lineColor = DynamicColor(red: 0.796, green: 0.816, blue: 0.847, alpha: 1.0)
			r.lineCap = .butt
			r.lineDashPattern = [40, 0.625]
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if primary == "boundary" {
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 2.5, 2.5, 2.5]
			r.casingColor = DynamicColor(red: 0.51, green: 0.71, blue: 0.996, alpha: 1.0)
			r.casingWidth = 3.0
		}
		if (primary == "boundary" && primaryValue == "protected_area") ||
			(primary == "boundary" && primaryValue == "national_park")
		{
			r.casingColor = DynamicColor(red: 0.69, green: 0.886, blue: 0.596, alpha: 1.0)
		}
		if ((primary == "man_made" && primaryValue == "groyne") || tags["man_made"] == "groyne") ||
			((primary == "man_made" && primaryValue == "breakwater") || tags["man_made"] == "breakwater")
		{
			r.lineWidth = 1.5
			r.lineCap = .round
			r.lineDashPattern = [7.5, 2.5, 0.5, 2.5]
		}
		if has(tags, "bridge") {
			r.casingColor = DynamicColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingOpacity = 0.6
			r.casingWidth = 8.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if has(tags, "tunnel") || (tags["location"] == "underground") || (tags["location"] == "underwater") {
			r.lineOpacity = 0.3
			r.casingOpacity = 0.5
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if has(tags, "embankment") || has(tags, "cutting") {
			r.casingColor = DynamicColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingOpacity = 0.5
			r.casingWidth = 11.0
			r.casingCap = .butt
			r.casingDashPattern = [1, 2]
		}
		if surface == "unpaved" {
			r.casingColor = DynamicColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.casingCap = .butt
			r.casingDashPattern = [2, 2]
		}
		if surface == "semipaved" {
			r.casingCap = .butt
			r.casingDashPattern = [3, 1]
		}
		if primary == "building" {
			r.lineColor = DynamicColor(red: 0.878, green: 0.431, blue: 0.373, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.878, green: 0.431, blue: 0.373, alpha: 0.3)
		}
		if (((primary == "leisure" && primaryValue == "pitch") || tags["leisure"] == "pitch") && tags["sport"] ==
			"beachvolleyball") ||
			(((primary == "leisure" && primaryValue == "pitch") || tags["leisure"] == "pitch") && tags["sport"] ==
				"baseball") ||
			(((primary == "leisure" && primaryValue == "pitch") || tags["leisure"] == "pitch") && tags["sport"] ==
				"softball")
		{
			r.lineColor = DynamicColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
			r.areaColor = DynamicColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (primary == "landuse" && primaryValue == "grass") && tags["golf"] == "green" {
			r.lineColor = DynamicColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (((primary == "leisure" && primaryValue == "pitch") || tags["leisure"] == "pitch") && tags["sport"] ==
			"basketball") ||
			(((primary == "leisure" && primaryValue == "pitch") || tags["leisure"] == "pitch") && tags["sport"] ==
				"skateboard")
		{
			r.lineColor = DynamicColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (primary == "highway" && primaryValue == "service") && tags["service"] == "driveway" {
			r.lineWidth = 2.125
			r.casingWidth = 3.125
		}
		if (primary == "highway" && primaryValue == "service") && has(tags, "service") {
			r.lineColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "service") && tags["service"] == "parking_aisle" {
			r.lineColor = DynamicColor(red: 0.8, green: 0.792, blue: 0.78, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "service") && tags["service"] == "driveway" {
			r.lineColor = DynamicColor(red: 1.0, green: 0.965, blue: 0.894, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "service") && tags["service"] == "emergency_access" {
			r.lineColor = DynamicColor(red: 0.867, green: 0.698, blue: 0.667, alpha: 1.0)
		}
		if ((primary == "highway" && primaryValue == "footway") && tags["public_transport"] == "platform") ||
			((primary == "highway" && primaryValue == "footway") &&
				((primary == "man_made" && primaryValue == "pier") || tags["man_made"] == "pier")) ||
			(primary == "highway" && has(tags, "crossing")) ||
			(primary == "highway" && tags["footway"] == "access_aisle")
		{
			r.casingColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && primaryValue == "path") && tags["bridge"] == "boardwalk" {
			r.lineColor = DynamicColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "footway") && tags["footway"] == "sidewalk" {
			r.lineColor = DynamicColor(red: 0.831, green: 0.706, blue: 0.706, alpha: 1.0)
		}
		if primary == "highway" && tags["crossing"] == "unmarked" {
			r.lineDashPattern = [3, 2]
		}
		if primary == "highway" && tags["crossing"] == "marked" {
			r.lineDashPattern = [3, 1.5]
		}
		if (primary == "highway" && primaryValue == "footway") && tags["crossing"] == "marked" {
			r.lineColor = DynamicColor(red: 0.298, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "footway") && tags["crossing"] == "unmarked" {
			r.lineColor = DynamicColor(red: 0.467, green: 0.416, blue: 0.416, alpha: 1.0)
		}
		if (primary == "highway" && primaryValue == "cycleway") && tags["crossing"] == "marked" {
			r.lineColor = DynamicColor(red: 0.267, green: 0.376, blue: 0.467, alpha: 1.0)
		}
		if primary == "highway" && tags["footway"] == "access_aisle" {
			r.lineColor = DynamicColor(red: 0.298, green: 0.267, blue: 0.267, alpha: 1.0)
			r.lineDashPattern = [2, 1]
		}
		if (primary == "railway" && (primary == "railway" && primaryValue == "platform_edge")) ||
			(primary == "railway" && (primary == "railway" && primaryValue == "platform"))
		{
			r.lineDashPattern = nil
			r.casingWidth = 0.0
		}
		if primary == "railway" && status != nil {
			r.casingColor = DynamicColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
		}
		if primary == "railway" && status == "disused" {
			r.casingColor = DynamicColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1.0)
		}
		if primary == "waterway" && primary == "waterway" && primaryValue != "dam" {
			r.lineColor = DynamicColor(red: 0.467, green: 0.867, blue: 0.867, alpha: 1.0)
			r.casingColor = DynamicColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
			r.areaColor = DynamicColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if has(tags, "barrier") && primary != "waterway" {
			r.lineWidth = 1.5
			r.lineCap = .round
			r.lineDashPattern = [7.5, 2.5, 0.5, 2.5]
		}
		if (has(tags, "barrier") && tags["barrier"] == "wall") ||
			(has(tags, "barrier") && tags["barrier"] == "retaining_wall") ||
			(has(tags, "barrier") && tags["barrier"] == "city_wall")
		{
			r.lineCap = .butt
			r.lineDashPattern = [8, 1.5, 4.5, 1.5]
		}
		if (primary == "railway" && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "living_street") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "path") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "corridor") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "pedestrian") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "service") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "track") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "steps") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "ladder") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "footway") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "cycleway") && has(tags, "bridge")) ||
			((primary == "highway" && primaryValue == "bridleway") && has(tags, "bridge"))
		{
			r.casingWidth = 5.0
		}
		if (has(tags, "bridge") && surface == "unpaved") || (has(tags, "bridge") && surface == "semipaved") {
			r.casingColor = DynamicColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
		}
		if status != nil && status != "disused" {
			r.lineCap = .butt
			r.lineDashPattern = [3.5, 1.5]
			r.casingCap = .butt
			r.casingDashPattern = [3.5, 1.5]
		}
		if primary == "railway" && status != nil && !has(tags, "service") {
			r.lineColor = DynamicColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0)
		}
		if has(tags, "barrier") && tags["barrier"] != "hedge" && primary != "waterway" {
			r.lineColor = DynamicColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0)
		}
		if primary == "highway" && status != nil && status == "construction" {
			r.lineColor = DynamicColor(red: 0.988, green: 0.424, blue: 0.078, alpha: 1.0)
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [5, 5]
			r.casingColor = DynamicColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && tags["construction"] == "path" && status != nil && status == "construction") ||
			(primary == "highway" && tags["construction"] == "footway" && status != nil && status == "construction") ||
			(primary == "highway" && tags["construction"] == "cycleway" && status != nil && status == "construction") ||
			(
				primary == "highway" && tags["construction"] == "bridleway" && status != nil && status ==
					"construction") ||
			(primary == "highway" && tags["construction"] == "corridor" && status != nil && status == "construction") ||
			(primary == "highway" && tags["construction"] == "steps" && status != nil && status == "construction") ||
			(primary == "highway" && tags["construction"] == "ladder" && status != nil && status == "construction")
		{
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [5, 5]
			r.casingWidth = 2.5
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && tags["proposed"] == "path" && status != nil && status == "proposed") ||
			(primary == "highway" && tags["proposed"] == "footway" && status != nil && status == "proposed") ||
			(primary == "highway" && tags["proposed"] == "cycleway" && status != nil && status == "proposed") ||
			(primary == "highway" && tags["proposed"] == "bridleway" && status != nil && status == "proposed") ||
			(primary == "highway" && tags["proposed"] == "steps" && status != nil && status == "proposed") ||
			(primary == "highway" && tags["proposed"] == "ladder" && status != nil && status == "proposed")
		{
			r.lineWidth = 1.5
			r.casingWidth = 2.25
		}
		if (primary == "highway" && has(tags, "bridge") && tags["proposed"] == "path" && status != nil && status ==
			"proposed") ||
			(primary == "highway" && has(tags, "bridge") && tags["proposed"] == "footway" && status != nil && status ==
				"proposed") ||
			(primary == "highway" && has(tags, "bridge") && tags["proposed"] == "cycleway" && status != nil && status ==
				"proposed") ||
			(primary == "highway" && has(tags, "bridge") && tags["proposed"] == "bridleway" && status != nil &&
				status ==
				"proposed") ||
			(primary == "highway" && has(tags, "bridge") && tags["proposed"] == "steps" && status != nil && status ==
				"proposed") ||
			(primary == "highway" && has(tags, "bridge") && tags["proposed"] == "ladder" && status != nil && status ==
				"proposed")
		{
			r.casingWidth = 5.0
		}

		return r
	}
}
