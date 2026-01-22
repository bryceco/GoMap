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
	private var tapPos = CGPoint.zero
	private var target: NSObject?
	private var requestedAction: Selector?

	override init(frame: CGRect) {
		super.init(frame: frame)
		addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
	}

	@objc func touchDown(_ sender: Any?) {
		tapPos = frame.origin
	}

	override func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
		if controlEvents == .touchUpInside {
			// we need to intercept the event and ignore it potentially
			self.target = (target as? NSObject)!
			requestedAction = action
			super.addTarget(self, action: #selector(touchUpInside), for: controlEvents)
		} else {
			super.addTarget(target, action: action, for: controlEvents)
		}
	}

	@objc func touchUpInside() {
		let pos1 = tapPos
		let pos2 = frame.origin
		if hypot(pos1.x - pos2.x, pos1.y - pos2.y) > frame.size.width / 2 {
			// we moved, so ignore event
		} else {
			// good to go: invoke the original action
			_ = target!.perform(requestedAction!, with: self).takeUnretainedValue()
		}
	}
}
