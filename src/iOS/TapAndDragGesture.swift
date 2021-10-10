//
//  TapAndDragGesture.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/13/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import UIKit

private enum TapDragGestureState {
	case needFirstTap
	case needSecondTap
	case needDrag
	case isDragging
}

private let DoubleTapTime: TimeInterval = 0.5

private func TouchTranslation(_ touch: UITouch, _ view: UIView) -> CGPoint {
	let newPoint = touch.location(in: view)
	let prevPoint = touch.previousLocation(in: view)
	let delta = CGPoint(x: newPoint.x - prevPoint.x,
	                    y: newPoint.y - prevPoint.y)
	return delta
}

class TapAndDragGesture: UIGestureRecognizer {
	private var tapState = TapDragGestureState.needFirstTap
	private var tapPoint = CGPoint.zero
	private var lastTouchLocation = CGPoint.zero
	private var lastTouchTranslation = CGPoint.zero
	private var lastTouchTimestamp: TimeInterval = 0.0

#if DEBUG
	private func showState() {
#if false
		let state: String
		switch tapState {
		case .needFirstTap: state = "need first"
		case .needSecondTap: state = "need second"
		case .needDrag: state = "need drag"
		case .isDragging: state = "dragging"
		}
		print("state = \(state)")
#endif
	}
#endif

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesBegan(touches, with: event)

		if touches.count != 1 {
			state = tapState == .needDrag ? .cancelled : .failed
			return
		}

		if tapState == .needSecondTap,
		   state == .possible
		{
			guard let touch = touches.first else { return }
			let loc = touch.location(in: view)
			if ProcessInfo.processInfo.systemUptime - lastTouchTimestamp < DoubleTapTime,
			   abs(Float(lastTouchLocation.x - loc.x)) < 100,
			   abs(Float(lastTouchLocation.y - loc.y)) < 100
			{
				tapState = .needDrag
			} else {
				// 2nd tap too slow or too far away
				tapState = .needFirstTap
				lastTouchLocation = touch.location(in: view)
			}
		}
#if DEBUG
		showState()
#endif
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesEnded(touches, with: event)

		if state != .possible,
		   state != .changed
		{
			return
		}
		switch tapState {
		case .needFirstTap:
			if let touch = touches.first {
				tapState = .needSecondTap
				lastTouchTimestamp = touch.timestamp
			}
		case .needSecondTap:
			break
		case .needDrag:
			state = .failed
			return
		case .isDragging:
			state = .ended
			return
		}
#if DEBUG
		showState()
#endif
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesMoved(touches, with: event)

		guard let touch = touches.first,
		      let view = self.view
		else { return }
		let delta = TouchTranslation(touch, view)
		if delta.x == 0, delta.y == 0 {
			return
		}

		switch tapState {
		case .needDrag:
			tapState = .isDragging
			state = .began
		case .isDragging:
			state = .changed
		case .needFirstTap,
		     .needSecondTap:
			state = .failed
			return
		}

		lastTouchTimestamp = touch.timestamp
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
		super.reset()
		tapState = .needFirstTap
#if DEBUG
		showState()
#endif
	}

	// translation in the coordinate system of the specified view
	func translation(in view: UIView?) -> CGPoint {
		return lastTouchTranslation
	}
}
