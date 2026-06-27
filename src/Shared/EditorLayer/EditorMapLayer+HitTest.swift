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

	private static func HitTestLineSegment(
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

	private static func osmHitTest(node: OsmNode, location: LatLon, maxDegrees: OSMSize) -> CGFloat {
		let delta = OSMPoint(x: (location.lon - node.latLon.lon) / maxDegrees.width,
		                     y: (location.lat - node.latLon.lat) / maxDegrees.height)
		let dist = hypot(delta.x, delta.y)
		return CGFloat(dist)
	}

	// distance is in units of the hit test radius (WayHitTestRadius)
	private static func osmHitTestEnumerate(
		_ point: CGPoint,
		radius: CGFloat,
		viewPort: MapViewPort,
		objects: ContiguousArray<OsmBaseObject>,
		testNodes: Bool,
		ignoreList: [OsmBaseObject],
		block: (_ obj: OsmBaseObject, _ dist: CGFloat, _ segment: Int) -> Void)
	{
		let location = viewPort.mapTransform.latLon(forScreenPoint: point)
		let pixelsPerDegree = viewPort.pixelsPerDegree()
		let maxDegrees = OSMSize(width: Double(radius) / pixelsPerDegree.width,
		                         height: Double(radius) / pixelsPerDegree.height)
		let NODE_BIAS = 0.5 // make nodes appear closer so they can be selected

		var parentRelations: Set<OsmRelation> = []
		for object in objects {
			if object.deleted {
				continue
			}

			if let node = object as? OsmNode {
				if !ignoreList.contains(where: { $0 === node }) {
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
				if !ignoreList.contains(where: { $0 === way }) {
					var seg = 0
					let distToWay = osmHitTest(way: way, location: location, maxDegrees: maxDegrees, segment: &seg)
					if distToWay <= 1.0 {
						block(way, distToWay, seg)
						parentRelations.formUnion(Set(way.parentRelations))
					}
				}
				if testNodes {
					for node in way.nodes {
						// ignoreList can be very large sometimes, and using a regular contains()
						// ends up invoking OsmBaseObject::isEqual, which is fairly slow because
						// it requires dynamic type casting. We can speed things up by doing
						// a direct object comparison here:
						if ignoreList.contains(where: { $0 === node }) {
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
				if !ignoreList.contains(where: { $0 === relation }) {
					var bestDist: CGFloat = 10000.0
					for member in relation.members {
						if let way = member.obj as? OsmWay {
							if !ignoreList.contains(where: { $0 === way }) {
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
			viewPort: viewPort,
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

		// Order the candidate set once, so both drag-connect and tap selection (and the fallback)
		// resolve equal-distance ties the same way across taps and app launches.
		let candidates = EditorMapLayer.sortedForSelection(Array(best.keys))
		var pick: OsmBaseObject?
		if isDragConnect {
			// prefer to connecct to a way in a relation over the relation itself, which is opposite what we do when selecting by tap
			for obj in candidates {
				if obj.isRelation() == nil {
					pick = obj
					break
				}
			}
		} else {
			// performing selection by tap
			pick = EditorMapLayer.tapSelectionPick(among: candidates,
			                                       selectedRelation: selectedRelation,
			                                       hasExistingSelection: selectedPrimary != nil)
		}
		if pick == nil {
			pick = candidates.first
		}
		guard let pick = pick else { return nil }
		pSegment = best[pick]!
		return pick
	}

	/// Among the equally-close hit-test candidates, decide which object a tap should select.
	/// - When a relation is already selected we prefer one of its member ways, so successive
	///   taps drill down relation -> way -> node.
	/// - A way that carries its own interesting tags and is a member of one of the candidate
	///   *container* relations (multipolygon/boundary/waterway, e.g. a parking area that is also a
	///   multipolygon member) is preferred over that relation, so the user selects the feature they
	///   see rather than its container (#969). Scoped to container members so an unrelated tagged
	///   way never steals a relation's selection and route/turn-restriction members don't either;
	///   it applies regardless of the current selection.
	/// - Otherwise, when nothing is selected we prefer a relation (a container relation first),
	///   so multipolygons/boundaries with tag-less member ways remain selectable on the first tap.
	/// Candidates are visited in a stable id order so equal-distance ties resolve the same way
	/// across taps and app launches.
	static func tapSelectionPick(among candidates: [OsmBaseObject],
	                             selectedRelation: OsmRelation?,
	                             hasExistingSelection: Bool) -> OsmBaseObject?
	{
		// Sorted here too so the helper is deterministic in isolation (callers may already sort).
		let candidates = EditorMapLayer.sortedForSelection(candidates)

		// Drilling down: prefer a member way of the already-selected relation.
		if let relation = selectedRelation {
			for member in relation.members {
				if let obj = member.obj, candidates.contains(obj) {
					return obj
				}
			}
		}

		// Container relations under the tap (multipolygon/boundary/waterway). These are the only
		// relations a tagged member should be preferred over: routes/turn-restrictions etc. have
		// no geometry of their own, so their member ways must not steal their selection. This
		// scoping matches relationToPromote.
		let containerRelations = candidates
			.compactMap { $0 as? OsmRelation }
			.filter { $0.isMultipolygon() || $0.isBoundary() || $0.isWaterway() }

		// A tagged way that is a member of a candidate container relation selects the way itself
		// rather than its container (#969).
		for obj in candidates {
			if let way = obj as? OsmWay,
			   way.hasInterestingTags(),
			   containerRelations.contains(where: { $0.member(byRef: way) != nil })
			{
				return way
			}
		}

		// Nothing selected: prefer a relation so tag-less members don't hijack the first tap away
		// from their container. Prefer a container relation (as relationToPromote does), then any.
		if !hasExistingSelection {
			if let container = containerRelations.first {
				return container
			}
			for obj in candidates {
				if obj.isRelation() != nil {
					return obj
				}
			}
		}

		// Deterministic fallback over the equal-distance set.
		return candidates.first
	}

	/// Stable ordering of hit-test candidates by OSM id, so equal-distance ties resolve the same
	/// way across taps and app launches.
	static func sortedForSelection(_ candidates: [OsmBaseObject]) -> [OsmBaseObject] {
		candidates.sorted {
			($0.extendedIdentifier.ident, $0.extendedIdentifier.type.rawValue)
				< ($1.extendedIdentifier.ident, $1.extendedIdentifier.type.rawValue)
		}
	}

	// return all nearby objects
	func osmHitTestMultiple(_ point: CGPoint, radius: CGFloat) -> [OsmBaseObject] {
		var objectSet: Set<OsmBaseObject> = []
		EditorMapLayer.osmHitTestEnumerate(
			point,
			radius: radius,
			viewPort: viewPort,
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
		                                   viewPort: viewPort,
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
