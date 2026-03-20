//
//  RightClickGestureRecognizer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 3/20/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit.UIGestureRecognizerSubclass

/// A discrete gesture recognizer that fires only on secondary button (right-click).
/// Requires iOS 13.4+ for `UIEvent.buttonMask
@available(iOS 13.4, *)
final class RightClickGestureRecognizer: UIGestureRecognizer {

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesBegan(touches, with: event)

		guard event.buttonMask.contains(.secondary) else {
			state = .failed
			return
		}
		state = .recognized
	}

	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
		super.touchesCancelled(touches, with: event)
		state = .cancelled
	}
}
