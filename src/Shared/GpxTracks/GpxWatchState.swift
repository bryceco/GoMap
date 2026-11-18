//
//  GpxWatchState.swift
//  Go Map!!
//
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import Foundation

struct GpxWatchState: Codable, Equatable {
	enum Status: String, Codable {
		case idle
		case running
		case paused
	}

	enum Command: String {
		case refresh
		case start
		case pause
		case stop
		case history
		case delete
		case setBackgroundRecording
	}

	static let stateKey = "gpxState"
	static let historyKey = "gpxHistory"
	static let commandKey = "command"
	static let traceIdKey = "traceId"
	static let enabledKey = "enabled"

	var status: Status = .idle
	var startTime: Date?
	var endTime: Date?
	var pointCount = 0
	var outline: [[Double]] = []
	var recordsInBackground = true
	var hasAlwaysLocationAccess = true

	func encoded() -> [String: Any] {
		guard let data = try? JSONEncoder().encode(self) else { return [:] }
		return [Self.stateKey: data]
	}

	init() {}

	init?(_ dictionary: [String: Any]) {
		guard let data = dictionary[Self.stateKey] as? Data,
		      let state = try? JSONDecoder().decode(Self.self, from: data)
		else {
			return nil
		}
		self = state
	}
}

struct GpxTraceSummary: Codable, Identifiable, Equatable {
	let id: String
	let startTime: Date
	let duration: TimeInterval
	let pointCount: Int
	let outline: [[Double]]

	static func encoded(_ traces: [GpxTraceSummary]) -> [String: Any] {
		guard let data = try? JSONEncoder().encode(traces) else { return [:] }
		return [GpxWatchState.historyKey: data]
	}

	static func decoded(_ dictionary: [String: Any]) -> [GpxTraceSummary]? {
		guard let data = dictionary[GpxWatchState.historyKey] as? Data else { return nil }
		return try? JSONDecoder().decode([GpxTraceSummary].self, from: data)
	}
}

extension Array where Element == [Double] {
	func simplified(to maxCount: Int) -> [[Double]] {
		guard count > maxCount, maxCount >= 2 else { return self }
		let step = Double(count - 1) / Double(maxCount - 1)
		return (0..<maxCount).map { self[Int((Double($0) * step).rounded())] }
	}
}
