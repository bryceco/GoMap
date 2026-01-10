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

private let DoubleTapTime: TimeInterval = 0.35
private let DoubleTapDistance: Float = 40.0

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
	private var secondTapTimer: Timer?

#if DEBUG
	private func showState() {
		let state: String
		switch tapState {
		case .needFirstTap: state = "need first"
		case .needSecondTap: state = "need second"
		case .needDrag: state = "need drag"
		case .isDragging: state = "dragging"
		}
		print("state = \(state)")
	}
#endif

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesBegan(touches, with: event)

		guard state == .possible,
		      let touch = touches.first
		else { return }

		if tapState == .needSecondTap {
			secondTapTimer?.invalidate()
			secondTapTimer = nil
		}

		var isIndirect = touches.first?.type == .indirect
		if #available(iOS 13.4, *),
		   touches.first?.type == .indirectPointer
		{
			isIndirect = true
		}
		if touches.count != 1 || isIndirect {
			state = .failed
			tapState = .needFirstTap
			return
		}

		let loc = touch.location(in: view)

		if tapState == .needFirstTap {
			lastTouchLocation = loc
		} else if tapState == .needSecondTap {
			guard
				hypot(Float(lastTouchLocation.x - loc.x),
				      Float(lastTouchLocation.y - loc.y)) < DoubleTapDistance
			else {
				// 2nd tap too slow or too far away
				state = .failed
				tapState = .needFirstTap
				return
			}
			tapState = .needDrag
		}
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesEnded(touches, with: event)

		guard
			state == .possible || state == .changed
		else {
			return
		}
		switch tapState {
		case .needFirstTap:
			tapState = .needSecondTap
			secondTapTimer?.invalidate()
			secondTapTimer = Timer.scheduledTimer(withTimeInterval: DoubleTapTime,
			                                      repeats: false)
			{ [weak self] _ in
				guard let self = self else { return }
				if self.tapState == .needSecondTap {
					self.state = .failed
				}
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
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesMoved(touches, with: event)

		guard let touch = touches.first,
		      let view = view
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
		lastTouchTranslation = delta
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesCancelled(touches, with: event)

		state = .failed
	}

	override func reset() {
		super.reset()
		tapState = .needFirstTap
	}

	// translation in the coordinate system of the specified view
	func translation(in view: UIView?) -> CGPoint {
		return lastTouchTranslation
	}
}
