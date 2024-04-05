//
//  RenderInfo.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit
import Collections

private let RenderInfoMaxPriority = (33 + 1) * 3

private let g_AddressRender: RenderInfo = {
	let info = RenderInfo()
	info.key = "ADDRESS"
	info.lineWidth = 0.0
	return info
}()

private let g_DefaultRender: RenderInfo = {
	let info = RenderInfo()
	info.key = "DEFAULT"
	info.lineColor = UIColor.black
	info.lineWidth = 0.0
	return info
}()

final class RenderInfo {
	var renderPriority = 0

	var key = ""
	var value: String?
	var lineColor: UIColor?
	var lineWidth: CGFloat = 0.0
	var lineCap: CAShapeLayerLineCap = .butt
	var lineDashPattern: [NSNumber]?
	var casingColor: UIColor?
	var casingWidth: CGFloat = 0.0
	var casingCap: CAShapeLayerLineCap = .butt
	var casingDashPattern: [NSNumber]?
	var areaColor: UIColor?

	var description: String {
		return "\(type(of: self)): \(key)=\(value ?? "")"
	}

	func isAddressPoint() -> Bool {
		return self === g_AddressRender
	}

	init(lineColor: UIColor? = UIColor.white,
		lineWidth: CGFloat = 2.0,
		lineCap: CAShapeLayerLineCap = .round,
		lineDashPattern: [CGFloat]? = nil,
		casingColor: UIColor? = nil,
		casingWidth: CGFloat = 0.0,
		casingCap: CAShapeLayerLineCap = .butt,
		casingDashPattern: [CGFloat]? = nil,
		areaColor: UIColor? = nil) {
		
		self.lineColor = lineColor
		self.lineWidth = lineWidth
		self.lineCap = lineCap
		self.lineDashPattern = lineDashPattern?.map { NSNumber(value: $0) }
		self.casingColor = casingColor
		self.casingWidth = casingWidth
		self.casingCap = casingCap
		self.casingDashPattern = casingDashPattern?.map { NSNumber(value: $0) }
		self.areaColor = areaColor
	}


	// The priority is a small integer bounded by RenderInfoMaxPriority which
	// allows us to sort them quickly using a Counting Sort algorithm.
	// The priority is cached per-object in renderPriority
	func renderPriorityForObject(_ object: OsmBaseObject) -> Int {
		var priority: Int
		if object.modifyCount > 0 {
			priority = 33
		} else {
			if renderPriority == 0 {
				switch (key, value) {
				case ("natural", "coastline"): renderPriority = 32
				case ("natural", "water"): renderPriority = 31
				case ("waterway", "riverbank"): renderPriority = 30
				case ("landuse", _): renderPriority = 29
				case ("highway", "motorway"): renderPriority = 29
				case ("highway", "trunk"): renderPriority = 28
				case ("highway", "motorway_link"): renderPriority = 27
				case ("highway", "primary"): renderPriority = 26
				case ("highway", "trunk_link"): renderPriority = 25
				case ("highway", "secondary"): renderPriority = 24
				case ("highway", "tertiary"): renderPriority = 23
				case ("railway", _): renderPriority = 22
				case ("highway", "primary_link"): renderPriority = 21
				case ("highway", "residential"): renderPriority = 20
				case ("highway", "raceway"): renderPriority = 19
				case ("highway", "secondary_link"): renderPriority = 18
				case ("highway", "tertiary_link"): renderPriority = 17
				case ("highway", "living_street"): renderPriority = 16
				case ("highway", "road"): renderPriority = 15
				case ("highway", "unclassified"): renderPriority = 14
				case ("highway", "service"): renderPriority = 13
				case ("highway", "bus_guideway"): renderPriority = 12
				case ("highway", "track"): renderPriority = 11
				case ("highway", "pedestrian"): renderPriority = 10
				case ("highway", "cycleway"): renderPriority = 9
				case ("highway", "path"): renderPriority = 8
				case ("highway", "bridleway"): renderPriority = 7
				case ("highway", "footway"): renderPriority = 6
				case ("highway", "steps"): renderPriority = 5
				case ("highway", "construction"): renderPriority = 4
				case ("highway", "proposed"): renderPriority = 3
				case ("highway", _): renderPriority = 3
				default:
					if isAddressPoint() {
						renderPriority = 1
					} else {
						renderPriority = 2
					}
				}
			}
			priority = renderPriority
		}

		let bonus: Int
		if object.isWay() != nil || ((object.isRelation()?.isMultipolygon()) ?? false) {
			bonus = 2
		} else if object.isRelation() != nil {
			bonus = 1
		} else {
			bonus = 0
		}
		priority = 3 * priority + bonus
		assert(priority < RenderInfoMaxPriority)
		return priority
	}

	static func sortByPriority(list: ContiguousArray<OsmBaseObject>,
	                           keepingFirst k: Int) -> ContiguousArray<OsmBaseObject>
	{
		let listCount = list.count
		var countOfPriority = [Int](repeating: 0, count: RenderInfoMaxPriority)

		for obj in list {
			countOfPriority[(RenderInfoMaxPriority - 1) - obj.renderPriorityCached] += 1
		}

		var max = listCount
		for i in 1..<RenderInfoMaxPriority {
			let prevSum = countOfPriority[i - 1]
			let newSum = countOfPriority[i] + prevSum
			countOfPriority[i] = newSum
			if max == listCount {
				// we are returning only the first k items, but we don't want to
				// throw out other items of the same priority, so include them as well
				// as long as it means we don't exceed 2*k items.
				if prevSum >= k || newSum >= 2 * k {
					max = prevSum
				}
			}
		}
		guard let tmp = list.first else { return [] }
		var output = ContiguousArray<OsmBaseObject>(repeating: tmp, count: max)
		for obj in list {
			let index = (RenderInfoMaxPriority - 1) - obj.renderPriorityCached
			let dest = countOfPriority[index] - 1
			countOfPriority[index] = dest
			if dest < max {
				output[dest] = obj
			}
		}
		return output
	}
}

final class RenderInfoDatabase {
	var allFeatures: [RenderInfo] = []

	static let shared = RenderInfoDatabase()
	static let nsZero = NSNumber(value: 0.0)

	required init() {}
    
	func renderInfoForObject(_ object: OsmBaseObject) -> RenderInfo {
		var tags = object.tags
		// if the object is part of a rendered relation then inherit that relation's tags
		if object.isWay() != nil,
		   object.parentRelations.count != 0,
		   !object.hasInterestingTags()
		{
			for parent in object.parentRelations {
				if parent.isBoundary() {
					tags = parent.tags
					break
				}
			}
		}

		return RenderInfo.style(tags: tags)

		// check if it is an address point
		if object.isNode() != nil,
		   !object.tags.isEmpty,
		   tags.first(where: { key, _ in OsmTags.IsInterestingKey(key) && !key.hasPrefix("addr:") }) == nil
		{
			return g_AddressRender
		}

		return g_DefaultRender
	}
}
