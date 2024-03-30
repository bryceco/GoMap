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
		if (classes.contains("barrier-hedge")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("landuse-flowerbed")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("landuse-forest")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("landuse-grass")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("landuse-recreation_ground")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("landuse-village_green")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-garden")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-golf_course")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-nature_reserve")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-park")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-pitch")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-track")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (primary == "natural") {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("natural-wood")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("golf-tee")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("golf-fairway")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("golf-rough")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("golf-green")) {
			r.lineColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("barrier-hedge")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("landuse-flowerbed")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("landuse-forest")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("landuse-grass")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("landuse-recreation_ground")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("landuse-village_green")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-garden")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-golf_course")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-nature_reserve")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-park")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-pitch")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-track")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (primary == "natural") {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("natural-wood")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("golf-tee")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("golf-fairway")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("golf-rough")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("golf-green")) {
			r.areaColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("amenity-fountain")) {
			r.lineColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
		}
		if (classes.contains("leisure-swimming_pool")) {
			r.lineColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
		}
		if (classes.contains("natural-bay")) {
			r.lineColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
		}
		if (classes.contains("natural-strait")) {
			r.lineColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
		}
		if (classes.contains("natural-water")) {
			r.lineColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 1.0)
		}
		if (classes.contains("amenity-fountain")) {
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if (classes.contains("leisure-swimming_pool")) {
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if (classes.contains("natural-bay")) {
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if (classes.contains("natural-strait")) {
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if (classes.contains("natural-water")) {
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if (classes.contains("leisure-track")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("natural-beach")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("natural-sand")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("natural-scrub")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("amenity-childcare")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("amenity-kindergarten")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("amenity-school")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("amenity-college")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("amenity-university")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("amenity-research_institute")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("leisure-track")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("natural-beach")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("natural-sand")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("natural-scrub")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("amenity-childcare")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("amenity-kindergarten")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("amenity-school")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("amenity-college")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("amenity-university")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("amenity-research_institute")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("landuse-residential")) {
			r.lineColor = UIColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 1.0)
		}
		if (status == "construction") {
			r.lineColor = UIColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 1.0)
		}
		if (classes.contains("landuse-residential")) {
			r.areaColor = UIColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 0.3)
		}
		if (status == "construction") {
			r.areaColor = UIColor(red: 0.769, green: 0.741, blue: 0.098, alpha: 0.3)
		}
		if (classes.contains("landuse-retail")) {
			r.lineColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
		}
		if (classes.contains("landuse-commercial")) {
			r.lineColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
		}
		if (classes.contains("landuse-landfill")) {
			r.lineColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
		}
		if (primary == "military") {
			r.lineColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
		}
		if (classes.contains("landuse-military")) {
			r.lineColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 1.0)
		}
		if (classes.contains("landuse-retail")) {
			r.areaColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if (classes.contains("landuse-commercial")) {
			r.areaColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if (classes.contains("landuse-landfill")) {
			r.areaColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if (primary == "military") {
			r.areaColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if (classes.contains("landuse-military")) {
			r.areaColor = UIColor(red: 0.839, green: 0.533, blue: 0.102, alpha: 0.3)
		}
		if (classes.contains("landuse-industrial")) {
			r.lineColor = UIColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 1.0)
		}
		if (classes.contains("power-plant")) {
			r.lineColor = UIColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 1.0)
		}
		if (classes.contains("landuse-industrial")) {
			r.areaColor = UIColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 0.3)
		}
		if (classes.contains("power-plant")) {
			r.areaColor = UIColor(red: 0.894, green: 0.643, blue: 0.961, alpha: 0.3)
		}
		if (classes.contains("natural-wetland")) {
			r.lineColor = UIColor(red: 0.6, green: 0.882, blue: 0.667, alpha: 1.0)
			r.areaColor = UIColor(red: 0.6, green: 0.882, blue: 0.667, alpha: 0.3)
		}
		if (classes.contains("landuse-cemetery")) {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
		}
		if (classes.contains("landuse-farmland")) {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
		}
		if (classes.contains("landuse-meadow")) {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
		}
		if (classes.contains("landuse-orchard")) {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
		}
		if (classes.contains("landuse-vineyard")) {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
		}
		if (classes.contains("landuse-cemetery")) {
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("landuse-farmland")) {
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("landuse-meadow")) {
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("landuse-orchard")) {
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("landuse-vineyard")) {
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("landuse-farmyard")) {
			r.lineColor = UIColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 1.0)
		}
		if (classes.contains("leisure-horse_riding")) {
			r.lineColor = UIColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 1.0)
		}
		if (classes.contains("landuse-farmyard")) {
			r.areaColor = UIColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 0.3)
		}
		if (classes.contains("leisure-horse_riding")) {
			r.areaColor = UIColor(red: 0.961, green: 0.863, blue: 0.729, alpha: 0.3)
		}
		if (classes.contains("amenity-parking")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("landuse-railway")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("landuse-quarry")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("man_made-adit")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("man_made-groyne")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("man_made-breakwater")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-bare_rock")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-cave_entrance")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-cliff")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-rock")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-scree")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-stone")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-shingle")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("waterway-dam")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("waterway-weir")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("amenity-parking")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("landuse-railway")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("landuse-quarry")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("man_made-adit")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("man_made-groyne")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("man_made-breakwater")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-bare_rock")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-cliff")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-cave_entrance")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-rock")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-scree")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-stone")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-shingle")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("waterway-dam")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("waterway-weir")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("natural-cave_entrance")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-glacier")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("natural-cave_entrance")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if (classes.contains("natural-glacier")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if (primary == "highway") {
			r.lineColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.lineWidth = 8.0
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-motorway")) {
			r.lineColor = UIColor(red: 0.812, green: 0.125, blue: 0.506, alpha: 1.0)
		}
		if (classes.contains("highway-motorway_link")) {
			r.lineColor = UIColor(red: 0.812, green: 0.125, blue: 0.506, alpha: 1.0)
		}
		if (classes.contains("motorway")) {
			r.lineColor = UIColor(red: 0.812, green: 0.125, blue: 0.506, alpha: 1.0)
		}
		if (classes.contains("highway-motorway")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-motorway_link")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("motorway")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-trunk")) {
			r.lineColor = UIColor(red: 0.867, green: 0.184, blue: 0.133, alpha: 1.0)
		}
		if (classes.contains("highway-trunk_link")) {
			r.lineColor = UIColor(red: 0.867, green: 0.184, blue: 0.133, alpha: 1.0)
		}
		if (classes.contains("trunk")) {
			r.lineColor = UIColor(red: 0.867, green: 0.184, blue: 0.133, alpha: 1.0)
		}
		if (classes.contains("highway-trunk")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-trunk_link")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("trunk")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-primary")) {
			r.lineColor = UIColor(red: 0.976, green: 0.596, blue: 0.024, alpha: 1.0)
		}
		if (classes.contains("highway-primary_link")) {
			r.lineColor = UIColor(red: 0.976, green: 0.596, blue: 0.024, alpha: 1.0)
		}
		if (classes.contains("primary")) {
			r.lineColor = UIColor(red: 0.976, green: 0.596, blue: 0.024, alpha: 1.0)
		}
		if (classes.contains("highway-primary")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-primary_link")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("primary")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-secondary")) {
			r.lineColor = UIColor(red: 0.953, green: 0.953, blue: 0.071, alpha: 1.0)
		}
		if (classes.contains("highway-secondary_link")) {
			r.lineColor = UIColor(red: 0.953, green: 0.953, blue: 0.071, alpha: 1.0)
		}
		if (classes.contains("secondary")) {
			r.lineColor = UIColor(red: 0.953, green: 0.953, blue: 0.071, alpha: 1.0)
		}
		if (classes.contains("highway-secondary")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-secondary_link")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("secondary")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-tertiary")) {
			r.lineColor = UIColor(red: 1.0, green: 0.976, blue: 0.702, alpha: 1.0)
		}
		if (classes.contains("highway-tertiary_link")) {
			r.lineColor = UIColor(red: 1.0, green: 0.976, blue: 0.702, alpha: 1.0)
		}
		if (classes.contains("tertiary")) {
			r.lineColor = UIColor(red: 1.0, green: 0.976, blue: 0.702, alpha: 1.0)
		}
		if (classes.contains("highway-tertiary")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-tertiary_link")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("tertiary")) {
			r.casingColor = UIColor(red: 0.439, green: 0.216, blue: 0.184, alpha: 1.0)
		}
		if (classes.contains("highway-residential")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		}
		if (classes.contains("residential")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		}
		if (classes.contains("highway-residential")) {
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("residential")) {
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("highway-unclassified")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("unclassified")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-unclassified")) {
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("unclassified")) {
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("highway-living_street")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("highway-bus_guideway")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("highway-service")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("highway-track")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("highway-road")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("highway-living_street")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("highway-bus_guideway")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("highway-service")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("highway-track")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("highway-road")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("highway-path")) {
			r.casingWidth = 5.0
		}
		if (classes.contains("highway-footway")) {
			r.casingWidth = 5.0
		}
		if (classes.contains("highway-cycleway")) {
			r.casingWidth = 5.0
		}
		if (classes.contains("highway-bridleway")) {
			r.casingWidth = 5.0
		}
		if (classes.contains("highway-corridor")) {
			r.casingWidth = 5.0
		}
		if (classes.contains("highway-steps")) {
			r.casingWidth = 5.0
		}
		if (classes.contains("highway-path")) {
			r.lineWidth = 3.0
		}
		if (classes.contains("highway-footway")) {
			r.lineWidth = 3.0
		}
		if (classes.contains("highway-cycleway")) {
			r.lineWidth = 3.0
		}
		if (classes.contains("highway-bridleway")) {
			r.lineWidth = 3.0
		}
		if (classes.contains("highway-corridor")) {
			r.lineWidth = 3.0
		}
		if (classes.contains("highway-steps")) {
			r.lineWidth = 3.0
		}
		if (classes.contains("highway-living_street")) {
			r.lineColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
		}
		if (classes.contains("living_street")) {
			r.lineColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
		}
		if (classes.contains("highway-living_street")) {
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		}
		if (classes.contains("living_street")) {
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
		}
		if (classes.contains("highway-corridor")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineDashPattern = [2, 8]
		}
		if (classes.contains("corridor")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineDashPattern = [2, 8]
		}
		if (classes.contains("highway-corridor")) {
			r.casingColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("corridor")) {
			r.casingColor = UIColor(red: 0.549, green: 0.816, blue: 0.373, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-pedestrian")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 3.5
			r.lineCap = .butt
			r.lineDashPattern = [8, 8]
		}
		if (classes.contains("pedestrian")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 3.5
			r.lineCap = .butt
			r.lineDashPattern = [8, 8]
		}
		if (classes.contains("highway-pedestrian")) {
			r.casingColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("pedestrian")) {
			r.casingColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-road")) {
			r.lineColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
		}
		if (classes.contains("road")) {
			r.lineColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
		}
		if (classes.contains("highway-road")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("road")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("highway-service")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("highway-bus_guideway")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("service")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-bus_guideway")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("service")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("highway-track")) {
			r.lineColor = UIColor(red: 0.773, green: 0.71, blue: 0.624, alpha: 1.0)
		}
		if (classes.contains("track")) {
			r.lineColor = UIColor(red: 0.773, green: 0.71, blue: 0.624, alpha: 1.0)
		}
		if (classes.contains("highway-track")) {
			r.casingColor = UIColor(red: 0.455, green: 0.435, blue: 0.435, alpha: 1.0)
		}
		if (classes.contains("track")) {
			r.casingColor = UIColor(red: 0.455, green: 0.435, blue: 0.435, alpha: 1.0)
		}
		if (classes.contains("highway-path")) {
			r.lineCap = .butt
			r.lineDashPattern = [6, 6]
		}
		if (classes.contains("highway-footway")) {
			r.lineCap = .butt
			r.lineDashPattern = [6, 6]
		}
		if (classes.contains("highway-cycleway")) {
			r.lineCap = .butt
			r.lineDashPattern = [6, 6]
		}
		if (classes.contains("highway-bridleway")) {
			r.lineCap = .butt
			r.lineDashPattern = [6, 6]
		}
		if (classes.contains("crossing")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("footway-access_aisle")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("public_transport-platform")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-platform")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("railway-platform")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("railway-platform_edge")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("man_made-pier")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-path")) {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-footway")) {
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-cycleway")) {
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-bridleway")) {
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-path")) {
			r.lineColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
		}
		if (classes.contains("highway-footway")) {
			r.lineColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
		}
		if (classes.contains("highway-bus_stop")) {
			r.lineColor = UIColor(red: 0.6, green: 0.533, blue: 0.533, alpha: 1.0)
		}
		if (classes.contains("highway-cycleway")) {
			r.lineColor = UIColor(red: 0.345, green: 0.663, blue: 0.929, alpha: 1.0)
		}
		if (classes.contains("highway-bridleway")) {
			r.lineColor = UIColor(red: 0.878, green: 0.427, blue: 0.373, alpha: 1.0)
		}
		if (classes.contains("leisure-track")) {
			r.lineColor = UIColor(red: 0.898, green: 0.722, blue: 0.169, alpha: 1.0)
		}
		if (classes.contains("highway-steps")) {
			r.lineColor = UIColor(red: 0.506, green: 0.824, blue: 0.361, alpha: 1.0)
			r.lineCap = .butt
			r.lineDashPattern = [3, 3]
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "aeroway") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
			r.lineDashPattern = nil
		}
		if (classes.contains("aeroway-runway")) {
			r.areaColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6)
		}
		if (classes.contains("aeroway-taxiway")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
			r.casingWidth = 7.0
		}
		if (classes.contains("taxiway")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
			r.casingWidth = 7.0
		}
		if (classes.contains("aeroway-taxiway")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
			r.lineWidth = 5.0
		}
		if (classes.contains("taxiway")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
			r.lineWidth = 5.0
		}
		if (classes.contains("aeroway-runway")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [24, 48]
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 10.0
			r.casingCap = .square
		}
		if (primary == "railway") {
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [12, 12]
			r.casingWidth = 7.0
		}
		if (primary == "railway") {
			r.lineColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0)
			r.casingColor = UIColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 1.0)
		}
		if (classes.contains("railway-subway")) {
			r.lineColor = UIColor(red: 0.733, green: 0.733, blue: 0.733, alpha: 1.0)
			r.casingColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1.0)
		}
		if (classes.contains("waterway-dock")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
		}
		if (classes.contains("waterway-boatyard")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
		}
		if (classes.contains("waterway-fuel")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 1.0
		}
		if (classes.contains("waterway-dock")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if (classes.contains("waterway-boatyard")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if (classes.contains("waterway-fuel")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.3)
		}
		if (primary == "waterway") {
			r.lineWidth = 5.0
			r.casingWidth = 7.0
		}
		if (classes.contains("waterway-river")) {
			r.lineWidth = 8.0
			r.casingWidth = 10.0
		}
		if (classes.contains("waterway-ditch")) {
			r.lineColor = UIColor(red: 0.2, green: 0.6, blue: 0.667, alpha: 1.0)
		}
		if (primary == "aerialway") {
			r.casingWidth = 7.0
		}
		if (classes.contains("attraction-summer_toboggan")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("attraction-water_slide")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("golf-cartpath")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("man_made-pipeline")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("natural-tree_row")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("roller_coaster-track")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("roller_coaster-support")) {
			r.casingWidth = 7.0
		}
		if (classes.contains("piste")) {
			r.casingWidth = 7.0
		}
		if (primary == "aerialway") {
			r.lineWidth = 5.0
		}
		if (classes.contains("attraction-summer_toboggan")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("attraction-water_slide")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("golf-cartpath")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("man_made-pipeline")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("natural-tree_row")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("roller_coaster-track")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("roller_coaster-support")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("piste")) {
			r.lineWidth = 5.0
		}
		if (classes.contains("route-ferry")) {
			r.lineColor = UIColor(red: 0.345, green: 0.663, blue: 0.929, alpha: 1.0)
			r.lineWidth = 3.0
			r.lineCap = .butt
			r.lineDashPattern = [12, 8]
		}
		if (primary == "aerialway") {
			r.lineColor = UIColor(red: 0.8, green: 0.333, blue: 0.333, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("piste")) {
			r.lineColor = UIColor(red: 0.667, green: 0.6, blue: 0.867, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("attraction-summer_toboggan")) {
			r.lineColor = UIColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("attraction-water_slide")) {
			r.lineColor = UIColor(red: 0.667, green: 0.878, blue: 0.796, alpha: 1.0)
			r.casingColor = UIColor(red: 0.239, green: 0.424, blue: 0.443, alpha: 1.0)
		}
		if (classes.contains("roller_coaster-track")) {
			r.lineColor = UIColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0)
			r.lineWidth = 3.0
			r.lineCap = .butt
			r.lineDashPattern = [5, 1]
			r.casingColor = UIColor(red: 0.439, green: 0.439, blue: 0.439, alpha: 1.0)
		}
		if (classes.contains("roller_coaster-support")) {
			r.lineColor = UIColor(red: 0.439, green: 0.439, blue: 0.439, alpha: 1.0)
		}
		if (classes.contains("golf-cartpath")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (primary == "power") {
			r.lineColor = UIColor(red: 0.576, green: 0.576, blue: 0.576, alpha: 1.0)
			r.lineWidth = 2.0
		}
		if (classes.contains("man_made-pipeline")) {
			r.lineColor = UIColor(red: 0.796, green: 0.816, blue: 0.847, alpha: 1.0)
			r.lineCap = .butt
			r.lineDashPattern = [80, 1]
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (primary == "boundary") {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.lineWidth = 2.0
			r.lineCap = .butt
			r.lineDashPattern = [20, 5, 5, 5]
			r.casingColor = UIColor(red: 0.51, green: 0.71, blue: 0.996, alpha: 1.0)
			r.casingWidth = 6.0
		}
		if (classes.contains("boundary-protected_area")) {
			r.casingColor = UIColor(red: 0.69, green: 0.886, blue: 0.596, alpha: 1.0)
		}
		if (classes.contains("boundary-national_park")) {
			r.casingColor = UIColor(red: 0.69, green: 0.886, blue: 0.596, alpha: 1.0)
		}
		if (classes.contains("man_made-groyne")) {
			r.lineWidth = 3.0
			r.lineCap = .round
			r.lineDashPattern = [15, 5, 1, 5]
		}
		if (classes.contains("man_made-breakwater")) {
			r.lineWidth = 3.0
			r.lineCap = .round
			r.lineDashPattern = [15, 5, 1, 5]
		}
		if (classes.contains("bridge")) {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 16.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (classes.contains("tunnel")) {
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (classes.contains("location-underground")) {
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (classes.contains("location-underwater")) {
			r.lineCap = .butt
			r.lineDashPattern = nil
		}
		if (classes.contains("embankment")) {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 22.0
			r.casingCap = .butt
			r.casingDashPattern = [2, 4]
		}
		if (classes.contains("cutting")) {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
			r.casingWidth = 22.0
			r.casingCap = .butt
			r.casingDashPattern = [2, 4]
		}
		if (classes.contains("unpaved")) {
			r.casingColor = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
			r.casingCap = .butt
			r.casingDashPattern = [4, 4]
		}
		if (classes.contains("semipaved")) {
			r.casingCap = .butt
			r.casingDashPattern = [6, 2]
		}
		if (primary == "building") {
			r.lineColor = UIColor(red: 0.878, green: 0.431, blue: 0.373, alpha: 1.0)
			r.areaColor = UIColor(red: 0.878, green: 0.431, blue: 0.373, alpha: 0.3)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-beachvolleyball")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-baseball")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-softball")) {
			r.lineColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.75)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-beachvolleyball")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-baseball")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-softball")) {
			r.areaColor = UIColor(red: 1.0, green: 1.0, blue: 0.58, alpha: 0.25)
		}
		if (classes.contains("landuse-grass") && classes.contains("golf-green")) {
			r.lineColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 1.0)
		}
		if (classes.contains("landuse-grass") && classes.contains("golf-green")) {
			r.areaColor = UIColor(red: 0.749, green: 0.91, blue: 0.247, alpha: 0.3)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-basketball")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-skateboard")) {
			r.lineColor = UIColor(red: 0.667, green: 0.667, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-basketball")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("leisure-pitch") && classes.contains("sport-skateboard")) {
			r.areaColor = UIColor(red: 0.549, green: 0.549, blue: 0.549, alpha: 0.5)
		}
		if (classes.contains("highway-service") && classes.contains("service-driveway")) {
			r.lineWidth = 4.25
			r.casingWidth = 6.25
		}
		if (classes.contains("highway-service") && classes.contains("service")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-service") && classes.contains("service")) {
			r.casingColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
		}
		if (classes.contains("highway-service") && classes.contains("service-parking_aisle")) {
			r.lineColor = UIColor(red: 0.8, green: 0.792, blue: 0.78, alpha: 1.0)
		}
		if (classes.contains("highway-service") && classes.contains("service-driveway")) {
			r.lineColor = UIColor(red: 1.0, green: 0.965, blue: 0.894, alpha: 1.0)
		}
		if (classes.contains("highway-service") && classes.contains("service-emergency_access")) {
			r.lineColor = UIColor(red: 0.867, green: 0.698, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-footway") && classes.contains("public_transport-platform")) {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-footway") && classes.contains("man_made-pier")) {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && classes.contains("crossing")) {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (primary == "highway" && classes.contains("footway-access_aisle")) {
			r.casingColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
			r.casingCap = .round
			r.casingDashPattern = nil
		}
		if (classes.contains("highway-path") && classes.contains("bridge-boardwalk")) {
			r.lineColor = UIColor(red: 0.867, green: 0.8, blue: 0.667, alpha: 1.0)
		}
		if (classes.contains("highway-footway") && classes.contains("footway-sidewalk")) {
			r.lineColor = UIColor(red: 0.831, green: 0.706, blue: 0.706, alpha: 1.0)
		}
		if (primary == "highway" && classes.contains("crossing-unmarked")) {
			r.lineDashPattern = [6, 4]
		}
		if (primary == "highway" && classes.contains("crossing-marked")) {
			r.lineDashPattern = [6, 3]
		}
		if (classes.contains("highway-footway") && classes.contains("crossing-marked")) {
			r.lineColor = UIColor(red: 0.298, green: 0.267, blue: 0.267, alpha: 1.0)
		}
		if (classes.contains("highway-footway") && classes.contains("crossing-unmarked")) {
			r.lineColor = UIColor(red: 0.467, green: 0.416, blue: 0.416, alpha: 1.0)
		}
		if (classes.contains("highway-cycleway") && classes.contains("crossing-marked")) {
			r.lineColor = UIColor(red: 0.267, green: 0.376, blue: 0.467, alpha: 1.0)
		}
		if (primary == "highway" && classes.contains("footway-access_aisle")) {
			r.lineColor = UIColor(red: 0.298, green: 0.267, blue: 0.267, alpha: 1.0)
			r.lineDashPattern = [4, 2]
		}
		if (primary == "railway" && classes.contains("railway-platform_edge")) {
			r.casingWidth = 0.0
		}
		if (primary == "railway" && classes.contains("railway-platform")) {
			r.casingWidth = 0.0
		}
		if (primary == "railway" && classes.contains("railway-platform_edge")) {
			r.lineDashPattern = nil
		}
		if (primary == "railway" && classes.contains("railway-platform")) {
			r.lineDashPattern = nil
		}
		if (primary == "railway" && status != nil) {
			r.casingColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
		}
		if (primary == "railway" && status == "disused") {
			r.casingColor = UIColor(red: 0.502, green: 0.502, blue: 0.502, alpha: 1.0)
		}
		if (primary == "waterway" && !classes.contains("waterway-dam")) {
			r.lineColor = UIColor(red: 0.467, green: 0.867, blue: 0.867, alpha: 1.0)
			r.casingColor = UIColor(red: 0.267, green: 0.267, blue: 0.267, alpha: 1.0)
			r.areaColor = UIColor(red: 0.467, green: 0.827, blue: 0.871, alpha: 0.3)
		}
		if (classes.contains("barrier") && primary != "waterway") {
			r.lineWidth = 3.0
			r.lineCap = .round
			r.lineDashPattern = [15, 5, 1, 5]
		}
		if (classes.contains("barrier") && classes.contains("barrier-wall")) {
			r.lineCap = .butt
			r.lineDashPattern = [16, 3, 9, 3]
		}
		if (classes.contains("barrier") && classes.contains("barrier-retaining_wall")) {
			r.lineCap = .butt
			r.lineDashPattern = [16, 3, 9, 3]
		}
		if (classes.contains("barrier") && classes.contains("barrier-city_wall")) {
			r.lineCap = .butt
			r.lineDashPattern = [16, 3, 9, 3]
		}
		if (primary == "railway" && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-living_street") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-path") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-corridor") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-pedestrian") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-service") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-track") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-steps") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-footway") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-cycleway") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("highway-bridleway") && classes.contains("bridge")) {
			r.casingWidth = 10.0
		}
		if (classes.contains("bridge") && classes.contains("unpaved")) {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
		}
		if (classes.contains("bridge") && classes.contains("semipaved")) {
			r.casingColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
		}
		if (status != nil && status != "disused") {
			r.lineCap = .butt
			r.lineDashPattern = [7, 3]
			r.casingCap = .butt
			r.casingDashPattern = [7, 3]
		}
		if (primary == "railway" && status != nil && !classes.contains("service")) {
			r.lineColor = UIColor(red: 0.933, green: 0.933, blue: 0.933, alpha: 1.0)
		}
		if (classes.contains("barrier") && !classes.contains("barrier-hedge") && primary != "waterway") {
			r.lineColor = UIColor(red: 0.867, green: 0.867, blue: 0.867, alpha: 1.0)
		}
		if (primary == "highway" && status != nil && status == "construction") {
			r.lineColor = UIColor(red: 0.988, green: 0.424, blue: 0.078, alpha: 1.0)
			r.lineWidth = 8.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
			r.casingColor = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
			r.casingWidth = 10.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-path")) {
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-footway")) {
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-cycleway")) {
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-bridleway")) {
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-steps")) {
			r.casingWidth = 5.0
			r.casingCap = .butt
			r.casingDashPattern = nil
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-path")) {
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-footway")) {
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-cycleway")) {
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-bridleway")) {
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
		}
		if (primary == "highway" && status != nil && status == "construction" && classes.contains("construction-steps")) {
			r.lineWidth = 4.0
			r.lineCap = .butt
			r.lineDashPattern = [10, 10]
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-path")) {
			r.casingWidth = 4.5
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-footway")) {
			r.casingWidth = 4.5
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-cycleway")) {
			r.casingWidth = 4.5
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-bridleway")) {
			r.casingWidth = 4.5
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-steps")) {
			r.casingWidth = 4.5
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-path")) {
			r.lineWidth = 3.0
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-footway")) {
			r.lineWidth = 3.0
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-cycleway")) {
			r.lineWidth = 3.0
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-bridleway")) {
			r.lineWidth = 3.0
		}
		if (primary == "highway" && status != nil && status == "proposed" && classes.contains("proposed-steps")) {
			r.lineWidth = 3.0
		}
		if (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-path")) {
			r.casingWidth = 10.0
		}
		if (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-footway")) {
			r.casingWidth = 10.0
		}
		if (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-cycleway")) {
			r.casingWidth = 10.0
		}
		if (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-bridleway")) {
			r.casingWidth = 10.0
		}
		if (primary == "highway" && classes.contains("bridge") && status != nil && status == "proposed" && classes.contains("proposed-steps")) {
			r.casingWidth = 10.0
		}

		return r
	}
}
