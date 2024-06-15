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

	var displayLink: CADisplayLink!
	var blockDict: [String: () -> Void] = [:]

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
		for (_, block) in blockDict {
			block()
		}
	}

	func duration() -> Double {
		return displayLink.duration
	}

	func timestamp() -> CFTimeInterval {
		return displayLink.timestamp
	}

	func addName(_ name: String, block: @escaping () -> Void) {
		blockDict[name] = block
		displayLink.isPaused = false
	}

	func hasName(_ name: String) -> Bool {
		return blockDict[name] != nil
	}

	func removeName(_ name: String) {
		blockDict.removeValue(forKey: name)

		if blockDict.count == 0 {
			displayLink.isPaused = true
		}
	}

	deinit {
		displayLink.remove(from: RunLoop.main, forMode: .default)
	}
}
