//
//  LocationURLParserTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 2/2/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import XCTest
@testable import Go_Map__

class LocationURLParserTestCase: XCTestCase {
    
    var parser: GeoURLParser!

    override func setUp() {
        super.setUp()
        
        parser = GeoURLParser()
    }

    override func tearDown() {
        parser = nil
        
        super.tearDown()
    }

    func testParseURL_withSchemeThatIsNotGeo_shouldResultInNil() {
        /// Given
        let url = URL(string: "https://openstreetmap.org/").require()
        
        /// When
        let result = parser.parseURL(url)
        
        /// Then
        XCTAssertNil(result)
    }

    func testParseURL_withNonNumericalLatitude_shouldResultInNil() {
        /// Given
        let url = URL(string: "geo:foo,1?z=2").require()
        
        /// When
        let result = parser.parseURL(url)
        
        /// Then
        XCTAssertNil(result)
    }

    func testParseURL_withNonNumericalLongitude_shouldResultInNil() {
        /// Given
        let url = URL(string: "geo:1,bar?z=2").require()
        
        /// When
        let result = parser.parseURL(url)
        
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
        let result = parser.parseURL(url).require()
        
        /// Then
        XCTAssertEqual(result.latitude, latitude)
        XCTAssertEqual(result.longitude, longitude)
        XCTAssertEqual(result.zoom, zoom)
        XCTAssertEqual(result.viewState, MAPVIEW_NONE)
    }

    func testParseURL_withURLThatContainsSemicolonsBetweenCoordinatesAndZoom_shouldNotResultInNil() {
        /// Given
        let url = URL(string: "geo:1,2;;;;;;;;;;;;;;;;;;;;;?z=3").require()
        
        /// When
        let result = parser.parseURL(url)
        
        /// Then
        XCTAssertNotNil(result)
    }

    func testParseURL_withURLThatHasANonNumericalZoomParameter_shouldDefaultToZoom0() {
        /// Given
        let url = URL(string: "geo:1,2?z=loremipsum").require()
        
        /// When
        let result = parser.parseURL(url).require()
        
        /// Then
        XCTAssertEqual(result.zoom, 0)
    }

    func testParseURL_withURLThatDoesNotHaveTheZoomParameter_shouldDefaultToZoom0() {
        /// Given
        let url = URL(string: "geo:1,2").require()
        
        /// When
        let result = parser.parseURL(url).require()
        
        /// Then
        XCTAssertEqual(result.zoom, 0)
    }

}
