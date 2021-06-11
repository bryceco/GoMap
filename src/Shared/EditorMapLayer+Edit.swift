//
//  EditorMapLayer+Edit.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/3/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Foundation

enum EditError: Error {
	case text(String)
}

extension EditorMapLayer {

	func extendSelectedWay(to newPoint: CGPoint, from pinPoint: CGPoint) -> Result<CGPoint,EditError> {

		if let way = self.selectedWay,
		   self.selectedNode == nil
		{
			// insert a new node into way at arrowPoint
			let pt = mapView.longitudeLatitude(forScreenPoint: pinPoint, birdsEye: true)
			let pt2 = OSMPoint(x: pt.longitude, y: pt.latitude)
			let segment = way.segmentClosestToPoint(pt2)
			var error: String? = nil
			guard let add = self.canAddNode(toWay: way, atIndex:segment+1, error:&error )
			else {
				return .failure(.text(error!))
			}
			let newNode = self.createNode(at: pinPoint)
			add(newNode)
			self.selectedNode = newNode
			return .success(newPoint)
		}

		let prevNode: OsmNode
		let way: OsmWay
		if let selectedNode = self.selectedNode,
		   let selectedWay = self.selectedWay,
		   selectedWay.nodes.count > 0,
		   selectedWay.isClosed() || (selectedNode != selectedWay.nodes.first && selectedNode != selectedWay.nodes.last)
		{
			// both a node and way are selected but selected node is not an endpoint (or way is closed),
			// so we will create a new way "T" from that node
			prevNode = selectedNode	// use the existing node selected by user
			way = self.createWay(with: selectedNode)	// create a new way extending off of it
		} else {
			// we're either extending a way from it's end, or creating a new way with
			// the pushpin as one end of it and crosshairs (or mouse click) as the other
			prevNode = self.selectedNode ?? self.createNode(at: pinPoint)
			way = self.selectedWay ?? self.createWay(with: prevNode)
		}

		let prevIndex = way.nodes.firstIndex(of: prevNode)!
		var nextIndex = prevIndex
		if nextIndex == way.nodes.count - 1 {
			nextIndex += 1
		}
		// add new node at point
		var newPoint = newPoint
		let prevPrevNode = way.nodes.count >= 2 ? way.nodes[way.nodes.count-2] : nil
		let prevPrevPoint = prevPrevNode != nil ? mapView.screenPoint(forLatitude: prevPrevNode!.lat, longitude: prevPrevNode!.lon, birdsEye: true) : CGPoint.zero

		if hypot(pinPoint.x - newPoint.x, pinPoint.y - newPoint.y) > 10.0 &&
			(prevPrevNode == nil || hypot(prevPrevPoint.x - newPoint.x, prevPrevPoint.y - newPoint.y) > 10.0)
		{
			// it's far enough from previous point to use
		} else {

			// compute a good place for next point
			if way.nodes.count < 2 {
				// create 2nd point in the direction of the center of the screen
				let vert = abs(Float(pinPoint.x - newPoint.x)) < abs(Float(pinPoint.y - newPoint.y))
				if vert {
					newPoint.x = pinPoint.x
					newPoint.y = abs(newPoint.y - pinPoint.y) < 30 ? pinPoint.y + 60 : 2 * newPoint.y - pinPoint.y
				} else {
					newPoint.x = abs(newPoint.x - pinPoint.x) < 30 ? pinPoint.x + 60 : 2 * newPoint.x - pinPoint.x
					newPoint.y = pinPoint.y
				}
			} else if way.nodes.count == 2 {
				// create 3rd point 90 degrees from first 2
				let n1 = way.nodes[1 - prevIndex]
				let p1 = mapView.screenPoint(forLatitude: n1.lat, longitude: n1.lon, birdsEye: true)
				var delta = CGPoint(x: p1.x - pinPoint.x, y: p1.y - pinPoint.y)
				let len = hypot(delta.x, delta.y)
				if len > 100 {
					delta.x *= CGFloat(100 / len)
					delta.y *= CGFloat(100 / len)
				}
				let np1 = CGPoint(x: pinPoint.x - delta.y, y: pinPoint.y + delta.x)
				let np2 = CGPoint(x: pinPoint.x + delta.y, y: pinPoint.y - delta.x)
				if OSMPoint(np1).distanceToPoint( OSMPoint(newPoint) ) < OSMPoint(np2).distanceToPoint( OSMPoint(newPoint) ) {
					newPoint = np1
				} else {
					newPoint = np2
				}
			} else {
				// create 4th point and beyond following angle of previous 3
				let n1 = prevIndex == 0 ? way.nodes[1] : way.nodes[prevIndex - 1]
				let n2 = prevIndex == 0 ? way.nodes[2] : way.nodes[prevIndex - 2]
				let p1 = mapView.screenPoint(forLatitude: n1.lat, longitude: n1.lon, birdsEye: true)
				let p2 = mapView.screenPoint(forLatitude: n2.lat, longitude: n2.lon, birdsEye: true)
				let d1 = OSMPoint(x: Double(pinPoint.x - p1.x), y: Double(pinPoint.y - p1.y))
				let d2 = OSMPoint(x: Double(p1.x - p2.x), y: Double(p1.y - p2.y))
				var a1 = atan2(d1.y, d1.x)
				let a2 = atan2(d2.y, d2.x)
				var dist = hypot(d1.x, d1.y)
				// if previous angle was 90 degrees then match length of first leg to make a rectangle
				if (way.nodes.count == 3 || way.nodes.count == 4) && abs(fmod(abs(Float(a1 - a2)), .pi) - .pi / 2) < 0.1 {
					dist = hypot(d2.x, d2.y)
				} else if dist > 100 {
					dist = 100
				}
				a1 += a1 - a2
				newPoint = CGPoint(x: Double(pinPoint.x) + dist * cos(a1),
								   y: Double(Double(pinPoint.y) + dist * sin(a1)))
			}
			// make sure selected point is on-screen
			var rc = bounds.insetBy(dx: 20.0, dy: 20.0)
			rc.size.height -= 190
			newPoint.x = CGFloat(max(newPoint.x, rc.origin.x))
			newPoint.x = CGFloat(min(newPoint.x, rc.origin.x + rc.size.width))
			newPoint.y = CGFloat(max(newPoint.y, rc.origin.y))
			newPoint.y = CGFloat(min(newPoint.y, rc.origin.y + rc.size.height))
		}

		if way.nodes.count >= 2 {
			let start = prevIndex == 0 ? way.nodes.last! : way.nodes[0]
			let s = mapView.screenPoint(forLatitude: start.lat, longitude: start.lon, birdsEye: true)
			let d = hypot(s.x - newPoint.x, s.y - newPoint.y)
			if d < 3.0 {
				// join first to last
				var error: String? = nil
				if let action = self.canAddNode(toWay: way, atIndex:nextIndex, error:&error) {
					action(start)
					self.selectedWay = way
					self.selectedNode = nil
					return .success(s)
				} else {
					// fall through to non-joining case
				}
			}
		}

		var error: String? = nil
		guard let addNodeToWay: EditActionWithNode = self.canAddNode(toWay: way, atIndex:nextIndex, error:&error)
		else {
			return .failure(.text(error!))
		}
		let node2 = self.createNode(at: newPoint)
		self.selectedWay = way // set selection before perfoming add-node action so selection is recorded in undo stack
		self.selectedNode = node2
		addNodeToWay(node2)
		return .success(newPoint)
	}

}
