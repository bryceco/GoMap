//
//  LocationURLParserTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

@testable import Go_Map__
import XCTest

class LocationURLParserTestCase: XCTestCase {
	var parser: LocationParser!

	override func setUp() {
		super.setUp()

		parser = LocationParser()
	}

	override func tearDown() {
		parser = nil

		super.tearDown()
	}

	func testParseURL_withSchemeThatIsNotGeo_shouldResultInNil() {
		/// Given
		let url = URL(string: "https://openstreetmap.org/").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url)

		/// Then
		XCTAssertNil(result)
	}

	func testParseURL_withNonNumericalLatitude_shouldResultInNil() {
		/// Given
		let url = URL(string: "geo:foo,1?z=2").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url)

		/// Then
		XCTAssertNil(result)
	}

	func testParseURL_withNonNumericalLongitude_shouldResultInNil() {
		/// Given
		let url = URL(string: "geo:1,bar?z=2").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url)

		/// Then
		XCTAssertNil(result)
	}

	func testParseURL_withProperURL_shouldReturnProperResult() {
		/// Given
		let latitude: Double = 1
		let longitude: Double = 2
		let zoom: Double = 3
		let url = URL(string: "geo:\(latitude),\(longitude)?z=\(zoom)").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url).require()

		/// Then
		XCTAssertEqual(result.latitude, latitude)
		XCTAssertEqual(result.longitude, longitude)
		XCTAssertEqual(result.zoom, zoom)
		XCTAssertEqual(result.view, nil)
	}

	func testParseURL_withURLThatContainsSemicolonsBetweenCoordinatesAndZoom_shouldNotResultInNil() {
		/// Given
		let url = URL(string: "geo:1,2;;;;;;;;;;;;;;;;;;;;;?z=3").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url)

		/// Then
		XCTAssertNotNil(result)
	}

	func testParseURL_withURLThatHasANonNumericalZoomParameter_shouldDefaultToZoom0() {
		/// Given
		let url = URL(string: "geo:1,2?z=loremipsum").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url).require()

		/// Then
		XCTAssertEqual(result.zoom, 0)
	}

	func testParseURL_withURLThatDoesNotHaveTheZoomParameter_shouldDefaultToZoom0() {
		/// Given
		let url = URL(string: "geo:1,2").require()

		/// When
		let result = LocationParser.mapLocationFrom(url: url).require()

		/// Then
		XCTAssertEqual(result.zoom, 0)
	}

	func testParseString_coordinateFormats() {
		// Use .nan for lat/lon to indicate the parse is expected to fail (return nil).
		typealias Case = (string: String, lat: Double, lon: Double)
		let cases: [Case] = [
			// Decimal degrees + NSEW suffix
			("14.004° N, 44.695° E", 14.004, 44.695), // lat-first
			("44.695° E, 14.004° N", 14.004, 44.695), // lon-first

			// DMS + NSEW prefix (comma required; space alone causes E to be consumed as firstDir2)
			("N26°35'36\",E106°40'44\"", 26.5933, 106.6789), // lat-first
			("S33°51'54\",E151°12'34\"", -33.865, 151.2094), // S negates lat
			("E106°40'44\",N26°35'36\"", 26.5933, 106.6789), // lon-first

			// DMS + NSEW suffix
			("26°35.7'N 106°40.44'E", 26.595, 106.674), // decimal minutes (no seconds)
			("26°35'36\"N 106°40'44\"E", 26.5933, 106.6789), // lat-first, space separator
			("19°33'51.6\"N+155°56'07.7\"W", 19.5643, -155.9355), // + separator, decimal seconds, W negates lon
			("49° 56\u{2032} 49\u{2033} W, 41° 43\u{2032} 57\u{2033} N", 41.7325, -49.9469), // unicode primes

			// Bare decimal pair (fallback scanner)
			("47.75538, -122.15979", 47.75538, -122.15979),
			("\u{2212}33.8688, 151.2093", -33.8688, 151.2093), // U+2212 minus normalised to hyphen
			("xxx 47.5°, 122.3° xxx", 47.5, 122.3), // coordinates embedded in longer text
			("xxx 47.75538, -122.15979 xxx", 47.75538, -122.15979), // coordinates embedded in longer text

			// Failure cases — NSEW on first coordinate only; second has no direction indicator
			("47.5° N, 122.3°", .nan, .nan),
			("47.5° S, 122.3°", .nan, .nan)
		]

		let accuracy = 0.0001
		for (string, expectedLat, expectedLon) in cases {
			if expectedLat.isNaN {
				XCTAssertNil(LocationParser.mapLocationFrom(string: string), string)
			} else {
				guard let result = LocationParser.mapLocationFrom(string: string) else {
					XCTFail("Failed to parse: \(string)")
					continue
				}
				XCTAssertEqual(result.latitude, expectedLat, accuracy: accuracy, string)
				XCTAssertEqual(result.longitude, expectedLon, accuracy: accuracy, string)
			}
		}
	}
}
