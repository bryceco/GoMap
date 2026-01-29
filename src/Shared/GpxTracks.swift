//
//  GpxTracks.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 1/15/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import CoreLocation.CLLocation
import UIKit

final class GpxTracks: DiskCacheSizeProtocol {

	private static let DefaultExpirationDays = 7
	private var stabilizingCount = 0

	let onChangeTracks = NotificationService<Void>()
	let OnChangeCurrent = NotificationService<Void>()

	init() {
		let uploads = UserPrefs.shared.gpxUploadedGpxTracks.value ?? [:]
		uploadedTracks = uploads.mapValues({ $0.boolValue })
	}

	// all tracks except the active track, sorted with most recent first
	private(set) lazy var savedTracks: [GpxTrack] = loadSavedTracks() {
		didSet {
			onChangeTracks.notify()
		}
	}

	private(set) var activeTrack: GpxTrack? { // track currently being recorded
		didSet {
			OnChangeCurrent.notify()
		}
	}

	// track picked in view controller
	weak var selectedTrack: GpxTrack? {
		didSet {
			// update for color change of selected track
			OnChangeCurrent.notify()
		}
	}

	private(set) var uploadedTracks: [String: Bool] {
		didSet {
			let dict = uploadedTracks.mapValues({ NSNumber(value: $0) })
			UserPrefs.shared.gpxUploadedGpxTracks.value = dict
			onChangeTracks.notify()
		}
	}

	func startNewTrack(continuingCurrentTrack: Bool) {
		if activeTrack != nil {
			endActiveTrack(continuingCurrentTrack: continuingCurrentTrack)
		}
		activeTrack = GpxTrack()
		stabilizingCount = 0
		selectedTrack = activeTrack
	}

	func endActiveTrack(continuingCurrentTrack: Bool) {
		guard let activeTrack else {
			return
		}
		activeTrack.finish()

		// add to list of previous tracks
		if activeTrack.points.count > 1 {
			savedTracks = [activeTrack] + savedTracks // do assignment to trigger notification
		}

		save(toDisk: activeTrack)
		self.activeTrack = nil
		selectedTrack = nil
	}

	private func save(toDisk track: GpxTrack) {
		if track.points.count >= 2 || track.wayPoints.count > 0 {
			// make sure save directory exists
			var time = TimeInterval(CACurrentMediaTime())
			let dir = saveDirectory()
			let path = URL(fileURLWithPath: dir).appendingPathComponent(track.fileName())
			do {
				try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
				let data = try NSKeyedArchiver.archivedData(withRootObject: track, requiringSecureCoding: true)
				try data.write(to: path)
			} catch {
				print("\(error)")
			}
			time = TimeInterval(CACurrentMediaTime() - time)
			DLog("GPX track \(track.points.count) points, save time = \(time)")
		}
	}

	func saveActiveTrack() {
		if let activeTrack {
			save(toDisk: activeTrack)
		}
	}

	func delete(track: GpxTrack) {
		let path = URL(fileURLWithPath: saveDirectory()).appendingPathComponent(track.fileName()).path
		try? FileManager.default.removeItem(atPath: path)
		savedTracks = savedTracks.filter { $0 !== track } // assign to trigger notification
		uploadedTracks.removeValue(forKey: track.name)
		onChangeTracks.notify()
	}

	func markTrackUploaded(_ track: GpxTrack) {
		uploadedTracks[track.name] = true
		onChangeTracks.notify()
	}

	// Removes GPX tracks older than date.
	// This is called when the user selects a new age limit for tracks.
	func trimTracksOlderThan(_ date: Date) {
		// since tracks are sorted chronologically we don't have to test all of them:
		while let track = savedTracks.last,
		      date.timeIntervalSince(track.creationDate) > 0
		{
			// delete oldest
			delete(track: track)
		}
		onChangeTracks.notify()
	}

	func totalPointCount() -> Int {
		var total = activeTrack?.points.count ?? 0
		for track in savedTracks {
			total += track.points.count
		}
		return total
	}

	func addPoint(_ location: CLLocation) {
		guard let activeTrack else {
			return
		}
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
		defer {
			if #available(iOS 16.2, *) {
				GpxTrackWidgetManager.shared.updateTrack()
			}
		}
#endif
		// ignore bad data while starting up
		stabilizingCount += 1
		if stabilizingCount >= 5 {
			// take it
		} else if stabilizingCount == 1 {
			// always skip first point
			return
		} else if location.horizontalAccuracy > 10.0 {
			// skip it
			return
		}

		activeTrack.addPoint(location)

		// automatically save periodically
		// save less frequently if we're in the background
		let saveInterval = UIApplication.shared.applicationState == .active ? 30 : 180

		if activeTrack.points.count % saveInterval == 0 {
			saveActiveTrack()
		}

		// if the number of points is too large then the periodic save will begin taking too long,
		// and drawing performance will degrade, so start a new track every hour
		if activeTrack.points.count >= 3600 {
			endActiveTrack(continuingCurrentTrack: true)
			startNewTrack(continuingCurrentTrack: true)
			stabilizingCount = 100 // already stable
			addPoint(location)
		}
		OnChangeCurrent.notify()
	}

	func allTracks() -> [GpxTrack] {
		if let activeTrack = activeTrack {
			return [activeTrack] + savedTracks
		} else {
			return savedTracks
		}
	}

	func saveDirectory() -> String {
		return ArchivePath.gpxPoints.path()
	}

	// MARK: Caching

	// Number of days after which we automatically delete tracks
	// If zero then never delete them
	var expirationDays: Int {
		get {
			UserPrefs.shared.gpxTracksExpireAfterDays.value ?? Self.DefaultExpirationDays
		}
		set {
			UserPrefs.shared.gpxTracksExpireAfterDays.value = newValue
		}
	}

	var recordTracksInBackground: Bool {
		get {
			UserPrefs.shared.gpxRecordsTracksInBackground.value ?? false
		}
		set {
			UserPrefs.shared.gpxRecordsTracksInBackground.value = newValue

			NotificationCenter.default.post(
				name: NSNotification.Name("CollectGpxTracksInBackgroundChanged"),
				object: nil,
				userInfo: nil)
		}
	}

	// load data
	private func loadSavedTracks() -> [GpxTrack] {
		let deleteIfCreatedBefore = expirationDays == 0
			? Date.distantPast
			: Date(timeIntervalSinceNow: TimeInterval(-expirationDays * 24 * 60 * 60))

		let dir = saveDirectory()
		var files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []

		// file names are timestamps, so sort increasing newest first
		files = files.sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }.reversed()

		let tracks: [GpxTrack] = files.compactMap { file in
			guard file.hasSuffix(".track") else {
				return nil
			}
			let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
			guard
				let data = try? Data(contentsOf: url, options: .alwaysMapped),
				let track = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [GpxTrack.self,
				                                                                GpxPoint.self,
				                                                                NSDate.self,
				                                                                NSArray.self],
				                                                    from: data) as? GpxTrack
			else {
				return nil
			}

			if track.creationDate.timeIntervalSince(deleteIfCreatedBefore) < 0 {
				// skip because its too old
				delete(track: track)
				return nil
			}
			return track
		}
		return tracks
	}

	func getDiskCacheSize() async -> (size: Int, count: Int) {
		var size = 0
		let dir = saveDirectory()
		let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
		for file in files {
			if file.hasSuffix(".track") {
				let path = URL(fileURLWithPath: dir).appendingPathComponent(file).path
				var status = stat()
				stat((path as NSString).fileSystemRepresentation, &status)
				size += (Int(status.st_size) + 511) & -512
			}
		}
		return (size,
		        files.count + (activeTrack != nil ? 1 : 0))
	}

	func purgeTileCache() {
		let active = activeTrack != nil
		let stable = stabilizingCount

		endActiveTrack(continuingCurrentTrack: false)

		let dir = saveDirectory()
		try? FileManager.default.removeItem(atPath: dir)
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)

		if active {
			startNewTrack(continuingCurrentTrack: false)
			stabilizingCount = stable
		}

		onChangeTracks.notify()
		OnChangeCurrent.notify()
	}

	// Load a GPX trace from an external source
	@discardableResult
	func addGPX(track: GpxTrack) -> GpxTrack {
		// ensure the track doesn't already exist
		if let duplicate = savedTracks.first(where: { track.isEqual(to: $0) }) {
			// duplicate track
			return duplicate
		}

		savedTracks = (savedTracks + [track]).sorted { $0.creationDate > $1.creationDate }

		save(toDisk: track)
		selectedTrack = track
		return track
	}

	// Load a GPX trace from an external source
	@discardableResult
	func loadGpxTrack(with data: Data, name: String) throws -> GpxTrack? {
		let newTrack = try GpxTrack(xmlData: data)
		if name != "" {
			newTrack.name = name
		}
		return addGPX(track: newTrack)
	}
}
