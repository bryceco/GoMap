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
	/// Creates a test node with the given tags at the origin.
	private func makeNode(tags: [String: String] = [:]) -> OsmNode {
		return OsmNode(withVersion: 1, changeset: 0, user: "", uid: 0,
		               ident: OsmBaseObject.nextUnusedIdentifier(),
		               timestamp: "", tags: tags, latLon: .zero)
	}

	func testLowerBoundOfDirectionShouldBeNotFoundIfNoDirectionTagExists() {
		let node = makeNode()

		XCTAssertNil(node.direction)
	}

	func testDirectionShouldUseTheDirectionTagForLowerBound() {
		let key = "direction"
		let direction = 42

		let node = makeNode(tags: [key: "\(direction)"])

		XCTAssertEqual(node.direction?.direction.start, direction)
	}

	func testDirectionShouldUseTheCameraDirectionTagForLowerBound() {
		let key = "camera:direction"
		let direction = 42

		let node = makeNode(tags: [key: "\(direction)"])

		XCTAssertEqual(node.direction?.direction.start, direction)
	}

	func testTechnicalDirectionTagKeyPrefersDirectionOverCameraDirection() {
		let node = makeNode(tags: ["direction": "90", "camera:direction": "180"])

		XCTAssertEqual(node.direction?.key, "direction")
	}

	func testTechnicalDirectionTagKeyUsesCameraDirectionWhenDirectionAbsent() {
		let node = makeNode(tags: ["camera:direction": "45"])

		XCTAssertEqual(node.direction?.key, "camera:direction")
	}

	func testTechnicalDirectionTagKeyIsNilForHighwayForwardBackward() {
		let node = makeNode(tags: ["highway": "stop", "direction": "forward"])

		XCTAssertNil(node.direction)
	}

	func testDirectionTagValueFormatsPointBearing() {
		let node = makeNode(tags: ["direction": "10"])

		XCTAssertEqual(node.direction?.direction.with(start: 95).valueString(), "95")
	}

	func testDirectionTagValuePreservesRangeSpan() {
		let node = makeNode(tags: ["direction": "90-120"])

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
			let node = makeNode(tags: [key: cardinalDirection])

			XCTAssertEqual(node.direction?.direction.start, expectedDirection)
		}
	}
}
