//
//  POITabBarControllerTestCase.swift
//  GoMapTests
//

@testable import Go_Map__
import XCTest

class POITabBarControllerTestCase: XCTestCase {
	// MARK: shouldHideAttributesTab

	func testShouldHideAttributesTabIsTrueForNilSelection() {
		XCTAssertTrue(POITabBarController.shouldHideAttributesTab(for: nil))
	}

	func testShouldHideAttributesTabIsTrueForPendingNode() {
		let node = OsmNode(asUserCreated: "")
		XCTAssertLessThan(node.ident, 0)
		XCTAssertTrue(POITabBarController.shouldHideAttributesTab(for: node))
	}

	func testShouldHideAttributesTabIsFalseForUploadedNode() {
		let node = OsmNode(
			withVersion: 1,
			changeset: 0,
			user: "",
			uid: 0,
			ident: 1,
			timestamp: "",
			tags: [:])
		XCTAssertGreaterThan(node.ident, 0)
		XCTAssertFalse(POITabBarController.shouldHideAttributesTab(for: node))
	}

	func testShouldHideAttributesTabIsTrueForPendingWay() {
		let way = OsmWay(asUserCreated: "")
		XCTAssertLessThan(way.ident, 0)
		XCTAssertTrue(POITabBarController.shouldHideAttributesTab(for: way))
	}

	// MARK: resolvedTabBar

	func testResolvedTabBarNilSelection() {
		assertResolvedTabBar(savedIndex: 0, selection: nil, expectedTabCount: 2, expectedSelectedIndex: 0)
		assertResolvedTabBar(savedIndex: 1, selection: nil, expectedTabCount: 2, expectedSelectedIndex: 1)
		assertResolvedTabBar(savedIndex: 2, selection: nil, expectedTabCount: 2, expectedSelectedIndex: 0)
	}

	func testResolvedTabBarPendingNode() {
		let node = OsmNode(asUserCreated: "")
		assertResolvedTabBar(savedIndex: 0, selection: node, expectedTabCount: 2, expectedSelectedIndex: 0)
		assertResolvedTabBar(savedIndex: 1, selection: node, expectedTabCount: 2, expectedSelectedIndex: 1)
		assertResolvedTabBar(savedIndex: 2, selection: node, expectedTabCount: 2, expectedSelectedIndex: 0)
	}

	func testResolvedTabBarUploadedNode() {
		let node = OsmNode(
			withVersion: 1,
			changeset: 0,
			user: "",
			uid: 0,
			ident: 42,
			timestamp: "",
			tags: [:])
		assertResolvedTabBar(savedIndex: 0, selection: node, expectedTabCount: 3, expectedSelectedIndex: 0)
		assertResolvedTabBar(savedIndex: 1, selection: node, expectedTabCount: 3, expectedSelectedIndex: 1)
		assertResolvedTabBar(savedIndex: 2, selection: node, expectedTabCount: 3, expectedSelectedIndex: 2)
	}

	func testResolvedTabBarPendingWay() {
		let way = OsmWay(asUserCreated: "")
		assertResolvedTabBar(savedIndex: 0, selection: way, expectedTabCount: 2, expectedSelectedIndex: 0)
		assertResolvedTabBar(savedIndex: 1, selection: way, expectedTabCount: 2, expectedSelectedIndex: 1)
		assertResolvedTabBar(savedIndex: 2, selection: way, expectedTabCount: 2, expectedSelectedIndex: 0)
	}

	// MARK: Helpers

	private func assertResolvedTabBar(
		savedIndex: Int,
		selection: OsmBaseObject?,
		expectedTabCount: Int,
		expectedSelectedIndex: Int,
		file: StaticString = #file,
		line: UInt = #line
	) {
		let result = POITabBarController.resolvedTabBar(savedIndex: savedIndex, selection: selection)
		XCTAssertEqual(result.tabCount, expectedTabCount, file: file, line: line)
		XCTAssertEqual(result.selectedIndex, expectedSelectedIndex, file: file, line: line)
	}
}
