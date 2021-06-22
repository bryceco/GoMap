//
//  TapAndDragGesture.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/13/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import UIKit

private enum EnumA: Int {
	case need_FIRST_TAP
	case need_SECOND_TAP
	case need_DRAG
	case is_DRAGGING
}

// #undef DEBUG

private let DoubleTapTime: TimeInterval = 0.5

private func TouchTranslation(_ touch: UITouch?, _ view: UIView?) -> CGPoint {
	let newPoint = touch?.location(in: view)
	let prevPoint = touch?.previousLocation(in: view)
	let delta = CGPoint(
		x: Double((newPoint?.x ?? 0.0) - (prevPoint?.x ?? 0.0)),
		y: Double((newPoint?.y ?? 0.0) - (prevPoint?.y ?? 0.0)))
	return delta
}

class TapAndDragGesture: UIGestureRecognizer {
	var tapState = 0
	var tapPoint = CGPoint.zero
	var lastTouchLocation = CGPoint.zero
	var lastTouchTranslation = CGPoint.zero
	var lastTouchTimestamp: TimeInterval = 0.0

#if DEBUG

	func showState() {
		var state: String?
		switch tapState {
		case EnumA.need_FIRST_TAP.rawValue:
			state = "need first"
		case EnumA.need_SECOND_TAP.rawValue:
			state = "need second"
		case EnumA.need_DRAG.rawValue:
			state = "need drag"
		case EnumA.is_DRAGGING.rawValue:
			state = "dragging"
		default:
			state = nil
		}
		print("state = \(state ?? "")\n")
	}

#endif

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesBegan(touches, with: event)
#if DEBUG
		print("began\n")
#endif
		if touches.count != 1 {
			state = tapState == EnumA.need_DRAG.rawValue ? .cancelled : .failed
			return
		}

		if tapState == EnumA.need_SECOND_TAP.rawValue, state == .possible {
			let touch = touches.first
			let loc = touch?.location(in: view)
			if ProcessInfo.processInfo.systemUptime - lastTouchTimestamp < DoubleTapTime,
			   abs(Float(lastTouchLocation.x - (loc?.x ?? 0.0))) < 100,
			   abs(Float(lastTouchLocation.y - (loc?.y ?? 0.0))) < 100
			{
				tapState = EnumA.need_DRAG.rawValue
			} else {
#if DEBUG
				print("2nd tap too slow or too far away\n")
				print("\(lastTouchLocation.x),\(lastTouchLocation.y) vs \(loc?.x ?? 0.0),\(loc?.y ?? 0.0)\n")
#endif
				tapState = EnumA.need_FIRST_TAP.rawValue
				lastTouchLocation = touch?.location(in: view) ?? CGPoint.zero
			}
		}
#if DEBUG
		showState()
#endif
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesEnded(touches, with: event)
#if DEBUG
		print("ended\n")
#endif
		if state != .possible, state != .changed {
			return
		}

		if tapState == EnumA.need_DRAG.rawValue {
			state = .failed
			return
		}
		if tapState == EnumA.is_DRAGGING.rawValue {
			state = .ended
			return
		}
		if tapState == EnumA.need_FIRST_TAP.rawValue {
			tapState = EnumA.need_SECOND_TAP.rawValue
			let touch = touches.first
			lastTouchTimestamp = touch?.timestamp ?? 0.0
		}
#if DEBUG
		showState()
#endif
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesMoved(touches, with: event)

		let touch = touches.first
		let delta = TouchTranslation(touch, view)
		if delta.x == 0, delta.y == 0 {
			return
		}

#if DEBUG
		print("moved\n")
#endif
		if tapState != EnumA.need_DRAG.rawValue, tapState != EnumA.is_DRAGGING.rawValue {
			state = .failed
			return
		}
		if tapState == EnumA.need_DRAG.rawValue {
			tapState = EnumA.is_DRAGGING.rawValue
			state = .began
		} else {
			state = .changed
		}
		lastTouchTimestamp = touch?.timestamp ?? 0.0
		lastTouchTranslation = delta
#if DEBUG
		showState()
#endif
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesCancelled(touches, with: event)

		state = .failed
	}

	override func reset() {
#if DEBUG
		print("reset\n")
#endif
		super.reset()
		tapState = EnumA.need_FIRST_TAP.rawValue
#if DEBUG
		showState()
#endif
	}

	// translation in the coordinate system of the specified view
	func translation(in view: UIView?) -> CGPoint {
		return lastTouchTranslation
	}
}
