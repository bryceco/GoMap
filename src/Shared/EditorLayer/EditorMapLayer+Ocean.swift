//
//  EditorMapLayer+Ocean.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/21/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import Foundation
import UIKit

extension OSMPoint: Hashable {
	public func hash(into hasher: inout Hasher) {
		hasher.combine(x)
		hasher.combine(y)
	}
}

extension EditorMapLayer {
	private enum CoastType: Int {
		case landOnLeft // it's tagged natural=coastline
		case outer // outer member of natural=water relation
		case inner // inner member of natural=water relation
		case unknown
	}

	private struct Coastline<T: Equatable>: Equatable,
		CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
	{
		var points: [T]
		var coastType: CoastType

		var description: String {
			return "\(coastType): \(points.first!) - \(points.last!)"
		}

		var debugDescription: String {
			return "\(coastType): \(points.first!) - \(points.last!)"
		}

		var customMirror: Mirror {
#if true
			return Mirror(self, children: [:])
#else
			return Mirror(self,
			              children: ["coastType": coastType,
			                         "points": [points.first!, points.last!]])
#endif
		}
	}

	private static func AppendNodes(to list: inout [LatLon], from: [LatLon], addToBack: Bool, reverseNodes: Bool) {
		let nodes = reverseNodes ? from.reversed() : from
		if addToBack {
			// insert at back of list
			list.append(contentsOf: nodes.dropFirst())
		} else {
			// insert at front of list
			list.insert(contentsOf: nodes.dropLast(), at: 0)
		}
	}

	private static func IsPointInRect(_ pt: CGPoint, rect: CGRect) -> Bool {
		let delta = 0.0001
		if pt.x < rect.origin.x - delta {
			return false
		}
		if pt.x > rect.origin.x + rect.size.width + delta {
			return false
		}
		if pt.y < rect.origin.y - delta {
			return false
		}
		if pt.y > rect.origin.y + rect.size.height + delta {
			return false
		}
		return true
	}

	private enum SIDE {
		case LEFT, TOP, RIGHT, BOTTOM
	}

	private static func WallForPoint(_ pt: CGPoint, rect: CGRect) -> SIDE {
		let delta = 0.01
		if fabs(pt.x - rect.origin.x) < delta {
			return .LEFT
		}
		if fabs(pt.y - rect.origin.y) < delta {
			return .TOP
		}
		if fabs(pt.x - rect.origin.x - rect.size.width) < delta {
			return .RIGHT
		}
		if fabs(pt.y - rect.origin.y - rect.size.height) < delta {
			return .BOTTOM
		}
		fatalError()
	}

	private static func RotateLoop(_ loop: inout [CGPoint], viewRect: CGRect) -> Bool {
		if loop.count < 4 {
			return false // bad loop
		}
		if loop[0] != loop.last! {
			return false // bad loop
		}
		loop.removeLast()
		var index = 0
		for point in loop {
			if !viewRect.contains(point) {
				break
			}
			index += 1
			if index >= loop.count {
				index = -1
				break
			}
		}
		if index > 0 {
			let set = 0..<index
			let a = loop[set]
			loop.removeSubrange(set)
			loop.append(contentsOf: a)
		}
		loop.append(loop[0])
		return index >= 0
	}

	static func ClipLineToRect(p1: CGPoint, p2: CGPoint, rect: CGRect) -> [CGPoint] {
		if p1.x.isInfinite || p2.x.isInfinite {
			return []
		}

		let top = rect.origin.y
		let bottom = rect.origin.y + rect.size.height
		let left = rect.origin.x
		let right = rect.origin.x + rect.size.width

		let dx = p2.x - p1.x
		let dy = p2.y - p1.y

		// get distances in terms of 0..1
		// we compute crossings for not only the rectangles walls but also the projections of the walls outside the rectangle,
		// so 4 possible interesection points
		var cross = [Double]()
		if dx != 0 {
			let vLeft = (left - p1.x) / dx
			let vRight = (right - p1.x) / dx
			if vLeft >= 0, vLeft <= 1 {
				cross.append(vLeft)
			}
			if vRight >= 0, vRight <= 1 {
				cross.append(vRight)
			}
		}
		if dy != 0 {
			let vTop = (top - p1.y) / dy
			let vBottom = (bottom - p1.y) / dy
			if vTop >= 0, vTop <= 1 {
				cross.append(vTop)
			}
			if vBottom >= 0, vBottom <= 1 {
				cross.append(vBottom)
			}
		}

		// sort crossings according to distance from p1
		cross.sort()

		// get the points that are actually inside the rect (max 2)
		let pts = cross.map { CGPoint(x: p1.x + $0 * dx, y: p1.y + $0 * dy) }.filter { IsPointInRect($0, rect: rect) }

		return pts
	}

	// input is an array of OsmWay
	// output is an array of arrays of OsmNode
	// take a list of ways and return a new list of ways with contiguous ways joined together.
	private static func joinConnectedWays(_ origList: [Coastline<LatLon>]) -> [Coastline<LatLon>] {
		// connect ways together forming congiguous runs
		var origList = origList.filter({ $0.points.count > 1 })
		var newList = [Coastline<LatLon>]()
		while var parent = origList.popLast() {
			// find all connected segments
			while true {
				let firstNode = parent.points[0]
				let lastNode = parent.points.last!
				if firstNode == lastNode {
					break
				}
				// find a way adjacent to current list
				var found: (index: Int, back: Bool, reverse: Bool)?
				for index in origList.indices {
					let way = origList[index]
					guard way.coastType == parent.coastType else {
						continue
					}
					if lastNode == way.points[0] {
						found = (index, true, false)
						break
					}
					if lastNode == way.points.last {
						found = (index, true, true)
						break
					}
					if firstNode == way.points.last {
						found = (index, false, false)
						break
					}
					if firstNode == way.points[0] {
						found = (index, false, true)
						break
					}
				}
				guard let found = found else {
					break // didn't find anything to connect to
				}
				let sibling = origList[found.index]
				Self.AppendNodes(to: &parent.points,
				                 from: sibling.points,
				                 addToBack: found.back,
				                 reverseNodes: found.reverse)
				if sibling.coastType.rawValue < parent.coastType.rawValue {
					// Sibling is more accurate so inherit it's value
					parent.coastType = sibling.coastType
					if found.reverse {
						// if the sibling was reversed we need to reverse everything to match it
						parent.points.reverse()
					}
				}
				origList.remove(at: found.index)
			}
			newList.append(parent)
		}
		return newList
	}

	private func convertLatLonToScreenPoint(_ latLon: LatLon) -> CGPoint {
		return owner.mapTransform.screenPoint(forLatLon: latLon, birdsEye: false)
	}

	private static func visibleSegmentsOfWay(_ way: [CGPoint], inView viewRect: CGRect) -> [[CGPoint]] {
		// trim nodes in outlines to only internal paths
		var way = way
		var newWays = [[CGPoint]]()

		var first = true
		var prevInside = false
		let isLoop = way[0] == way.last!
		var prevPoint = CGPoint(x: 0, y: 0)
		var trimmedSegment: [CGPoint]?

		if isLoop {
			// rotate loop to ensure start/end point is outside viewRect
			let ok = Self.RotateLoop(&way, viewRect: viewRect)
			if !ok {
				// entire loop is inside view
				return [way]
			}
		}

		for pt in way {
			let isInside = viewRect.contains(pt)
			if first {
				first = false
			} else {
				var isEntry = false
				var isExit = false
				if prevInside {
					if isInside {
						// still inside
					} else {
						// moved to outside
						isExit = true
					}
				} else {
					if isInside {
						// moved inside
						isEntry = true
					} else {
						// if previous and current are both outside maybe we intersected
						if viewRect.intersectsLineSegment(prevPoint, pt),
						   !pt.x.isInfinite,
						   !prevPoint.x.isInfinite
						{
							isEntry = true
							isExit = true
						} else {
							// still outside
						}
					}
				}

				let pts = (isEntry || isExit) ? Self.ClipLineToRect(p1: prevPoint, p2: pt, rect: viewRect) : nil
				if isEntry {
					// start tracking trimmed segment
					let v = pts![0]
					trimmedSegment = [v]
				}
				if isExit {
					// end of trimmed segment. If the way began inside the viewrect then trimmedSegment is nil and gets ignored
					if trimmedSegment != nil {
						let v = pts!.last!
						trimmedSegment!.append(v)
						newWays.append(trimmedSegment!)
						trimmedSegment = nil
					}
				} else if isInside {
					// internal node for trimmed segment
					if trimmedSegment != nil {
						trimmedSegment!.append(pt)
					}
				}
			}
			prevPoint = pt
			prevInside = isInside
		}
		return newWays
	}

	private static func addPointList(_ list: [CGPoint], toPath path: CGMutablePath) {
		var first = true
		for pt in list {
			if pt.x.isInfinite {
				break
			}
			if first {
				first = false
				path.move(to: pt)
			} else {
				path.addLine(to: pt)
			}
		}
	}

	public func getOceanLayer(_ objectList: ContiguousArray<OsmBaseObject>) -> CAShapeLayer? {
		// get all coastline ways
		let landuseCount = 10
		var osmWays = [(way: OsmWay, coastType: CoastType)]()

		var landPoints = [CGPoint]()

		for object in objectList {
			guard !(object is OsmNode) else {
				continue
			}

#if false
			// record objects that we can use later to distinguish ocean from land
			if landPoints.count < landuseCount,
			   let way = object as? OsmWay,
			   way.nodes.count > 1,
			   way.tags["highway"] != nil || way.tags["building"] != nil
			{
				for n in [way.nodes.first!, way.nodes.last!, way.nodes[way.nodes.count / 2]] {
					let latLon = convertLatLonToScreenPoint(n.latLon)
					if bounds.contains(latLon) {
						landPoints.append(latLon)
						break
					}
				}
			}
#endif

			guard object.isCoastline() else {
				continue
			}

			if let way = object as? OsmWay,
			   way.nodes.count >= 2
			{
				let isCoastline = object.tags["natural"] == "coastline"
				osmWays.append((way, coastType: isCoastline ? .landOnLeft : .unknown))
			} else if let relation = object as? OsmRelation {
				for member in relation.members {
					guard let way = member.obj as? OsmWay,
					      way.nodes.count >= 2
					else { continue }

					if member.role == "outer" {
						osmWays.append((way, .outer))
					} else if member.role == "inner" {
						osmWays.append((way, .inner))
					} else {
						// skip
					}
				}
			}
		} // end of loop filtering objects
		if osmWays.count == 0 {
			return nil
		}

		// remove any objects that are duplicated, prefering known coastline types
		osmWays.sort(by: { a, b in a.coastType.rawValue < b.coastType.rawValue })
		var latLonWays = [Coastline<LatLon>]()
		var seen = Set<OsmWay>()
		for item in osmWays {
			guard seen.insert(item.way).inserted else {
				continue
			}
			latLonWays.append(Coastline<LatLon>(points: item.way.nodes.map { $0.latLon },
			                                    coastType: item.coastType))
		}

		// connect ways together forming contiguous runs
		latLonWays = Self.joinConnectedWays(latLonWays.map { $0 })

		// convert lists of nodes to screen points
		var screenWays = latLonWays.map { way in
			Coastline<CGPoint>(points: way.points.map { convertLatLonToScreenPoint($0) },
			                   coastType: way.coastType)
		}

		// Delete loops with a degenerate number of nodes. These are typically data errors:
		screenWays = screenWays.filter { $0.points.count >= 4 || $0.points[0] != $0.points.last! }

		// ensure that closed outer ways are clockwise and inner are counter-clockwise
		for index in screenWays.indices {
			let way = screenWays[index]
			if way.points[0] == way.points.last! {
				// Its a closed loop
				let reverse: Bool
				switch way.coastType {
				case .outer:
					reverse = !(IsClockwisePolygon(way.points) ?? true)
				case .inner:
					reverse = IsClockwisePolygon(way.points) ?? false
				case .landOnLeft, .unknown:
					reverse = false
				}
				if reverse {
					screenWays[index].points.reverse()
				}
			} else {
				if way.coastType != .landOnLeft {
					screenWays[index].coastType = .unknown
				}
			}
		}

		// trim nodes in segments to only visible paths
		let viewRect = bounds
		var visibleSegments = screenWays.flatMap { way in
			Self.visibleSegmentsOfWay(way.points, inView: viewRect)
				.map { Coastline<CGPoint>(points: $0, coastType: way.coastType) }
		}
		if visibleSegments.count == 0 {
			// nothing is on screen
			return nil
		}

		// pull islands (loops) into a separate list
		var islands = [[CGPoint]]()
		visibleSegments.removeAll(where: { a -> Bool in
			if a.points[0] == a.points.last! {
				islands.append(a.points)
				return true
			} else {
				return false
			}
		})

		// get list of all external points
		var pointSet: Set<CGPoint> = []
		var entryDict: [CGPoint: Coastline<CGPoint>] = [:]
		for way in visibleSegments {
			pointSet.insert(way.points[0])
			pointSet.insert(way.points.last!)
			entryDict[way.points[0]] = way
		}

		// Sort points clockwise. When we see a way that exits the view bounding box
		// we can quickly find the next way that reenters the bounding box.
		let viewCenter = viewRect.center()
		let borderPoints = pointSet.sorted(by: { pt1, pt2 -> Bool in
			let ang1 = atan2(pt1.y - viewCenter.y, pt1.x - viewCenter.x)
			let ang2 = atan2(pt2.y - viewCenter.y, pt2.x - viewCenter.x)
			let angle = ang1 - ang2
			return angle < 0
		})

		// sort so coastlines come first
		visibleSegments.sort { a, b in a.coastType.rawValue < b.coastType.rawValue }

		// now have a set of discontiguous arrays of coastline nodes.
		// Draw segments adding points at screen corners to connect them
		let path = CGMutablePath()
		while let firstOutline = visibleSegments.popLast() {
			var exit = firstOutline.points.last!

			Self.addPointList(firstOutline.points, toPath: path)

			while true {
				// find next point following exit point
				var nextOutline = entryDict[exit] // check if exit point is also entry point
				if nextOutline == nil { // find next entry point following exit point
					let exitIndex = borderPoints.firstIndex(of: exit)!
					let entryIndex = (exitIndex + 1) % borderPoints.count
					nextOutline = entryDict[borderPoints[entryIndex]]
				}
				guard let nextOutline = nextOutline else {
					return nil
				}
				let entry = nextOutline.points[0]

				// connect exit point to entry point following clockwise borders
				if true {
					var point1 = exit
					let point2 = entry
					var wall1 = Self.WallForPoint(point1, rect: viewRect)
					let wall2 = Self.WallForPoint(point2, rect: viewRect)

					wall_loop: while true {
						switch wall1 {
						case .LEFT:
							if wall2 == .LEFT, point1.y > point2.y {
								break wall_loop
							}
							point1 = CGPoint(x: viewRect.origin.x,
							                 y: viewRect.origin.y)
							path.addLine(to: point1)
							fallthrough
						case .TOP:
							if wall2 == .TOP, point1.x < point2.x {
								break wall_loop
							}
							point1 = CGPoint(x: viewRect.origin.x + viewRect.size.width,
							                 y: viewRect.origin.y)
							path.addLine(to: point1)
							fallthrough
						case .RIGHT:
							if wall2 == .RIGHT, point1.y < point2.y {
								break wall_loop
							}
							point1 = CGPoint(x: viewRect.origin.x + viewRect.size.width,
							                 y: viewRect.origin.y + viewRect.size.height)
							path.addLine(to: point1)
							fallthrough
						case .BOTTOM:
							if wall2 == .BOTTOM, point1.x > point2.x {
								break wall_loop
							}
							point1 = CGPoint(x: viewRect.origin.x,
							                 y: viewRect.origin.y + viewRect.size.height)
							path.addLine(to: point1)
							wall1 = .LEFT
						}
					}
				}

				if nextOutline == firstOutline {
					break
				}

				if !visibleSegments.contains(nextOutline) {
					return nil
				}
				for pt in nextOutline.points {
					path.addLine(to: pt)
				}

				exit = nextOutline.points.last!
				visibleSegments.removeAll { $0 == nextOutline }
			}
		}

		// draw islands
		for island in islands {
			Self.addPointList(island, toPath: path)
		}

#if false
		let insideCount = landPoints.reduce(0, { prev, point in
			prev + (path.contains(point) ? 1 : 0)
		})

		// if no coastline then draw water everywhere
		print("\(insideCount) < \(landPoints.count - insideCount)")
		if insideCount < landPoints.count - insideCount {
			path.addRect(viewRect)
		}
#endif

		let layer = CAShapeLayer()
		layer.path = path
		layer.frame = bounds
		layer.bounds = bounds
		layer.fillColor = UIColor(red: 0, green: 0, blue: 1, alpha: 0.1).cgColor
		layer.strokeColor = UIColor.red.cgColor
		layer.lineWidth = 2.0
		//		layer.zPosition		= Z_OCEAN;	// FIXME

		return layer
	}
}
