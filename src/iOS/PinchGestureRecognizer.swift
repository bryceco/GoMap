//
//  PinchGestureRecognizer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/12/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

class PinchGestureRecognizer: UIPinchGestureRecognizer {

	/// True when the pinch originated from a trackpad rather than direct touch.
	private(set) var _isTrackpad = false

	var isTrackpad: Bool {
		return _isTrackpad || AppEnvironment.isRunningOnMac
	}

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesBegan(touches, with: event)
		if #available(iOS 13.4, *) {
			_isTrackpad = touches.contains { $0.type == .indirectPointer }
		}
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesEnded(touches, with: event)
		_isTrackpad = false
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesCancelled(touches, with: event)
		_isTrackpad = false
	}
}
