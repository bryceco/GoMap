//
//  GpxLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 2/22/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

import CoreLocation.CLLocation
import UIKit

final class GpxLayer: DrawingLayer, GetDiskCacheSize, DrawingLayerDelegate {
	private static let DefaultExpirationDays = 7
	var stabilizingCount = 0

	private(set) var activeTrack: GpxTrack? // track currently being recorded

	// track picked in view controller
	weak var selectedTrack: GpxTrack? {
		didSet {
			// update for color change of selected track
			setNeedsLayout()
		}
	}

	private(set) var previousTracks: [GpxTrack] = [] // sorted with most recent first

	override init(mapView: MapView) {
		let uploads = UserPrefs.shared.gpxUploadedGpxTracks.value ?? [:]
		uploadedTracks = uploads.mapValues({ $0.boolValue })
		super.init(mapView: mapView)
		super.geojsonDelegate = self
	}

	var uploadedTracks: [String: Bool] {
		didSet {
			let dict = uploadedTracks.mapValues({ NSNumber(value: $0) })
			UserPrefs.shared.gpxUploadedGpxTracks.value = dict
		}
	}

	func startNewTrack() {
		if activeTrack != nil {
			endActiveTrack()
		}
		activeTrack = GpxTrack()
		stabilizingCount = 0
		selectedTrack = activeTrack

		if #available(iOS 16.2, *) {
			GpxTrackWidgetManager.shared.startTrack(fromWidget: false)
		}
	}

	func endActiveTrack() {
		if let activeTrack = activeTrack {
			// redraw shape with archive color
			setNeedsLayout()

			activeTrack.finish()

			if #available(iOS 16.2, *) {
				GpxTrackWidgetManager.shared.endTrack(fromWidget: false)
			}

			// add to list of previous tracks
			if activeTrack.points.count > 1 {
				previousTracks.insert(activeTrack, at: 0)
			}

			save(toDisk: activeTrack)
			self.activeTrack = nil
			selectedTrack = nil
		}
	}

	func save(toDisk track: GpxTrack) {
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
		if let activeTrack = activeTrack {
			save(toDisk: activeTrack)
		}
	}

	func delete(_ track: GpxTrack) {
		let path = URL(fileURLWithPath: saveDirectory()).appendingPathComponent(track.fileName()).path
		try? FileManager.default.removeItem(atPath: path)
		previousTracks.removeAll { $0 === track }
		uploadedTracks.removeValue(forKey: track.name)
		setNeedsLayout()
	}

	func markTrackUploaded(_ track: GpxTrack) {
		uploadedTracks[track.name] = true
	}

	// Removes GPX tracks older than date.
	// This is called when the user selects a new age limit for tracks.
	func trimTracksOlderThan(_ date: Date) {
		while let track = previousTracks.last {
			let point = track.points[0]
			if let timestamp1 = point.timestamp {
				if date.timeIntervalSince(timestamp1) > 0 {
					// delete oldest
					delete(track)
				} else {
					break
				}
			}
		}
	}

	func totalPointCount() -> Int {
		var total = activeTrack?.points.count ?? 0
		for track in previousTracks {
			total += track.points.count
		}
		return total
	}

	func addPoint(_ location: CLLocation) {
		if let activeTrack = activeTrack {
			defer {
				if #available(iOS 16.2, *) {
					GpxTrackWidgetManager.shared.updateTrack()
				}
			}
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
			let saveInterval = UIApplication.shared
				.applicationState == .active ? 30 : 180 // save less frequently if we're in the background

			if activeTrack.points.count % saveInterval == 0 {
				saveActiveTrack()
			}

			// if the number of points is too large then the periodic save will begin taking too long,
			// and drawing performance will degrade, so start a new track every hour
			if activeTrack.points.count >= 3600 {
				endActiveTrack()
				startNewTrack()
				stabilizingCount = 100 // already stable
				addPoint(location)
			}

			setNeedsLayout()
		}
	}

	func allTracks() -> [GpxTrack] {
		if let activeTrack = activeTrack {
			return [activeTrack] + previousTracks
		} else {
			return previousTracks
		}
	}

	// Delegate function to provide GeoJSONLayer with data
	func geojsonData() -> [(GeoJSONGeometry, UIColor)] {
		return allTracks().compactMap {
			let color = $0 == selectedTrack
				? UIColor.red
				: UIColor(red: 1.0,
				          green: 99 / 255.0,
				          blue: 249 / 255.0,
				          alpha: 1.0)
			return ($0.geoJSON, color)
		}
	}

	func saveDirectory() -> String {
		return ArchivePath.gpxPoints.path()
	}

	override func action(forKey key: String) -> CAAction? {
		switch key {
		case "transform",
		     "bounds",
		     "position":
			return nil
		default:
			return super.action(forKey: key)
		}
	}

	// MARK: Caching

	// Number of days after which we automatically delete tracks
	// If zero then never delete them
	static var expirationDays: Int {
		get {
			UserPrefs.shared.gpxTracksExpireAfterDays.value ?? Self.DefaultExpirationDays
		}
		set {
			UserPrefs.shared.gpxTracksExpireAfterDays.value = newValue
		}
	}

	static var backgroundTracking: Bool {
		get {
			UserPrefs.shared.gpxRecordsTracksInBackground.value ?? false
		}
		set {
			UserPrefs.shared.gpxRecordsTracksInBackground.value = newValue
		}
	}

	// load data if not already loaded
	var didLoadSavedTracks = false
	func loadTracksInBackground(withProgress progressCallback: (() -> Void)?) {
		if didLoadSavedTracks {
			return
		}
		didLoadSavedTracks = true

		let expiration = GpxLayer.expirationDays
		let deleteIfCreatedBefore = expiration == 0 ? Date.distantPast
			: Date(timeIntervalSinceNow: TimeInterval(-expiration * 24 * 60 * 60))

		DispatchQueue.global(qos: .default).async(execute: { [self] in
			let dir = saveDirectory()
			var files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []

			// file names are timestamps, so sort increasing newest first
			files = files.sorted { $0.compare($1, options: .caseInsensitive) == .orderedAscending }.reversed()

			for file in files {
				if file.hasSuffix(".track") {
					let url = URL(fileURLWithPath: dir).appendingPathComponent(file)
					guard
						let data = try? Data(contentsOf: url, options: .alwaysMapped),
						let track = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [GpxTrack.self,
						                                                                GpxPoint.self,
						                                                                NSDate.self,
						                                                                NSArray.self],
						                                                    from: data) as? GpxTrack
					else {
						continue
					}

					if track.creationDate.timeIntervalSince(deleteIfCreatedBefore) < 0 {
						// skip because its too old
						DispatchQueue.main.async(execute: { [self] in
							delete(track)
						})
						continue
					}
					DispatchQueue.main.async(execute: { [self] in
						previousTracks.append(track)
						setNeedsLayout()
						if let progressCallback = progressCallback {
							progressCallback()
						}
					})
				}
			}
		})
	}

	func getDiskCacheSize() -> (size: Int, count: Int) {
		var size = 0
		let dir = saveDirectory()
		var files: [String] = []
		do {
			files = try FileManager.default.contentsOfDirectory(atPath: dir)
		} catch {}
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

		endActiveTrack()
		sublayers = nil

		let dir = saveDirectory()
		do {
			try FileManager.default.removeItem(atPath: dir)
		} catch {}
		do {
			try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
		} catch {}

		setNeedsLayout()

		if active {
			startNewTrack()
			stabilizingCount = stable
		}
	}

	func center(on track: GpxTrack) {
		let center: GpxPoint
		if let wayPoint = track.wayPoints.first {
			center = wayPoint
		} else {
			// get midpoint
			let mid = track.points.count / 2
			guard mid < track.points.count else {
				return
			}
			center = track.points[mid]
		}
		mapView.centerOn(latLon: center.latLon, metersWide: 20.0)
	}

	// Load a GPX trace from an external source
	func addGPX(track: GpxTrack, center: Bool) {
		// ensure the track doesn't already exist
		if previousTracks.contains(where: {
			$0.name == track.name &&
				$0.points.count == track.points.count &&
				$0.points.first?.latLon == track.points.first?.latLon &&
				$0.points.last?.latLon == track.points.last?.latLon
		}) {
			// duplicate track
			return
		}
		previousTracks.append(track)
		previousTracks.sort(by: { $0.creationDate > $1.creationDate })

		if center {
			self.center(on: track)
			selectedTrack = track
			mapView.displayGpxLogs = true // ensure GPX tracks are visible
		}
		save(toDisk: track)
	}

	// Load a GPX trace from an external source
	func loadGPXData(_ data: Data, center: Bool) throws {
		let newTrack = try GpxTrack(xmlData: data)
		addGPX(track: newTrack, center: center)
	}

	// MARK: Properties

	override var isHidden: Bool {
		get {
			return super.isHidden
		}
		set(hidden) {
			let wasHidden = isHidden
			super.isHidden = hidden

			if wasHidden, !hidden {
				loadTracksInBackground(withProgress: nil)
				setNeedsLayout()
			}
		}
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
