//
//  DraggableButton.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/21/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

// This is a button that knows that it might be accidentally dragged in it's parent view,
// and if that happens then it shouldn't activate on touchUpInside.
//
// When it sees touchDown it records its position and then on touchUpInside
// it checks if it has moved a significant distance, and only calls the
// target selector if it is close by. There are other ways to accomplish this, such
// as having the drag gesture recognizer cancel the tap recognizer.
class DraggableButton: UIButton {
	private var touchDownPos = CGPoint.zero

	override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
		touchDownPos = touch.location(in: nil)
		return super.beginTracking(touch, with: event)
	}

	override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
		if let touch {
			let endPos = touch.location(in: nil)
			let distance = hypot(touchDownPos.x - endPos.x, touchDownPos.y - endPos.y)
			if distance < 10 {
				sendActions(for: .touchUpInside)
			}
		}
		super.endTracking(touch, with: event)
	}
}
