//
//  DisplayLink.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/9/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

final class DisplayLink {
	static let shared = DisplayLink()

	enum AnimationId {
		case rotateScreenSmoothing // smoothly rotates the screen when compass is enabled/disabled
		case automatedFramerateTest // automatically pans the screen during FPS test
		case fpsLabelUpdate // updates the FPS test label
		case pinDragScroll // pans the screen when pushpin is dragged to edge
		case screenPanningInertia // applies inertia after user pan gesture ends
	}

	var displayLink: CADisplayLink!
	var blockDict: [AnimationId: () -> Void] = [:]

	private static let g_shared = DisplayLink()

	init() {
		displayLink = CADisplayLink(target: self, selector: #selector(step))
		displayLink.isPaused = true
		displayLink.add(to: RunLoop.main, forMode: .default)
		setFrameRate()
	}

	func setFrameRate() {
		if #available(iOS 15.0, *) {
			let maxFPS = Float(UIScreen.main.maximumFramesPerSecond)
			let preferredFPS = (UserPrefs.shared.maximizeFrameRate.value ?? false) ? maxFPS : 60.0
			let rng = CAFrameRateRange(minimum: 30.0,
			                           maximum: maxFPS,
			                           preferred: preferredFPS)
			displayLink.preferredFrameRateRange = rng
		}
	}

	@objc func step() {
		for block in blockDict.values {
			block()
		}
	}

	var duration: CFTimeInterval {
		return displayLink.duration
	}

	var timestamp: CFTimeInterval {
		return displayLink.timestamp
	}

	func add(_ name: AnimationId, block: @escaping () -> Void) {
		blockDict[name] = block
		displayLink.isPaused = false
	}

	func has(_ name: AnimationId) -> Bool {
		return blockDict[name] != nil
	}

	func remove(_ name: AnimationId) {
		blockDict.removeValue(forKey: name)

		if blockDict.count == 0 {
			displayLink.isPaused = true
		}
	}

	deinit {
		displayLink.remove(from: RunLoop.main, forMode: .default)
	}
}
