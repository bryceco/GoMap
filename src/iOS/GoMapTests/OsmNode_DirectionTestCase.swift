//
//  OsmNode_DirectionTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/10/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

@testable import Go_Map__
import XCTest

class OsmNode_DirectionTestCase: XCTestCase {
	func testLowerBoundOfDirectionShouldBeNotFoundIfNoDirectionTagExists() {
		let node = OsmNode(asUserCreated: "")

		XCTAssertNil(node.direction)
	}

	func testDirectionShouldUseTheDirectionTagForLowerBound() {
		let key = "direction"
		let direction = 42

		let node = OsmNode(asUserCreated: "")
		node.constructTag(key, value: "\(direction)")

		XCTAssertEqual(node.direction?.direction.start, direction)
	}

	func testDirectionShouldUseTheCameraDirectionTagForLowerBound() {
		let key = "camera:direction"
		let direction = 42

		let node = OsmNode(asUserCreated: "")
		node.constructTag(key, value: "\(direction)")

		XCTAssertEqual(node.direction?.direction.start, direction)
	}

	func testTechnicalDirectionTagKeyPrefersDirectionOverCameraDirection() {
		let node = OsmNode(asUserCreated: "")
		node.constructTag("direction", value: "90")
		node.constructTag("camera:direction", value: "180")

		XCTAssertEqual(node.direction?.key, "direction")
	}

	func testTechnicalDirectionTagKeyUsesCameraDirectionWhenDirectionAbsent() {
		let node = OsmNode(asUserCreated: "")
		node.constructTag("camera:direction", value: "45")

		XCTAssertEqual(node.direction?.key, "camera:direction")
	}

	func testTechnicalDirectionTagKeyIsNilForHighwayForwardBackward() {
		let node = OsmNode(asUserCreated: "")
		node.constructTag("highway", value: "stop")
		node.constructTag("direction", value: "forward")

		XCTAssertNil(node.direction)
	}

	func testDirectionTagValueFormatsPointBearing() {
		let node = OsmNode(asUserCreated: "")
		node.constructTag("direction", value: "10")

		XCTAssertEqual(node.direction?.direction.with(start: 95).valueString(), "95")
	}

	func testDirectionTagValuePreservesRangeSpan() {
		let node = OsmNode(asUserCreated: "")
		node.constructTag("direction", value: "90-120")

		XCTAssertEqual(node.direction?.direction.with(start: 0).valueString(), "0-30")
	}

	func testDirectionShouldParseCardinalDirectionToLowerBound() {
		let key = "camera:direction"

		let cardinalDirectionToDegree: [String: Int] = ["N": 0,
		                                                "NE": 45,
		                                                "E": 90,
		                                                "SE": 135,
		                                                "S": 180,
		                                                "SW": 225,
		                                                "W": 270,
		                                                "NW": 315]
		for (cardinalDirection, expectedDirection) in cardinalDirectionToDegree {
			let node = OsmNode(asUserCreated: "")
			node.constructTag(key, value: cardinalDirection)

			XCTAssertEqual(node.direction?.direction.start, expectedDirection)
		}
	}
}
