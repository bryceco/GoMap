//
//  GpxTrackAttributes.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/5/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
// ActivityKit not supported in MacCatalyst
import ActivityKit
import AppIntents
import SwiftUI

struct GpxTrackAttributes: ActivityAttributes {
	public typealias GpxTrackStatus = ContentState
	enum Status: Int, Codable {
		case running
		case paused
		case ended
	}

	public struct ContentState: Codable, Hashable {
		var startTime: Date
		var endTime: Date?
		var pointCount: Int
		var status: Status

		var durationHMS: String {
			let formatter = DateComponentsFormatter()
			formatter.allowedUnits = [.minute, .second]
			formatter.zeroFormattingBehavior = .dropLeading
			return formatter.string(from: (endTime ?? Date()).timeIntervalSince(startTime))!
		}

		init(startTime: Date,
		     endTime: Date? = nil,
		     pointCount: Int = 0,
		     status: GpxTrackAttributes.Status = .running)
		{
			self.startTime = startTime
			self.endTime = endTime
			self.pointCount = pointCount
			self.status = status
		}
	}
}

@available(iOS 16.1, *)
struct PauseGpxTrackIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Pause GPX"
	static var description = IntentDescription("Pause recording GPX tracks.")

	public init() {}

	func perform() async throws -> some IntentResult {
		await MainActor.run {
			widgetPauseGPS()
		}
		return .result()
	}
}

@available(iOS 16.1, *)
struct StopGpxTrackIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Stop GPX"
	static var description = IntentDescription("Stop recording GPX tracks.")

	public init() {}

	func perform() async throws -> some IntentResult {
		await MainActor.run {
			widgetStopGPS()
		}
		return .result()
	}
}

@available(iOS 16.1, *)
struct StartGpxTrackIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "Start GPX"
	static var description = IntentDescription("Start recording GPX tracks.")

	public init() {}

	func perform() async throws -> some IntentResult {
		await MainActor.run {
			widgetStartGPS()
		}
		return .result()
	}
}
#endif
