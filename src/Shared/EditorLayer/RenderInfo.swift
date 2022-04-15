//
//  RenderInfo.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/4/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

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
	var areaColor: UIColor?

	var description: String {
		return "\(type(of: self)): \(key)=\(value ?? "")"
	}

	func isAddressPoint() -> Bool {
		return self === g_AddressRender
	}

	class func color(forHexString text: String?) -> UIColor? {
		guard let text = text else {
			return nil
		}
		assert(text.count == 6)

		var r: CGFloat = 0
		var g: CGFloat = 0
		var b: CGFloat = 0
		let start = text.index(text.startIndex, offsetBy: 0)
		let hexColor = String(text[start...])
		if hexColor.count == 6 {
			let scanner = Scanner(string: hexColor)
			var hexNumber: UInt64 = 0
			if scanner.scanHexInt64(&hexNumber) {
				r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255.0
				g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255.0
				b = CGFloat((hexNumber & 0x0000FF) >> 0) / 255.0
			}
		}

		if #available(iOS 13.0, *) { // Dark Mode
			let color = UIColor(dynamicProvider: { traitCollection in
				if traitCollection.userInterfaceStyle == .dark {
					// lighten colors for dark mode
					let delta: CGFloat = 0.3
					let r3 = r * (1 - delta) + delta
					let g3 = g * (1 - delta) + delta
					let b3 = b * (1 - delta) + delta
					return UIColor(red: r3, green: g3, blue: b3, alpha: 1.0)
				}
				return UIColor(red: r, green: g, blue: b, alpha: 1.0)
			})
			return color
		} else {
			return UIColor(red: r, green: g, blue: b, alpha: 1.0)
		}
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
				if prevSum >= k || newSum >= 2 * k {
					max = prevSum
				}
			}
		}
		let tmp = OsmNode(asUserCreated: "")
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
	var keyDict: [String: [String: RenderInfo]] = [:]

	static let shared = RenderInfoDatabase()

	class func readConfiguration() -> [RenderInfo] {
		var text = NSData(contentsOfFile: "RenderInfo.json") as Data?
		if text == nil {
			if let path = Bundle.main.path(forResource: "RenderInfo", ofType: "json") {
				text = NSData(contentsOfFile: path) as Data?
			}
		}
		var features: [String: [String: Any]] = [:]
		do {
			if let text = text {
				features = try JSONSerialization.jsonObject(with: text, options: []) as? [String: [String: Any]] ?? [:]
			}
		} catch {}

		var renderList: [RenderInfo] = []

		for (feature, dict) in features {
			let keyValue = feature.components(separatedBy: "/")
			let render = RenderInfo()
			render.key = keyValue[0]
			render.value = keyValue.count > 1 ? keyValue[1] : ""
			render.lineColor = RenderInfo.color(forHexString: dict["lineColor"] as? String)
			render.areaColor = RenderInfo.color(forHexString: dict["areaColor"] as? String)
			render.lineWidth = CGFloat((dict["lineWidth"] as? NSNumber ?? NSNumber(value: 0)).doubleValue)
			renderList.append(render)
		}
		return renderList
	}

	required init() {
		allFeatures = RenderInfoDatabase.readConfiguration()
		keyDict = [:]
		for tag: RenderInfo in allFeatures {
			var valDict = keyDict[tag.key]
			if valDict == nil {
				valDict = [tag.value ?? "": tag]
			} else {
				valDict![tag.value ?? ""] = tag
			}
			keyDict[tag.key] = valDict
		}
	}

	func renderInfoForObject(_ object: OsmBaseObject) -> RenderInfo {
		var tags = object.tags
		// if the object is part of a rendered relation than inherit that relation's tags
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

		// try exact match
		var bestRender: RenderInfo?
		var bestIsDefault = false
		var bestCount = 0
		for (key, value) in tags {
			guard let valDict = keyDict[key] else { continue }
			var isDefault = false
			var render = valDict[value]
			if render == nil {
				render = valDict[""]
				if render != nil {
					isDefault = true
				}
			}
			guard let render = render else { continue }

			let count: Int = ((render.lineColor != nil) ? 1 : 0) + ((render.areaColor != nil) ? 1 : 0)
			if bestRender == nil || (bestIsDefault && !isDefault) || (count > bestCount) {
				bestRender = render
				bestCount = count
				bestIsDefault = isDefault
				continue
			}
		}
		if let bestRender = bestRender {
			return bestRender
		}

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
