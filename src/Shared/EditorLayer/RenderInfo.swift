//
//  RenderInfo.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

private let RenderInfoMaxPriority = (33 + 1) * 3

func DynamicColor(red r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha: CGFloat) -> UIColor {
	if #available(iOS 13.0, *) { // Dark Mode
		return UIColor(dynamicProvider: { traitCollection in
			if traitCollection.userInterfaceStyle == .dark {
				// lighten colors for dark mode
				let delta: CGFloat = 0.3
				let r3 = r * (1 - delta) + delta
				let g3 = g * (1 - delta) + delta
				let b3 = b * (1 - delta) + delta
				return UIColor(red: r3, green: g3, blue: b3, alpha: alpha)
			}
			return UIColor(red: r, green: g, blue: b, alpha: alpha)
		})
	} else {
		return UIColor(red: r, green: g, blue: b, alpha: alpha)
	}
}

final class RenderInfo {
	var renderPriority = 0

	var key = ""
	var value: String?
	var lineColor: UIColor?
	var lineOpacity: CGFloat = 1.0
	var lineWidth: CGFloat = 0.0
	var lineCap: CAShapeLayerLineCap
	var lineDashPattern: [NSNumber]?
	var casingColor: UIColor?
	var casingOpacity: CGFloat = 1.0
	var casingWidth: CGFloat
	var casingCap: CAShapeLayerLineCap
	var casingDashPattern: [NSNumber]?
	var areaColor: UIColor?
	var isAddressPoint: Bool

	var description: String {
		return "\(type(of: self)): \(key)=\(value ?? "")"
	}

	func isDefault() -> Bool {
		// These values should match the init() defaults
		return lineColor == UIColor.white
			&& lineOpacity == 1.0
			&& lineWidth == 1.0
			&& lineCap == .round
			&& lineDashPattern == nil
			&& casingColor == nil
			&& casingOpacity == 1.0
			&& casingWidth == 0.0
			&& casingCap == .butt
			&& casingDashPattern == nil
			&& areaColor == nil
	}

	init(
		key: String = "",
		value: String? = nil,
		lineColor: UIColor? = .white,
		lineOpacity: CGFloat = 1.0,
		lineWidth: CGFloat = 1.0,
		lineCap: CAShapeLayerLineCap = .round,
		lineDashPattern: [CGFloat]? = nil,
		casingColor: UIColor? = nil,
		casingOpacity: CGFloat = 1.0,
		casingWidth: CGFloat = 0.0,
		casingCap: CAShapeLayerLineCap = .butt,
		casingDashPattern: [CGFloat]? = nil,
		areaColor: UIColor? = nil)
	{
		self.key = key
		self.value = value
		self.lineColor = lineColor
		self.lineWidth = lineWidth
		self.lineCap = lineCap
		self.lineDashPattern = lineDashPattern?.map { NSNumber(value: $0) }
		self.casingColor = casingColor
		self.casingWidth = casingWidth
		self.casingCap = casingCap
		self.casingDashPattern = casingDashPattern?.map { NSNumber(value: $0) }
		self.areaColor = areaColor
		isAddressPoint = false
	}

	class func forObject(_ object: OsmBaseObject) -> RenderInfo {
		var tags = object.tags
		// if the object is part of a rendered relation then inherit that relation's tags
		if object is OsmWay,
		   object.parentRelations.count != 0,
		   !object.hasInterestingTags(),
		   let parent = object.parentRelations.first(where: { $0.isBoundary() })
		{
			tags = parent.tags
		}

		let renderInfo = RenderInfo.style(tags: tags)
		let isDefault = renderInfo.isDefault()

		// adjust things for improved visibility
		renderInfo.lineWidth = 2 * renderInfo.lineWidth
		renderInfo.casingWidth = 2 * renderInfo.casingWidth
		renderInfo.lineDashPattern = renderInfo.lineDashPattern?.map({ NSNumber(value: $0.doubleValue * 0.5) })
		renderInfo.casingDashPattern = renderInfo.casingDashPattern?.map({ NSNumber(value: $0.doubleValue * 0.5) })
		if renderInfo.casingColor == nil {
			renderInfo.casingColor = UIColor.black
			renderInfo.casingWidth = renderInfo.lineWidth + 1
		} else if renderInfo.casingDashPattern != nil {
			// dashes in casing are hard to see, so make sure they're extra wide
			renderInfo.casingWidth = max(renderInfo.casingWidth, renderInfo.lineWidth + 4)
		} else if renderInfo.lineWidth >= renderInfo.casingWidth {
			renderInfo.casingWidth = renderInfo.lineWidth + 1
		}
		
		// combine opacity with color's alpha channel
		if let color = renderInfo.lineColor {
			renderInfo.lineColor = color.withAlphaComponent(color.cgColor.alpha * renderInfo.lineOpacity)
		}
		if let color = renderInfo.casingColor {
			renderInfo.casingColor = color.withAlphaComponent(color.cgColor.alpha * renderInfo.casingOpacity)
		}

		// check if it is an address point
		if isDefault,
		   object is OsmNode,
		   !tags.isEmpty,
		   tags.keys.first(where: { OsmTags.IsInterestingKey($0) && !$0.hasPrefix("addr:") }) == nil
		{
			renderInfo.isAddressPoint = true
		}

		// do this last: compute priority (what gets displayed when zoomed out)
		renderInfo.renderPriority = renderInfo.computeRenderPriority(object)

		return renderInfo
	}

	// The priority is a small integer bounded by RenderInfoMaxPriority which
	// allows us to sort them quickly using a Counting Sort algorithm.
	// The priority is cached per-object in renderPriority
	func computeRenderPriority(_ object: OsmBaseObject) -> Int {
		guard renderPriority == 0 else { return renderPriority }
		var priority: Int
		if object.modifyCount > 0 {
			priority = 33
		} else {
			switch (key, value) {
			case ("natural", "coastline"): priority = 32
			case ("natural", "water"): priority = 31
			case ("waterway", "riverbank"): priority = 30
			case ("landuse", _): priority = 29
			case ("highway", "motorway"): priority = 29
			case ("highway", "trunk"): priority = 28
			case ("highway", "motorway_link"): priority = 27
			case ("highway", "primary"): priority = 26
			case ("highway", "trunk_link"): priority = 25
			case ("highway", "secondary"): priority = 24
			case ("highway", "tertiary"): priority = 23
			case ("railway", _): priority = 22
			case ("highway", "primary_link"): priority = 21
			case ("highway", "residential"): priority = 20
			case ("highway", "raceway"): priority = 19
			case ("highway", "secondary_link"): priority = 18
			case ("highway", "tertiary_link"): priority = 17
			case ("highway", "living_street"): priority = 16
			case ("highway", "road"): priority = 15
			case ("highway", "unclassified"): priority = 14
			case ("highway", "service"): priority = 13
			case ("highway", "bus_guideway"): priority = 12
			case ("highway", "track"): priority = 11
			case ("highway", "pedestrian"): priority = 10
			case ("highway", "cycleway"): priority = 9
			case ("highway", "path"): priority = 8
			case ("highway", "bridleway"): priority = 7
			case ("highway", "footway"): priority = 6
			case ("highway", "steps"): priority = 5
			case ("highway", "construction"): priority = 4
			case ("highway", "proposed"): priority = 3
			case ("highway", _): priority = 3
			default:
				if isAddressPoint {
					priority = 1
				} else {
					priority = 2
				}
			}
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
			countOfPriority[(RenderInfoMaxPriority - 1) - obj.renderInfo!.renderPriority] += 1
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
			let index = (RenderInfoMaxPriority - 1) - obj.renderInfo!.renderPriority
			let dest = countOfPriority[index] - 1
			countOfPriority[index] = dest
			if dest < max {
				output[dest] = obj
			}
		}
		return output
	}
}
