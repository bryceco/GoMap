//
//  GpxTrackTestCase.swift
//  GoMapTests
//
//  Created by Bryce Cogswell on 10/4/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

@testable import Go_Map__
import XCTest

class GpxTrackTestCase: XCTestCase {

	// MARK: - Date Parsing

	/// Reference date from ISO8601DateFormatter for comparison.
	private func referenceDate(from string: String) -> Date? {
		let fmt = ISO8601DateFormatter()
		fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let d = fmt.date(from: string) { return d }
		fmt.formatOptions = [.withInternetDateTime]
		return fmt.date(from: string)
	}

	func testParseGpxTime_basicUTC() {
		let input = "2024-05-01T12:34:56Z"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_fractionalSeconds() {
		let input = "2024-05-01T12:34:56.789Z"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_positiveTimezoneOffset() {
		let input = "2026-10-03T14:00:03+02:00"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: "2026-10-03T12:00:03Z")
		else { return XCTFail("Failed to parse: \(input)") }
		// +02:00 means UTC time is 12:00:03
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_negativeTimezoneOffset() {
		let input = "2024-07-15T08:30:00-05:00"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: "2024-07-15T13:30:00Z")
		else { return XCTFail("Failed to parse: \(input)") }
		// -05:00 means UTC time is 13:30:00
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_fractionalSecondsWithTimezone() {
		let input = "2026-10-03T14:00:03.123+02:00"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: "2026-10-03T12:00:03.123Z")
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_epoch() {
		let input = "1970-01-01T00:00:00Z"
		guard let parsed = GpxPoint.parseGpxTime(input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970, 0.0, accuracy: 0.001, input)
	}

	func testParseGpxTime_y2k() {
		// Year 2000 is a leap year (divisible by 400)
		let input = "2000-01-01T00:00:00Z"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_leapYearFeb29() {
		let input = "2024-02-29T12:00:00Z"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_centuryNonLeapYear() {
		// 1900 is NOT a leap year (divisible by 100 but not 400)
		let input = "1900-03-01T00:00:00Z"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_variousYears() {
		// Test a spread of years to catch leap year calculation errors
		let dates = [
			"1971-06-15T10:20:30Z",
			"1999-12-31T23:59:59Z",
			"2000-02-29T00:00:00Z",
			"2004-02-29T12:00:00Z",
			"2010-07-04T18:30:00Z",
			"2020-03-01T00:00:00Z",
			"2026-10-03T14:00:03Z", // The date from the bug report
			"2030-01-01T00:00:00Z",
			"2100-03-01T00:00:00Z" // Century non-leap year in the future
		]
		for input in dates {
			guard let parsed = GpxPoint.parseGpxTime(input),
			      let expected = referenceDate(from: input)
			else { XCTFail("Failed to parse: \(input)"); continue }
			XCTAssertEqual(parsed.timeIntervalSince1970,
			               expected.timeIntervalSince1970,
			               accuracy: 0.001,
			               input)
		}
	}

	func testParseGpxTime_endOfDay() {
		let input = "2026-06-15T23:59:59Z"
		guard let parsed = GpxPoint.parseGpxTime(input),
		      let expected = referenceDate(from: input)
		else { return XCTFail("Failed to parse: \(input)") }
		XCTAssertEqual(parsed.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001,
		               input)
	}

	func testParseGpxTime_invalidInputs() {
		let invalid = [
			"",
			"not-a-date",
			"2024-13-01T00:00:00Z", // month > 12
			"2024-00-01T00:00:00Z", // month 0
			"2024-05-01", // no time component
			"2024-05-01 12:34:56Z", // space instead of T
			"12:34:56Z" // no date
		]
		for input in invalid {
			XCTAssertNil(GpxPoint.parseGpxTime(input), "Should not parse: \(input)")
		}
	}

	// MARK: - GPX Import/Export Round Trip

	private let sampleGpx = """
		<?xml version="1.0" encoding="UTF-8"?>
		<gpx creator="TestApp" version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
		  <metadata>
		    <time>2026-10-03T14:00:03Z</time>
		  </metadata>
		  <trk>
		    <name>Test Track</name>
		    <trkseg>
		      <trkpt lat="47.12345" lon="11.98765">
		        <time>2026-10-03T14:00:03Z</time>
		        <ele>512.5</ele>
		      </trkpt>
		      <trkpt lat="47.12400" lon="11.98800">
		        <time>2026-10-03T14:01:03Z</time>
		        <ele>515.0</ele>
		      </trkpt>
		      <trkpt lat="47.12500" lon="11.98900">
		        <time>2026-10-03T14:02:03Z</time>
		        <ele>520.0</ele>
		      </trkpt>
		    </trkseg>
		  </trk>
		  <wpt lat="47.13000" lon="11.99000">
		    <time>2026-10-03T14:05:00Z</time>
		    <ele>530.0</ele>
		    <name>Summit</name>
		    <desc>Nice view</desc>
		  </wpt>
		</gpx>
		"""

	private func importSampleTrack() -> GpxTrack? {
		guard let data = sampleGpx.data(using: .utf8),
		      let track = try? GpxTrack(xmlData: data)
		else { return nil }
		return track
	}

	private func roundTripTrack() -> GpxTrack? {
		guard let track = importSampleTrack(),
		      let exportedXml = track.gpxXmlString(),
		      let reimportedData = exportedXml.data(using: .utf8),
		      let track2 = try? GpxTrack(xmlData: reimportedData)
		else { return nil }
		return track2
	}

	func testImportGpx_pointCount() {
		guard let track = importSampleTrack()
		else { return XCTFail("Failed to import sample GPX") }
		XCTAssertEqual(track.points.count, 3)
		XCTAssertEqual(track.wayPoints.count, 1)
	}

	func testImportGpx_trackName() {
		guard let track = importSampleTrack()
		else { return XCTFail("Failed to import sample GPX") }
		XCTAssertEqual(track.name, "Test Track")
	}

	func testImportGpx_coordinates() {
		guard let track = importSampleTrack()
		else { return XCTFail("Failed to import sample GPX") }
		XCTAssertEqual(track.points[0].latLon.lat, 47.12345, accuracy: 0.00001)
		XCTAssertEqual(track.points[0].latLon.lon, 11.98765, accuracy: 0.00001)
	}

	func testImportGpx_timestamps() {
		guard let track = importSampleTrack(),
		      let timestamp = track.points[0].timestamp,
		      let expected = referenceDate(from: "2026-10-03T14:00:03Z")
		else { return XCTFail("Failed to import sample GPX or missing timestamp") }
		XCTAssertEqual(timestamp.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001)
	}

	func testImportGpx_elevation() {
		guard let track = importSampleTrack()
		else { return XCTFail("Failed to import sample GPX") }
		XCTAssertEqual(track.points[0].elevation, 512.5, accuracy: 0.01)
	}

	func testImportGpx_creationDate() {
		guard let track = importSampleTrack(),
		      let expected = referenceDate(from: "2026-10-03T14:00:03Z")
		else { return XCTFail("Failed to import sample GPX") }
		XCTAssertEqual(track.creationDate.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 0.001)
	}

	func testImportGpx_waypoint() {
		guard let track = importSampleTrack()
		else { return XCTFail("Failed to import sample GPX") }
		let wpt = track.wayPoints[0]
		XCTAssertEqual(wpt.latLon.lat, 47.13, accuracy: 0.00001)
		XCTAssertEqual(wpt.latLon.lon, 11.99, accuracy: 0.00001)
		XCTAssertEqual(wpt.elevation, 530.0, accuracy: 0.01)
		XCTAssertEqual(wpt.name, "Summit")
		XCTAssertEqual(wpt.desc, "Nice view")
	}

	func testImportGpx_duration() {
		guard let track = importSampleTrack()
		else { return XCTFail("Failed to import sample GPX") }
		// 14:02:03 - 14:00:03 = 120 seconds
		XCTAssertEqual(track.duration(), 120.0, accuracy: 0.001)
	}

	func testRoundTrip_preservesTimestamps() {
		guard let track = importSampleTrack(),
		      let track2 = roundTripTrack()
		else { return XCTFail("Round trip failed") }
		// Timestamps should survive the round trip
		XCTAssertEqual(track.points.count, track2.points.count)
		for (p1, p2) in zip(track.points, track2.points) {
			guard let t1 = p1.timestamp, let t2 = p2.timestamp
			else { XCTFail("Missing timestamp"); continue }
			XCTAssertEqual(t1.timeIntervalSince1970,
			               t2.timeIntervalSince1970,
			               accuracy: 1.0) // RFC 3339 export truncates to whole seconds
		}
	}

	func testRoundTrip_preservesCoordinates() {
		guard let track = importSampleTrack(),
		      let track2 = roundTripTrack()
		else { return XCTFail("Round trip failed") }
		for (p1, p2) in zip(track.points, track2.points) {
			XCTAssertEqual(p1.latLon.lat, p2.latLon.lat, accuracy: 0.000001)
			XCTAssertEqual(p1.latLon.lon, p2.latLon.lon, accuracy: 0.000001)
		}
	}

	func testRoundTrip_preservesElevation() {
		guard let track = importSampleTrack(),
		      let track2 = roundTripTrack()
		else { return XCTFail("Round trip failed") }
		for (p1, p2) in zip(track.points, track2.points) {
			XCTAssertEqual(p1.elevation, p2.elevation, accuracy: 0.01)
		}
	}

	func testRoundTrip_preservesTrackName() {
		guard let track = importSampleTrack(),
		      let track2 = roundTripTrack()
		else { return XCTFail("Round trip failed") }
		XCTAssertEqual(track.name, track2.name)
	}

	func testRoundTrip_preservesWaypoints() {
		guard let track = importSampleTrack(),
		      let track2 = roundTripTrack()
		else { return XCTFail("Round trip failed") }
		XCTAssertEqual(track.wayPoints.count, track2.wayPoints.count)
		for (w1, w2) in zip(track.wayPoints, track2.wayPoints) {
			XCTAssertEqual(w1.latLon.lat, w2.latLon.lat, accuracy: 0.000001)
			XCTAssertEqual(w1.latLon.lon, w2.latLon.lon, accuracy: 0.000001)
			XCTAssertEqual(w1.elevation, w2.elevation, accuracy: 0.01)
			XCTAssertEqual(w1.name, w2.name)
			XCTAssertEqual(w1.desc, w2.desc)
			guard let t1 = w1.timestamp, let t2 = w2.timestamp
			else { XCTFail("Missing waypoint timestamp"); continue }
			XCTAssertEqual(t1.timeIntervalSince1970,
			               t2.timeIntervalSince1970,
			               accuracy: 1.0)
		}
	}

	func testRoundTrip_datesMatchReference() {
		// Verify that after import → export → re-import, dates still match
		// the original ISO8601 reference (catches the +8 day bug)
		guard let track2 = roundTripTrack(),
		      let timestamp = track2.points[0].timestamp,
		      let expected = referenceDate(from: "2026-10-03T14:00:03Z")
		else { return XCTFail("Round trip failed or missing timestamp") }
		XCTAssertEqual(timestamp.timeIntervalSince1970,
		               expected.timeIntervalSince1970,
		               accuracy: 1.0,
		               "Date should still be Oct 3, not shifted")
	}

	// MARK: - Import Error Cases

	func testImportGpx_emptyData() {
		XCTAssertThrowsError(try GpxTrack(xmlData: Data())) { error in
			XCTAssertEqual(error as? GpxError, .noData)
		}
	}

	func testImportGpx_singlePoint() {
		let gpx = """
			<?xml version="1.0"?>
			<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
			  <trk><trkseg>
			    <trkpt lat="47.0" lon="11.0"><time>2026-01-01T00:00:00Z</time></trkpt>
			  </trkseg></trk>
			</gpx>
			"""
		guard let data = gpx.data(using: .utf8)
		else { return XCTFail("Failed to encode GPX string") }
		XCTAssertThrowsError(try GpxTrack(xmlData: data)) { error in
			XCTAssertEqual(error as? GpxError, .fewerThanTwoPoints)
		}
	}

	func testImportGpx_waypointOnlyIsValid() {
		let gpx = """
			<?xml version="1.0"?>
			<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
			  <wpt lat="47.0" lon="11.0">
			    <name>Marker</name>
			  </wpt>
			</gpx>
			"""
		guard let data = gpx.data(using: .utf8),
		      let track = try? GpxTrack(xmlData: data)
		else { return XCTFail("Failed to import waypoint-only GPX") }
		XCTAssertEqual(track.wayPoints.count, 1)
		XCTAssertEqual(track.points.count, 0)
	}

	func testImportGpx_noTimestamps() {
		let gpx = """
			<?xml version="1.0"?>
			<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
			  <trk><trkseg>
			    <trkpt lat="47.0" lon="11.0"></trkpt>
			    <trkpt lat="47.1" lon="11.1"></trkpt>
			  </trkseg></trk>
			</gpx>
			"""
		guard let data = gpx.data(using: .utf8),
		      let track = try? GpxTrack(xmlData: data)
		else { return XCTFail("Failed to import GPX without timestamps") }
		XCTAssertEqual(track.points.count, 2)
		XCTAssertNil(track.points[0].timestamp)
		XCTAssertNil(track.points[1].timestamp)
		XCTAssertEqual(track.duration(), 0.0)
	}

	func testImportGpx_namespacePrefixes() {
		// Some GPS devices emit namespace-prefixed elements
		let gpx = """
			<?xml version="1.0"?>
			<ns1:gpx version="1.1" xmlns:ns1="http://www.topografix.com/GPX/1/1">
			  <ns1:trk><ns1:trkseg>
			    <ns1:trkpt lat="47.0" lon="11.0">
			      <ns1:time>2026-01-01T12:00:00Z</ns1:time>
			    </ns1:trkpt>
			    <ns1:trkpt lat="47.1" lon="11.1">
			      <ns1:time>2026-01-01T12:01:00Z</ns1:time>
			    </ns1:trkpt>
			  </ns1:trkseg></ns1:trk>
			</ns1:gpx>
			"""
		guard let data = gpx.data(using: .utf8),
		      let track = try? GpxTrack(xmlData: data)
		else { return XCTFail("Failed to import namespace-prefixed GPX") }
		XCTAssertEqual(track.points.count, 2)
	}
}
