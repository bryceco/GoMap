//
//  FpsLabel.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/15/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import UIKit

private let ENABLE_FPS = 0

private let FRAME_COUNT = 2 * 60

final class FpsLabel: UILabel {
	private var historyPos = 0
	private var frameTimestamp = [CFTimeInterval](repeating: 0, count: FRAME_COUNT) // average last 60 frames

	private var timer: DispatchSourceTimer!

	public var showFPS = false {
		didSet {
			if showFPS == oldValue {
				return
			}
			if showFPS {
				isHidden = false
				DisplayLink.shared.addName("FpsLabel", block: {
					self.frameUpdated()
				})

				// create a timer to update the text twice a second
				timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
				timer.schedule(deadline: .now(), repeating: .milliseconds(500))
				timer.setEventHandler(handler: { [weak self] in
					self?.updateText()
				})
				timer?.activate()
				layer.backgroundColor = UIColor(white: 1.0, alpha: 0.6).cgColor
			} else {
				text = nil
				isHidden = true
				DisplayLink.shared.removeName("FpsLabel")
				timer?.cancel()
			}
		}
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		showFPS = false
		isHidden = true
	}

	deinit {
		showFPS = false
	}

	func updateText() {
		// scan backward to see how many frames were drawn in the last second
		let seconds = Double(FRAME_COUNT / 60)
		var frameCount: Double = 0
		var pos = (historyPos + FRAME_COUNT - 1) % FRAME_COUNT
		let last = frameTimestamp[pos]
		var prev: CFTimeInterval = 0.0
		repeat {
			pos -= 1
			if pos < 0 {
				pos = FRAME_COUNT - 1
			}
			prev = frameTimestamp[pos]
			frameCount += 1
			if last - prev >= seconds {
				break
			}
		} while pos != historyPos

		let average = CFTimeInterval(frameCount / (last - prev))
		if average >= 10.0 {
			text = String(format: "%.1f FPS", average)
		} else {
			text = String(format: "%.2f FPS", average)
		}
	}

	func frameUpdated() {
		// add to history
		let now = CACurrentMediaTime()
		frameTimestamp[historyPos] = now
		historyPos += 1
		if historyPos >= FRAME_COUNT {
			historyPos = 0
		}
	}
}
