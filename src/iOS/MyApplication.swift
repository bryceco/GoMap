//
//  MyApplication.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/11/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

import UIKit

let TOUCH_RADIUS: CGFloat = 22

class MyApplication: UIApplication {
	private var touches: [UITouch: (UIWindow, TimeInterval)] = [:]
	private var touchImage: UIImage?

	var showTouchCircles = false

	override init() {
		super.init()
		touchImage = UIImage(named: "Finger")
	}

	func rect(forTouchPosition pos: CGPoint) -> CGRect {
		if touchImage != nil {
			var rc = CGRect(origin: pos, size: touchImage?.size ?? CGSize.zero)
			rc = rc.offsetBy(dx: -(touchImage?.size.width ?? 0.0) / 2, dy: -TOUCH_RADIUS)
			rc.origin.x += 15 // extra so rotated finger is aligned
			rc.origin.y -= 10 // extra so touches on toolbar or easier to see
			return rc
		} else {
			return CGRect(
				x: pos.x - TOUCH_RADIUS,
				y: pos.y - TOUCH_RADIUS,
				width: 2 * TOUCH_RADIUS,
				height: 2 * TOUCH_RADIUS)
		}
	}

	override func sendEvent(_ event: UIEvent) {
		super.sendEvent(event)

		if !showTouchCircles {
			return
		}

		for touch in event.allTouches ?? [] {
			var pos: CGPoint = touch.location(in: nil)
			// if we double-tap then the second tap will be captured by our own window
			pos = touch.window!.convert(pos, to: nil)

			if UIDevice.current.userInterfaceIdiom == .phone {
				// Translate coordinates in case screen is rotated. On iPad the tranform is done for us.
				pos = UIScreen.main.coordinateSpace.convert(pos, to: UIScreen.main.fixedCoordinateSpace)
			}

			if touch.phase == .began {
				let win = UIWindow(frame: rect(forTouchPosition: pos))

				touches[touch] = (win, touch.timestamp)
				win.windowLevel = .statusBar
				win.isHidden = false
				if touchImage != nil {
					win.layer.contents = touchImage?.cgImage
					win.layer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 4))
				} else {
					win.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 1.0, alpha: 1.0)
					win.layer.cornerRadius = TOUCH_RADIUS
					win.layer.opacity = 0.85
				}
			} else if touch.phase == .moved {
				let (win, _) = touches[touch]!
				win.layer.setAffineTransform(CGAffineTransform.identity)
				win.frame = rect(forTouchPosition: pos)
				win.layer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 4))
			} else if touch.phase == .stationary {
				// ignore
			} else {
				// ended/cancelled
				// remove window after a slight delay so quick taps are still visible
				let MIN_DISPLAY_INTERVAL = 0.5
				let (win, start) = touches[touch]!
				var delta = TimeInterval(touch.timestamp - start)
				if delta < MIN_DISPLAY_INTERVAL {
					delta = TimeInterval(MIN_DISPLAY_INTERVAL - delta)
					DispatchQueue.main.asyncAfter(
						deadline: DispatchTime
							.now() + Double(Int64(delta * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC),
						execute: {
							// force window to be retained until now
							withExtendedLifetime(win) {}
						})
				}
				touches.removeValue(forKey: touch)
			}
		}
	}
}
