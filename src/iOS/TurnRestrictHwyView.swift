//
//  TurnRestrictHwyView.swift
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

import UIKit

enum TURN_RESTRICT: Int {
	case NONE = 0
	case NO = 1
	case ONLY = 2
}

typealias BlockTurnRestrictHwyView = (TurnRestrictHwyView) -> Void

class TurnRestrictHwyView: UIView {
	var objRel: OsmRelation? // associated relation
	var wayObj: OsmWay? // associated way
	var centerNode: OsmNode?
	var connectedNode: OsmNode?
	var centerPoint = CGPoint.zero
	var endPoint = CGPoint.zero
	var highlightLayer: CAShapeLayer?
	var highwayLayer: CAShapeLayer?
	var highwaySelectedCallback: BlockTurnRestrictHwyView?
	var restrictionChangedCallback: BlockTurnRestrictHwyView?
	var arrowButton: UIButton?
	var parentWaysArray = [OsmWay]()
	var restriction: TURN_RESTRICT!

	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		let point = OSMPoint(point)
		let dist = point.distanceToLineSegment(OSMPoint(centerPoint), OSMPoint(endPoint))
		return dist < 10.0 // touch within 10 pixels
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		if highwaySelectedCallback != nil {
			highwaySelectedCallback?(self)
		}
	}

	func rotateButtonForDirection() {
		if restriction == .NONE {
			let angle = CGFloat(TurnRestrictHwyView.heading(from: centerPoint, to: endPoint))
			arrowButton?.transform = CGAffineTransform(rotationAngle: .pi + angle)
		} else {
			arrowButton?.transform = CGAffineTransform.identity
		}
	}

	func createTurnRestrictionButton() {
		let dist: CGFloat = 0.5
		let location = CGPoint(
			x: Double(centerPoint.x + (endPoint.x - centerPoint.x) * dist),
			y: Double(centerPoint.y + (endPoint.y - centerPoint.y) * dist))

		arrowButton = UIButton(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
		arrowButton?.setImage(UIImage(named: "arrowAllow"), for: .normal)

		arrowButton?.imageView?.contentMode = .scaleAspectFit
		arrowButton?.center = location
		arrowButton?.layer.borderWidth = 1.0
		arrowButton?.layer.cornerRadius = 2.0
		arrowButton?.layer.borderColor = UIColor.black.cgColor

		arrowButton?.addTarget(self, action: #selector(restrictionButtonPressed(_:)), for: .touchUpInside)

		if let arrowButton = arrowButton {
			addSubview(arrowButton)
		}
	}

	func createOneWayArrowsForHighway() {
		if wayObj?.isOneWay == ONEWAY._NONE {
			return
		}

		var centerIndex: Int?
		if let centerNode = centerNode {
			centerIndex = wayObj?.nodes.firstIndex(of: centerNode) ?? NSNotFound
		}
		var otherIndex: Int?
		if let connectedNode = connectedNode {
			otherIndex = wayObj?.nodes.firstIndex(of: connectedNode) ?? NSNotFound
		}
		let forwardOneWay = (wayObj?.isOneWay == ONEWAY._FORWARD) == ((otherIndex ?? 0) > (centerIndex ?? 0))

		// create 3 arrows on highway
		let location1 = MidPointOf(centerPoint, endPoint)
		let location2 = MidPointOf(location1, centerPoint)
		let location3 = MidPointOf(location1, endPoint)

		createOneWayArrow(atPosition: location1, isDirection: forwardOneWay)
		createOneWayArrow(atPosition: location2, isDirection: forwardOneWay)
		createOneWayArrow(atPosition: location3, isDirection: forwardOneWay)
	}

	func createOneWayArrow(atPosition location: CGPoint, isDirection isForward: Bool) {
		// Height of the arrow
		let arrowHeight: CGFloat = 12
		let arrowHeightHalf = arrowHeight / 2

		let p1 = CGPoint(x: arrowHeightHalf, y: arrowHeightHalf)
		let p2 = CGPoint(x: -arrowHeightHalf, y: arrowHeightHalf)
		let p3 = CGPoint(x: 0, y: -arrowHeightHalf)

		let path = UIBezierPath()
		path.move(to: p1)
		path.addLine(to: p3)
		path.addLine(to: p2)
		path.addLine(to: CGPoint(x: 0, y: 0))
		path.close()

		let arrow = CAShapeLayer()
		arrow.path = path.cgPath // arrowPath;
		arrow.lineWidth = 1.0
		arrow.anchorPoint = CGPoint(x: 0.5, y: 0.5)

		let angle = CGFloat(isForward ? TurnRestrictHwyView.heading(from: location, to: center) : TurnRestrictHwyView
			.heading(from: center, to: location))
		arrow.setAffineTransform(CGAffineTransform(rotationAngle: angle))
		arrow.position = location

		arrow.fillColor = UIColor.black.cgColor
		layer.addSublayer(arrow)

		if let arrowButton = arrowButton {
			bringSubviewToFront(arrowButton)
		}
	}

	func isOneWayExitingCenter() -> Bool {
		let way = wayObj
		if way?.isOneWay != nil {
			var centerIndex: Int?
			if let centerNode = centerNode {
				centerIndex = way?.nodes.firstIndex(of: centerNode) ?? NSNotFound
			}
			var otherIndex: Int?
			if let connectedNode = connectedNode {
				otherIndex = way?.nodes.firstIndex(of: connectedNode) ?? NSNotFound
			}
			if ((otherIndex ?? 0) > (centerIndex ?? 0)) == (way?.isOneWay == ONEWAY._FORWARD) {
				return true
			}
		}
		return false
	}

	func isOneWayEnteringCenter() -> Bool {
		let way = wayObj
		if way?.isOneWay != nil {
			var centerIndex: Int?
			if let centerNode = centerNode {
				centerIndex = way?.nodes.firstIndex(of: centerNode) ?? NSNotFound
			}
			var otherIndex: Int?
			if let connectedNode = connectedNode {
				otherIndex = way?.nodes.firstIndex(of: connectedNode) ?? NSNotFound
			}
			if ((otherIndex ?? 0) < (centerIndex ?? 0)) == (way?.isOneWay == ONEWAY._FORWARD) {
				return true
			}
		}
		return false
	}

	@objc func restrictionButtonPressed(_ sender: UIButton?) {
		if restrictionChangedCallback != nil {
			restrictionChangedCallback?(self)
		}
	}

	func turnAngleDegrees(from fromPoint: CGPoint) -> Double {
		let fromAngle = atan2(centerPoint.y - fromPoint.y, centerPoint.x - fromPoint.x)
		let toAngle = atan2(endPoint.y - centerPoint.y, endPoint.x - centerPoint.x)
		var angle = (toAngle - fromAngle) * 180 / .pi
		if angle > 180 {
			angle -= 360
		}
		if angle <= -180 {
			angle += 360
		}
		return Double(angle)
	}

	// MARK: Get angle of line connecting two points

	class func heading(from a: CGPoint, to b: CGPoint) -> Float {
		let dx = b.x - a.x
		let dy = b.y - a.y
		let radians = atan2(-dx, dy) // in radians
		return Float(radians)
	}

	// MARK: Point Pair To Bearing Degree

	class func bearingDegrees(from startingPoint: CGPoint, to endingPoint: CGPoint) -> CGFloat {
		let bearingRadians = atan2(endingPoint.y - startingPoint.y,
		                           endingPoint.x - startingPoint.x) // bearing in radians
		let bearingDegrees = bearingRadians * (180.0 / .pi) // convert to degrees
		return CGFloat(bearingDegrees)
	}
}

private func MidPointOf(_ p1: CGPoint, _ p2: CGPoint) -> CGPoint {
	let p = CGPoint(x: Double((p1.x + p2.x) / 2), y: Double((p1.y + p2.y) / 2))
	return p
}
