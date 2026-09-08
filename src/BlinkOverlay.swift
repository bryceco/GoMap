
//
//  BlinkOverlay.swift
//  OpenStreetMap
//
//  Highlights an OSM feature on-screen with an animated marching-ants stroke.
//  Blinking begins immediately on creation and stops automatically when the
//  object is deallocated — callers simply set their reference to nil to stop.
//

import QuartzCore
import UIKit

final class BlinkOverlay {

	/// Disambiguates which arc of a closed way to blink when highlighting the
	/// portion between two nodes.  `forward` follows the node-array order;
	/// `backward` goes the other way around the ring.
	enum Direction {
		case forward
		case backward
	}

	private let blinkLayer: CAShapeLayer

	// MARK: - Node

	/// Blink a node (animated circle around the node).
	init(node: OsmNode,
	     color: UIColor = .white,
	     mapTransform: MapTransform,
	     parentLayer: CALayer)
	{
		let center = mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true)
		var rect = CGRect(x: center.x, y: center.y, width: 0, height: 0)
		rect = rect.insetBy(dx: -10, dy: -10)
		let path = CGMutablePath()
		path.addEllipse(in: rect)
		blinkLayer = Self.makeAndAdd(path: path, color: color, to: parentLayer)
	}

	// MARK: - Way (entire)

	/// Blink an entire way.
	init(way: OsmWay,
	     color: UIColor = .white,
	     mapTransform: MapTransform,
	     parentLayer: CALayer)
	{
		let path = Self.pathForNodes(way.nodes, mapTransform: mapTransform)
		blinkLayer = Self.makeAndAdd(path: path, color: color, to: parentLayer)
	}

	// MARK: - Way segment

	/// Blink a single segment of a way — the edge between
	/// `way.nodes[segment]` and `way.nodes[segment + 1]`.
	init(way: OsmWay,
	     segment: Int,
	     color: UIColor = .white,
	     mapTransform: MapTransform,
	     parentLayer: CALayer)
	{
		assert(way.nodes.count >= segment + 2)
		let path = Self.pathForNodes(Array(way.nodes[segment...segment + 1]),
		                             mapTransform: mapTransform)
		blinkLayer = Self.makeAndAdd(path: path, color: color, to: parentLayer)
	}

	// MARK: - Between two nodes of a way

	/// Blink the portion of a way between two of its nodes.
	///
	/// For an open way there is only one path between the two nodes, so
	/// `direction` is ignored.  For a **closed** way there are two arcs;
	/// pass `.forward` to travel in node-array order from `from` to `to`,
	/// or `.backward` to travel in the opposite direction.  Passing `nil`
	/// is equivalent to `.forward` for closed ways.
	init(way: OsmWay,
	     from: OsmNode,
	     to: OsmNode,
	     direction: Direction?,
	     color: UIColor = .white,
	     mapTransform: MapTransform,
	     parentLayer: CALayer)
	{
		let nodes = Self.nodesAlong(way: way, from: from, to: to, direction: direction)
		let path = Self.pathForNodes(nodes, mapTransform: mapTransform)
		blinkLayer = Self.makeAndAdd(path: path, color: color, to: parentLayer)
	}

	func translate(dx: CGFloat, dy: CGFloat) {
		blinkLayer.position = blinkLayer.position.withOffset(dx, dy)
	}

	deinit {
		blinkLayer.removeFromSuperlayer()
	}

	// MARK: - Private helpers

	private static func makeAndAdd(path: CGPath, color: UIColor, to parentLayer: CALayer) -> CAShapeLayer {
		let (backing, dots) = makeLayers(path: path, color: color)
		startAnimation(on: dots)
		parentLayer.addSublayer(backing)
		return backing
	}

	private static func makeLayers(path: CGPath, color: UIColor) -> (CAShapeLayer, CAShapeLayer) {
		let backing = CAShapeLayer()
		backing.path = path
		backing.fillColor = nil
		backing.lineWidth = 3.0
		backing.zPosition = 4 // EDITOR_ZLAYER.BLINK
		backing.strokeColor = UIColor.black.cgColor

		let dots = CAShapeLayer()
		dots.path = path
		dots.fillColor = nil
		dots.lineWidth = backing.lineWidth
		dots.position = .zero
		dots.anchorPoint = .zero
		dots.strokeColor = color.cgColor
		dots.lineDashPhase = 0.0
		dots.lineDashPattern = [NSNumber(value: 4), NSNumber(value: 4)]

		backing.addSublayer(dots)
		return (backing, dots)
	}

	private static func startAnimation(on dots: CAShapeLayer) {
		let animation = CABasicAnimation(keyPath: "lineDashPhase")
		animation.fromValue = NSNumber(value: 0.0)
		animation.toValue = NSNumber(value: -16.0)
		animation.duration = 0.6
		animation.repeatCount = Float(CGFloat.greatestFiniteMagnitude)
		dots.add(animation, forKey: "linePhase")
	}

	/// Screen-space polyline through an array of nodes.
	private static func pathForNodes(_ nodes: [OsmNode], mapTransform: MapTransform) -> CGPath {
		let path = CGMutablePath()
		guard let first = nodes.first else { return path }
		path.move(to: mapTransform.screenPoint(forLatLon: first.latLon, birdsEye: true))
		for node in nodes.dropFirst() {
			path.addLine(to: mapTransform.screenPoint(forLatLon: node.latLon, birdsEye: true))
		}
		return path
	}

	/// Returns the ordered nodes of `way` between `from` and `to`.
	private static func nodesAlong(way: OsmWay,
	                               from: OsmNode,
	                               to: OsmNode,
	                               direction: Direction?) -> [OsmNode]
	{
		let nodes = way.nodes
		guard let fromIdx = nodes.firstIndex(of: from),
		      let toIdx = nodes.firstIndex(of: to)
		else { return [] }

		if way.isClosed() {
			// Closed ways duplicate the first node at the end; the ring has
			// (count − 1) unique nodes.
			// Backward a→b = reversed(forward b→a), so we swap start/end and
			// reverse at the end rather than walking the ring in reverse.
			let ringCount = nodes.count - 1
			let isForward = (direction ?? .forward) == .forward
			let (start, end) = isForward ? (fromIdx % ringCount, toIdx % ringCount)
				: (toIdx % ringCount, fromIdx % ringCount)
			let slice: [OsmNode] = start <= end
				? Array(nodes[start...end])
				: Array(nodes[start..<ringCount]) + Array(nodes[0...end])
			return isForward ? slice : slice.reversed()
		} else {
			// Open way: one unambiguous path.
			return fromIdx <= toIdx
				? Array(nodes[fromIdx...toIdx])
				: Array(nodes[toIdx...fromIdx].reversed())
		}
	}
}
