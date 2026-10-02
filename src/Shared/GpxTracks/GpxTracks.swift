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

	/// The total point count across all chunks of the current recording session.
	var activeTrackTotalPointCount: Int {
		// nonGpxTracks holds previous chunks from the current session (cleared after consolidation)
		return nonGpxTracks.reduce(0, { $0 + $1.points.count }) + (activeTrack?.points.count ?? 0)
	}

	/// The original start date of the current recording session (before any splits).
	var activeTrackStartDate: Date? {
		// nonGpxTracks is newest-first, so .last is the oldest (original) chunk
		return nonGpxTracks.last?.creationDate ?? activeTrack?.creationDate
	}

	let onChangeTracks = NotificationService<Void>()
	let OnChangeCurrent = NotificationService<Void>()

	init() {
		let uploads = UserPrefs.shared.gpxUploadedGpxTracks.value ?? [:]
		// Migrate old keys that used "1234567.890.track" format to fileBaseName()
		uploadedTracks = Dictionary(uniqueKeysWithValues: uploads.map { key, value in
			let migratedKey = key.hasSuffix(".track") ? String(key.dropLast(6)) : key
			return (migratedKey, value.boolValue)
		})
	}

	// all tracks except the active track, sorted with most recent first
	private(set) lazy var savedTracks: [GpxTrack] = consolidateTrackFiles(loadSavedTracks()) {
		didSet {
			onChangeTracks.notify()
		}
	}

	private(set) var activeTrack: GpxTrack? { // track currently being recorded
		didSet {
			OnChangeCurrent.notify()
		}
	}

	private var nonGpxTracks: [GpxTrack] = []

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
		nonGpxTracks.insert(activeTrack, at: 0) // newest-first, like nonGpxTracks ordering
		self.activeTrack = nil
		selectedTrack = nil

		if !continuingCurrentTrack {
			savedTracks = consolidateTrackFiles(savedTracks)
		}
	}

	private func save(toDisk track: GpxTrack) {
		if track.points.count >= 2 || track.wayPoints.count > 0 {
			// make sure save directory exists
			var time = TimeInterval(CACurrentMediaTime())
			let dir = saveDirectory()
			let path = dir.appendingPathComponent(track.fileTrackName())
			do {
				try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
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

	private func deleteFile(for track: GpxTrack) {
		let dir = saveDirectory()
		// Remove both current and legacy filenames
		for base in [track.fileBaseName(), track.legacyFileBaseName()] {
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(base + ".track"))
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(base + ".gpx"))
		}
		uploadedTracks.removeValue(forKey: track.name ?? track.fileBaseName())
	}

	func delete(track: GpxTrack) {
		deleteFile(for: track)
		savedTracks = savedTracks.filter { $0 !== track } // assign to trigger notification
		onChangeTracks.notify()
	}

	func markTrackUploaded(_ track: GpxTrack) {
		uploadedTracks[track.name ?? track.fileBaseName()] = true
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

	func saveDirectory() -> URL {
		return ArchivePath.gpxPoints.url()
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

	/// Parse a single file into a GpxTrack, or nil if it can't be parsed.
	private static func parseTrackFile(url: URL, file: String) -> (track: GpxTrack, isTrackFile: Bool)? {
		if file.hasSuffix(".gpx") {
			guard
				let data = try? Data(contentsOf: url),
				let decoded = try? GpxTrack(xmlData: data)
			else {
				return nil
			}
			return (decoded, false)
		} else if file.hasSuffix(".track") {
			guard
				let data = try? Data(contentsOf: url, options: .alwaysMapped),
				let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [GpxTrack.self,
				                                                                  GpxPoint.self,
				                                                                  NSDate.self,
				                                                                  NSArray.self],
				                                                      from: data) as? GpxTrack
			else {
				return nil
			}
			return (decoded, true)
		}
		return nil
	}

	// load data
	private func loadSavedTracks() -> [GpxTrack] {
		let deleteIfCreatedBefore = expirationDays == 0
			? Date.distantPast
			: Date(timeIntervalSinceNow: TimeInterval(-expirationDays * 24 * 60 * 60))

		let dir = saveDirectory()
		let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
		let trackFiles = files.filter { $0.hasSuffix(".gpx") || $0.hasSuffix(".track") }

		// Parse files in parallel
		var results = [(track: GpxTrack, isTrackFile: Bool)?](repeating: nil, count: trackFiles.count)
		DispatchQueue.concurrentPerform(iterations: trackFiles.count) { index in
			let file = trackFiles[index]
			let url = dir.appendingPathComponent(file)
			results[index] = Self.parseTrackFile(url: url, file: file)
		}

		// Collect results sequentially
		nonGpxTracks = []
		var tracks: [GpxTrack] = []
		for result in results {
			guard let (track, isTrackFile) = result else { continue }
			if track.creationDate.timeIntervalSince(deleteIfCreatedBefore) < 0 {
				deleteFile(for: track)
				continue
			}
			if isTrackFile {
				nonGpxTracks.append(track)
			}
			tracks.append(track)
		}

		// sort newest first
		tracks.sort { $0.creationDate > $1.creationDate }
		nonGpxTracks.sort { $0.creationDate > $1.creationDate }
		return tracks
	}

	/// Consolidates .track files that are continuations of each other into single .gpx files.
	/// Returns the updated track list with non-gpx tracks replaced by merged tracks.
	private func consolidateTrackFiles(_ tracks: [GpxTrack]) -> [GpxTrack] {
		guard !nonGpxTracks.isEmpty else { return tracks }

		let maxGapSeconds: TimeInterval = 5
		let dir = saveDirectory()

		// Walk oldest to newest, appending continuations onto the oldest track in each group
		var current = nonGpxTracks.last!
		var mergedTracks: [GpxTrack] = []

		for newerTrack in nonGpxTracks.reversed().dropFirst() {
			if let currentLast = current.points.last?.timestamp,
			   let newerFirst = newerTrack.points.first?.timestamp,
			   newerFirst.timeIntervalSince(currentLast) < maxGapSeconds
			{
				// continuation: append newer points into current
				current.appendPoints(from: newerTrack)
			} else {
				// gap: finalize current and start a new group
				mergedTracks.append(current)
				current = newerTrack
			}
		}
		mergedTracks.append(current)

		// Write merged tracks as .gpx files
		for track in mergedTracks {
			if let gpxData = track.gpxXmlData() {
				try? gpxData.write(to: dir.appendingPathComponent(track.fileGpxName()))
			}
		}

		// Delete all the original .track files (try both current and legacy filenames)
		for track in nonGpxTracks {
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(track.fileTrackName()))
			try? FileManager.default.removeItem(at: dir.appendingPathComponent(track.legacyFileBaseName() + ".track"))
		}

		// Replace nonGpxTracks entries with the merged tracks
		let nonGpxSet = Set(nonGpxTracks.map { ObjectIdentifier($0) })
		nonGpxTracks = []
		return (tracks.filter { !nonGpxSet.contains(ObjectIdentifier($0)) } + mergedTracks)
			.sorted { $0.creationDate > $1.creationDate }
	}

	func getDiskCacheSize() async -> (size: Int, count: Int) {
		var size = 0
		let dir = saveDirectory()
		let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
		for file in files {
			if file.hasSuffix(".track") || file.hasSuffix(".gpx") {
				let path = dir.appendingPathComponent(file).path
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
		try? FileManager.default.removeItem(at: dir)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

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
