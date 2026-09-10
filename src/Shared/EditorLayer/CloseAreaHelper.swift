//
//  CloseAreaHelper.swift
//  Go Map!!
//
//  Finds paths that connect the two endpoints of an open way through existing
//  map geometry, so the user can close the way to form a polygon by tapping
//  one of the highlighted candidate paths (the "Follow / Close Area" feature,
//  analogous to iD's "F" key).
//

import Foundation

// MARK: - CloseAreaHelper

/// Manages the "Close Area" operation.
///
/// On creation it runs a breadth-first search through the OSM graph to find
/// all simple paths that connect the two endpoints of `selectedWay` through
/// other ways.
final class CloseAreaHelper {

	// MARK: ConnectingPath

	struct ConnectingPath {
		/// All nodes along the path, **including** the two endpoints of
		/// `selectedWay` (i.e. `nodes.first == selectedWay.nodes.last` and
		/// `nodes.last == selectedWay.nodes.first`).
		let nodes: [OsmNode]
	}

	// MARK: Properties

	let selectedWay: OsmWay
	/// Candidate closing paths (at most `maxPaths`).
	let paths: [ConnectingPath]

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

		let raw = Self.findConnectingPaths(from: lastNode,
		                                   to: firstNode,
		                                   excluding: selectedWay,
		                                   mapData: mapData)
		guard !raw.isEmpty else { return nil }

		self.paths = raw.prefix(Self.maxPaths).map { ConnectingPath(nodes: $0) }
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
			for j in 1..<path.nodes.count {
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
	private static let maxPaths = 10

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
	private static func findConnectingPaths(from start: OsmNode,
	                                        to goal: OsmNode,
	                                        excluding: OsmWay,
	                                        mapData: OsmMapData)
		-> [[OsmNode]]
	{
		var results: [[OsmNode]] = []

		var queue: [SearchState] = [
			SearchState(
				currentNode: start,
				pathNodes: [start],
				usedWayIdents: [excluding.ident],
				usedWays: [],
				visitedNodeIdents: [start.ident])
		]

		while !queue.isEmpty, results.count < maxPaths {
			let state = queue.removeLast()
			guard state.usedWays.count < maxWaysPerPath else {
				print("too many ways in path")
				continue
			}

			for way in mapData.waysContaining(state.currentNode) {
				guard !state.usedWayIdents.contains(way.ident) else { continue }
				let wayNodes = way.nodes

				// Find every index where `currentNode` appears in this way
				// and try both traversal directions from each occurrence.
				// For closed ways wayNodes.first === wayNodes.last; skip the
				// duplicate last entry to avoid producing redundant paths.
				for (startIdx, node) in wayNodes.enumerated() where node === state.currentNode {
					if way.isClosed(), startIdx == wayNodes.count - 1 { continue }
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
	/// `results`.  A new `SearchState` is enqueued at every visited node so
	/// that interior junction nodes (nodes shared with other ways) become
	/// branch points in the search.
	private static func walk(
		wayNodes: [OsmNode],
		from startIdx: Int,
		step: Int,
		way: OsmWay,
		state: SearchState,
		goal: OsmNode,
		queue: inout [SearchState],
		results: inout [[OsmNode]])
	{
		var newPath = state.pathNodes
		var newVisited = state.visitedNodeIdents
		var newUsedIdents = state.usedWayIdents
		var newUsedWays = state.usedWays
		newUsedIdents.insert(way.ident)
		newUsedWays.insert(way)

		if way.isClosed() {
			// Closed ways store wayNodes.first === wayNodes.last; the ring has
			// wayNodes.count-1 distinct nodes.  Use modular arithmetic so the
			// walk can go either direction around the ring and find the goal
			// even when it lies on the other side of the first/last node.
			let ringCount = wayNodes.count - 1
			var idx = (startIdx + step + ringCount) % ringCount
			for _ in 0..<ringCount - 1 {
				let node = wayNodes[idx]
				if node === goal {
					newPath.append(node)
					results.append(newPath)
					return
				}
				if newVisited.contains(node.ident) {
					return // genuine cycle — abandon this branch
				}
				newPath.append(node)
				newVisited.insert(node.ident)
				if node.wayCount > 1 {
					queue.append(SearchState(
						currentNode: node,
						pathNodes: newPath,
						usedWayIdents: newUsedIdents,
						usedWays: newUsedWays,
						visitedNodeIdents: newVisited))
				}
				idx = (idx + step + ringCount) % ringCount
			}
		} else {
			var idx = startIdx + step
			while idx >= 0, idx < wayNodes.count {
				let node = wayNodes[idx]
				if node === goal {
					newPath.append(node)
					results.append(newPath)
					return
				}
				if newVisited.contains(node.ident) {
					return // cycle — abandon this branch
				}
				newPath.append(node)
				newVisited.insert(node.ident)
				if node.wayCount > 1 {
					queue.append(SearchState(
						currentNode: node,
						pathNodes: newPath,
						usedWayIdents: newUsedIdents,
						usedWays: newUsedWays,
						visitedNodeIdents: newVisited))
				}
				idx += step
			}
		}
	}
}
