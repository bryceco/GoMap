//
//  WayCloser.swift
//  Go Map!!
//
//  Finds paths that connect the two endpoints of an open way through existing
//  map geometry, so the user can close the way to form a polygon by tapping
//  one of the highlighted candidate paths (the "Follow / Close Area" feature,
//  analogous to iD's "F" key).
//

import UIKit

// MARK: - WayCloser

/// Manages the "Close Area" operation.
///
/// On creation it runs a breadth-first search through the OSM graph to find
/// all simple paths that connect the two endpoints of `selectedWay` through
/// other ways.  Each path is assigned a distinct colour so it can be shown as
/// a `BlinkOverlay`.  The caller stores the `WayCloser` while the mode is
/// active and asks `pathIndex(nearScreenPoint:…)` to resolve taps.
final class WayCloser {

	// MARK: ClosingPath

	struct ClosingPath {
		/// All nodes along the path, **including** the two endpoints of
		/// `selectedWay` (i.e. `nodes.first == selectedWay.nodes.last` and
		/// `nodes.last == selectedWay.nodes.first`).
		let nodes: [OsmNode]
		/// The set of ways traversed (used for display / debugging).
		let ways: Set<OsmWay>
		/// The colour to use for the marching-ants overlay.
		let color: UIColor
	}

	// MARK: Properties

	let selectedWay: OsmWay
	/// Candidate closing paths (at most `maxPaths`).
	let paths: [ClosingPath]

	// MARK: Init

	/// Returns `nil` when the way is already closed, has fewer than 2 nodes,
	/// or no connecting path is found.
	init?(selectedWay: OsmWay, mapData: OsmMapData) {
		guard !selectedWay.isClosed(),
		      selectedWay.nodes.count >= 2,
		      let firstNode = selectedWay.nodes.first,
		      let lastNode = selectedWay.nodes.last,
		      firstNode !== lastNode
		else { return nil }

		self.selectedWay = selectedWay

		let raw = Self.findClosingPaths(from: lastNode,
		                                to: firstNode,
		                                excluding: selectedWay,
		                                mapData: mapData)
		guard !raw.isEmpty else { return nil }

		self.paths = raw.prefix(Self.maxPaths).enumerated().map { index, r in
			ClosingPath(nodes: r.nodes,
			            ways: r.ways,
			            color: Self.pathColors[index % Self.pathColors.count])
		}
	}

	// MARK: Hit testing

	/// Returns the index into `paths` of the path closest to `point` (screen
	/// coordinates), or `nil` if no path is within `radius` pixels.
	func pathIndex(nearScreenPoint point: CGPoint,
	               mapTransform: MapTransform,
	               radius: CGFloat) -> Int?
	{
		var bestIndex: Int?
		var bestDist = radius

		for (i, path) in paths.enumerated() {
			for j in 1 ..< path.nodes.count {
				let p1 = OSMPoint(mapTransform.screenPoint(forLatLon: path.nodes[j - 1].latLon, birdsEye: true))
				let p2 = OSMPoint(mapTransform.screenPoint(forLatLon: path.nodes[j].latLon, birdsEye: true))
				let dist = CGFloat(OSMPoint(point).distanceToLineSegment(p1, p2))
				if dist < bestDist {
					bestDist = dist
					bestIndex = i
				}
			}
		}

		return bestIndex
	}

	// MARK: - Private constants

	private static let maxWaysPerPath = 6
	private static let maxPaths = 5
	private static let pathColors: [UIColor] = [
		UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1), // yellow
		UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 1), // cyan
		UIColor(red: 0.2, green: 1.0,  blue: 0.2, alpha: 1), // green
		UIColor(red: 1.0, green: 0.5,  blue: 0.0, alpha: 1), // orange
		UIColor(red: 1.0, green: 0.0,  blue: 1.0, alpha: 1), // magenta
	]

	// MARK: - BFS path finding

	private struct SearchState {
		let currentNode: OsmNode
		let pathNodes: [OsmNode]
		let usedWayIdents: Set<Int64>
		let usedWays: Set<OsmWay>
		let visitedNodeIdents: Set<Int64>
	}

	/// Returns up to `maxPaths` simple paths from `start` to `goal` that do
	/// not traverse `excluding`.  Each result contains the full node sequence
	/// (including `start` and `goal`) plus the set of ways used.
	private static func findClosingPaths(from start: OsmNode,
	                                     to goal: OsmNode,
	                                     excluding: OsmWay,
	                                     mapData: OsmMapData)
		-> [(nodes: [OsmNode], ways: Set<OsmWay>)]
	{
		var results: [(nodes: [OsmNode], ways: Set<OsmWay>)] = []

		var queue: [SearchState] = [
			SearchState(
				currentNode: start,
				pathNodes: [start],
				usedWayIdents: [excluding.ident],
				usedWays: [],
				visitedNodeIdents: [start.ident]
			)
		]

		while !queue.isEmpty, results.count < maxPaths {
			let state = queue.removeLast()
			guard state.usedWays.count < maxWaysPerPath else { continue }

			for way in mapData.waysContaining(state.currentNode) {
				guard !state.usedWayIdents.contains(way.ident) else { continue }
				let wayNodes = way.nodes

				// Find every index where `currentNode` appears in this way
				// and try both traversal directions from each occurrence.
				for (startIdx, node) in wayNodes.enumerated() where node === state.currentNode {
					Self.walk(wayNodes: wayNodes, from: startIdx, step: +1,
					          way: way, state: state, goal: goal,
					          queue: &queue, results: &results)
					Self.walk(wayNodes: wayNodes, from: startIdx, step: -1,
					          way: way, state: state, goal: goal,
					          queue: &queue, results: &results)
				}
			}
		}

		return results
	}

	/// Walks `wayNodes` starting from `startIdx` in direction `step` (+1 or
	/// −1).  If the goal is encountered the complete path is appended to
	/// `results`; if the end of the way segment is reached without finding the
	/// goal a new `SearchState` is enqueued for further exploration.
	private static func walk(
		wayNodes: [OsmNode],
		from startIdx: Int,
		step: Int,
		way: OsmWay,
		state: SearchState,
		goal: OsmNode,
		queue: inout [SearchState],
		results: inout [(nodes: [OsmNode], ways: Set<OsmWay>)]
	) {
		var newPath = state.pathNodes
		var newVisited = state.visitedNodeIdents
		var newUsedIdents = state.usedWayIdents
		var newUsedWays = state.usedWays
		newUsedIdents.insert(way.ident)
		newUsedWays.insert(way)

		var idx = startIdx + step
		while idx >= 0, idx < wayNodes.count {
			let node = wayNodes[idx]

			if node === goal {
				newPath.append(node)
				results.append((nodes: newPath, ways: newUsedWays))
				return
			}

			if newVisited.contains(node.ident) {
				return // cycle — abandon this branch
			}

			newPath.append(node)
			newVisited.insert(node.ident)
			idx += step
		}

		// Reached the end of this way without finding the goal.
		// Continue the search from the last accumulated node.
		guard let lastNode = newPath.last, lastNode !== state.currentNode else { return }
		queue.append(SearchState(
			currentNode: lastNode,
			pathNodes: newPath,
			usedWayIdents: newUsedIdents,
			usedWays: newUsedWays,
			visitedNodeIdents: newVisited
		))
	}
}
