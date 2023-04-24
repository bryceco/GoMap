//
//  EditorMapLayer+HitTest.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import CoreGraphics
import CoreLocation

extension EditorMapLayer {
	// MARK: Hit Testing

	@inline(__always) private static func HitTestLineSegment(
		_ point: LatLon,
		_ maxDegrees: OSMSize,
		_ coord1: LatLon,
		_ coord2: LatLon) -> CGFloat
	{
		var line1 = OSMPoint(x: coord1.lon - point.lon, y: coord1.lat - point.lat)
		var line2 = OSMPoint(x: coord2.lon - point.lon, y: coord2.lat - point.lat)
		let pt = OSMPoint(x: 0, y: 0)

		// adjust scale
		line1.x /= maxDegrees.width
		line1.y /= maxDegrees.height
		line2.x /= maxDegrees.width
		line2.y /= maxDegrees.height

		let dist = pt.distanceToLineSegment(line1, line2)
		return CGFloat(dist)
	}

	@inline(__always) private static func HitTestLineSegment(
		_ point: CGPoint,
		_ maxPixels: CGFloat,
		_ coord1: CGPoint,
		_ coord2: CGPoint) -> CGFloat
	{
		let line1 = OSMPoint(x: Double((coord1.x - point.x) / maxPixels), y: Double((coord1.y - point.y) / maxPixels))
		let line2 = OSMPoint(x: Double((coord2.x - point.x) / maxPixels), y: Double((coord2.y - point.y) / maxPixels))
		let pt = OSMPoint(x: 0, y: 0)
		let dist = pt.distanceToLineSegment(line1, line2)
		return CGFloat(dist)
	}

	private static func osmHitTest(way: OsmWay, location: LatLon, maxDegrees: OSMSize, segment: inout Int) -> CGFloat {
		var previous = LatLon.zero
		var seg = -1
		var bestDist: CGFloat = 1_000000
		for node in way.nodes {
			if seg >= 0 {
				let dist = HitTestLineSegment(location, maxDegrees, node.latLon, previous)
				if dist < bestDist {
					bestDist = dist
					segment = seg
				}
			}
			seg += 1
			previous = node.latLon
		}
		return bestDist
	}

	private static func osmHitTest(
		way: OsmWay,
		location: CGPoint,
		maxPixels: CGFloat,
		mapTransform: MapTransform,
		segment: inout Int) -> CGFloat
	{
		var previous = mapTransform.screenPoint(forLatLon: way.nodes.first!.latLon, birdsEye: true)
		var seg = 0
		var bestDist: CGFloat = 1_000000
		for node in way.nodes.dropFirst() {
			let pt = mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
			let dist = HitTestLineSegment(location, maxPixels, pt, previous)
			if dist < bestDist {
				bestDist = dist
				segment = seg
			}
			seg += 1
			previous = pt
		}
		return bestDist
	}

	private static func osmHitTest(node: OsmNode, location: LatLon, maxDegrees: OSMSize) -> CGFloat {
		let delta = OSMPoint(x: (location.lon - node.latLon.lon) / maxDegrees.width,
		                     y: (location.lat - node.latLon.lat) / maxDegrees.height)
		let dist = hypot(delta.x, delta.y)
		return CGFloat(dist)
	}

	private static func osmHitTest(node: OsmNode, location: CGPoint, maxPixels: CGFloat,
	                               mapTransform: MapTransform) -> CGFloat
	{
		let nodePt = mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
		let delta = CGPoint(x: location.x - nodePt.x,
		                    y: location.y - nodePt.y)
		let dist = hypot(delta.x, delta.y) / maxPixels
		return dist
	}

	// distance is in units of the hit test radius (WayHitTestRadius)
	private static func osmHitTestEnumerate(
		_ point: CGPoint,
		radius: CGFloat,
		owner: EditorMapLayerOwner,
		objects: ContiguousArray<OsmBaseObject>,
		testNodes: Bool,
		ignoreList: [OsmBaseObject],
		block: @escaping (_ obj: OsmBaseObject, _ dist: CGFloat, _ segment: Int) -> Void)
	{
		if MapTransform.projection == .polarSouth {
			// need to hittest using screen coordinates rather than lat/lon
			return osmHitTestEnumerate(
				point,
				radius: radius,
				mapTransform: owner.mapTransform,
				objects: objects,
				testNodes: testNodes,
				ignoreList: ignoreList,
				block: block)
		}

		let location = owner.mapTransform.latLon(forScreenPoint: point)
		let p2 = owner.mapTransform.latLon(forScreenPoint: CGPoint(x: point.x + 1, y: point.y + 2))
		let pixelsPerDegree = OSMSize(width: 1.0 / Double(fabs(p2.lon - location.lon)),
		                              height: 1.0 / Double(fabs(p2.lat - location.lat)))
		let maxDegrees = OSMSize(width: Double(radius) / pixelsPerDegree.width,
		                         height: Double(radius) / pixelsPerDegree.height)
		let NODE_BIAS = 0.5 // make nodes appear closer so they can be selected

		var parentRelations: Set<OsmRelation> = []
		for object in objects {
			if object.deleted {
				continue
			}

			if let node = object as? OsmNode {
				if !ignoreList.contains(node) {
					if testNodes || node.wayCount == 0 {
						var dist = osmHitTest(node: node, location: location, maxDegrees: maxDegrees)
						dist *= CGFloat(NODE_BIAS)
						if dist <= 1.0 {
							block(node, dist, 0)
							parentRelations.formUnion(Set(node.parentRelations))
						}
					}
				}
			} else if let way = object as? OsmWay {
				if !ignoreList.contains(way) {
					var seg = 0
					let distToWay = osmHitTest(way: way, location: location, maxDegrees: maxDegrees, segment: &seg)
					if distToWay <= 1.0 {
						block(way, distToWay, seg)
						parentRelations.formUnion(Set(way.parentRelations))
					}
				}
				if testNodes {
					for node in way.nodes {
						if ignoreList.contains(node) {
							continue
						}
						var dist = osmHitTest(node: node, location: location, maxDegrees: maxDegrees)
						dist *= CGFloat(NODE_BIAS)
						if dist < 1.0 {
							block(node, dist, 0)
							parentRelations.formUnion(Set(node.parentRelations))
						}
					}
				}
			} else if let relation = object as? OsmRelation,
			          relation.isMultipolygon()
			{
				if !ignoreList.contains(relation) {
					var bestDist: CGFloat = 10000.0
					for member in relation.members {
						if let way = member.obj as? OsmWay {
							if !ignoreList.contains(way) {
								if (member.role == "inner") || (member.role == "outer") {
									var seg = 0
									let dist = osmHitTest(
										way: way,
										location: location,
										maxDegrees: maxDegrees,
										segment: &seg)
									if dist < bestDist {
										bestDist = dist
									}
								}
							}
						}
					}
					if bestDist <= 1.0 {
						block(relation, bestDist, 0)
					}
				}
			}
		}
		for relation in parentRelations {
			// for non-multipolygon relations, like turn restrictions
			block(relation, 1.0, 0)
		}
	}

	// distance is in units of the hit test radius (WayHitTestRadius)
	private static func osmHitTestEnumerate(
		_ point: CGPoint,
		radius: CGFloat,
		mapTransform: MapTransform,
		objects: ContiguousArray<OsmBaseObject>,
		testNodes: Bool,
		ignoreList: [OsmBaseObject],
		block: @escaping (_ obj: OsmBaseObject, _ dist: CGFloat, _ segment: Int) -> Void)
	{
		let NODE_BIAS = 0.5 // make nodes appear closer so they can be selected

		var parentRelations: Set<OsmRelation> = []
		for object in objects {
			if object.deleted {
				continue
			}

			if let node = object as? OsmNode {
				if !ignoreList.contains(node) {
					if testNodes || node.wayCount == 0 {
						var dist = osmHitTest(
							node: node,
							location: point,
							maxPixels: radius,
							mapTransform: mapTransform)
						dist *= CGFloat(NODE_BIAS)
						if dist <= 1.0 {
							block(node, dist, 0)
							parentRelations.formUnion(Set(node.parentRelations))
						}
					}
				}
			} else if let way = object as? OsmWay {
				if !ignoreList.contains(way) {
					var seg = 0
					let distToWay = osmHitTest(
						way: way,
						location: point,
						maxPixels: radius,
						mapTransform: mapTransform,
						segment: &seg)
					if distToWay <= 1.0 {
						block(way, distToWay, seg)
						parentRelations.formUnion(Set(way.parentRelations))
					}
				}
				if testNodes {
					for node in way.nodes {
						if ignoreList.contains(node) {
							continue
						}
						var dist = osmHitTest(
							node: node,
							location: point,
							maxPixels: radius,
							mapTransform: mapTransform)
						dist *= CGFloat(NODE_BIAS)
						if dist < 1.0 {
							block(node, dist, 0)
							parentRelations.formUnion(Set(node.parentRelations))
						}
					}
				}
			} else if let relation = object as? OsmRelation,
			          relation.isMultipolygon()
			{
				if !ignoreList.contains(relation) {
					var bestDist: CGFloat = 10000.0
					for member in relation.members {
						if let way = member.obj as? OsmWay {
							if !ignoreList.contains(way) {
								if (member.role == "inner") || (member.role == "outer") {
									var seg = 0
									let dist = osmHitTest(
										way: way,
										location: point,
										maxPixels: radius,
										mapTransform: mapTransform,
										segment: &seg)
									if dist < bestDist {
										bestDist = dist
									}
								}
							}
						}
					}
					if bestDist <= 1.0 {
						block(relation, bestDist, 0)
					}
				}
			}
		}
		for relation in parentRelations {
			// for non-multipolygon relations, like turn restrictions
			block(relation, 1.0, 0)
		}
	}

	// default hit test when clicking on the map, or drag-connecting
	func osmHitTest(_ point: CGPoint,
	                radius: CGFloat,
	                isDragConnect: Bool,
	                ignoreList: [OsmBaseObject],
	                segment pSegment: inout Int) -> OsmBaseObject?
	{
		if isHidden {
			return nil
		}

		var bestDist: CGFloat = 1_000000
		var best: [OsmBaseObject: Int] = [:]
		EditorMapLayer.osmHitTestEnumerate(
			point,
			radius: radius,
			owner: owner,
			objects: shownObjects,
			testNodes: isDragConnect,
			ignoreList: ignoreList,
			block: { obj, dist, segment in
				if dist < bestDist {
					bestDist = dist
					best.removeAll()
					best[obj] = segment
				} else if dist == bestDist {
					best[obj] = segment
				}
			})
		if bestDist > 1.0 {
			return nil
		}

		var pick: OsmBaseObject?
		if isDragConnect {
			// prefer to connecct to a way in a relation over the relation itself, which is opposite what we do when selecting by tap
			for obj in best.keys {
				if obj.isRelation() == nil {
					pick = obj
					break
				}
			}
		} else {
			// performing selection by tap
			if pick == nil,
			   let relation = selectedRelation
			{
				// pick a way that is a member of the relation if possible
				for member in relation.members {
					if let obj = member.obj,
					   best[obj] != nil
					{
						pick = obj
						break
					}
				}
			}
			if pick == nil, selectedPrimary == nil {
				// nothing currently selected, so prefer relations
				for obj in best.keys {
					if obj.isRelation() != nil {
						pick = obj
						break
					}
				}
			}
		}
		if pick == nil {
			pick = best.first!.key
		}
		guard let pick = pick else { return nil }
		pSegment = best[pick]!
		return pick
	}

	// return all nearby objects
	func osmHitTestMultiple(_ point: CGPoint, radius: CGFloat) -> [OsmBaseObject] {
		var objectSet: Set<OsmBaseObject> = []
		EditorMapLayer.osmHitTestEnumerate(
			point,
			radius: radius,
			owner: owner,
			objects: shownObjects,
			testNodes: true,
			ignoreList: [],
			block: { obj, _, _ in
				objectSet.insert(obj)
			})
		var objectList = Array(objectSet)
		objectList.sort(by: { o1, o2 in
			let diff1 = (o1.hasInterestingTags() ? 1 : 0) - (o2.hasInterestingTags() ? 1 : 0)
			if diff1 != 0 {
				return diff1 > 0
			}
			let diff = (o1 is OsmRelation ? 1 : o1 is OsmWay ? 2 : 0)
				- (o2 is OsmRelation ? 1 : o2 is OsmWay ? 2 : 0)
			if diff != 0 {
				return -diff < 0
			}
			let diff2 = o1.ident - o2.ident
			return diff2 < 0
		})
		return objectList
	}

	// drill down to a node in the currently selected way
	func osmHitTestNode(inSelectedWay point: CGPoint, radius: CGFloat) -> OsmNode? {
		guard let selectedWay = selectedWay else {
			return nil
		}
		var hit: OsmNode?
		var bestDist: CGFloat = 1_000000
		EditorMapLayer.osmHitTestEnumerate(point,
		                                   radius: radius,
		                                   owner: owner,
		                                   objects: ContiguousArray<OsmBaseObject>(selectedWay.nodes),
		                                   testNodes: true,
		                                   ignoreList: [],
		                                   block: { obj, dist, _ in
		                                   	if dist < bestDist {
		                                   		bestDist = dist
		                                   		hit = (obj as! OsmNode)
		                                   	}
		                                   })
		if bestDist <= 1.0 {
			return hit
		}
		return nil
	}
}
