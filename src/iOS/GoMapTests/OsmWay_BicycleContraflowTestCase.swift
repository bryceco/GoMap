//
//  OsmWay_BicycleContraflowTestCase.swift
//  GoMapTests
//

@testable import Go_Map__
import XCTest

class OsmWay_BicycleContraflowTestCase: XCTestCase {
	func testAllowsBicycleContraflowWhenOneWayAndOnewayBicycleNo() {
		let way = OsmWay(asUserCreated: "")
		way.constructTag("oneway", value: "yes")
		way.constructTag("oneway:bicycle", value: "no")

		XCTAssertTrue(way.allowsBicycleContraflow())
	}

	func testAllowsBicycleContraflowWhenOneWayBackwardAndOnewayBicycleNo() {
		let way = OsmWay(asUserCreated: "")
		way.constructTag("oneway", value: "-1")
		way.constructTag("oneway:bicycle", value: "no")

		XCTAssertTrue(way.allowsBicycleContraflow())
	}

	func testDoesNotAllowBicycleContraflowWithoutOnewayBicycleNo() {
		let way = OsmWay(asUserCreated: "")
		way.constructTag("oneway", value: "yes")

		XCTAssertFalse(way.allowsBicycleContraflow())
	}

	func testDoesNotAllowBicycleContraflowWhenNotOneWay() {
		let way = OsmWay(asUserCreated: "")
		way.constructTag("oneway:bicycle", value: "no")

		XCTAssertFalse(way.allowsBicycleContraflow())
	}
}
