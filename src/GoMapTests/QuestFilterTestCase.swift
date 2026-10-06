//
//  QuestFilterTestCase.swift
//  GoMapTests
//
//  Created by Bryce Cogswell on 10/8/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

@testable import Go_Map__
import XCTest

class QuestFilterTestCase: XCTestCase {

	// MARK: - Helpers

	private func makeNode(tags: [String: String] = [:]) -> OsmNode {
		return OsmNode(withVersion: 1, changeset: 0, user: "", uid: 0,
		               ident: OsmBaseObject.nextUnusedIdentifier(),
		               timestamp: "", tags: tags, latLon: .zero)
	}

	private func makeWay(tags: [String: String] = [:]) -> OsmWay {
		return OsmWay(withVersion: 1, changeset: 0, user: "", uid: 0,
		              ident: OsmBaseObject.nextUnusedIdentifier(),
		              timestamp: "", tags: tags)
	}

	private func makeQuest(
		tree: QuestFilterGroup,
		editKeys: [String] = ["name"],
		geometry: QuestDefinitionWithFilters.Geometries = .init()
	) throws -> QuestProtocol {
		let def = QuestDefinitionWithFilters(
			title: "Test Quest",
			label: "Q",
			editKeys: editKeys,
			filterTree: tree,
			geometry: geometry)
		return try def.makeQuestInstance()
	}

	private func questFromJSON(_ json: String) throws -> QuestProtocol {
		let data = Data(json.utf8)
		let def = try JSONDecoder().decode(QuestDefinitionWithFilters.self, from: data)
		return try def.makeQuestInstance()
	}

	// MARK: - Condition Predicate Tests

	func testEquals() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .equals, value: "residential")),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testNotEquals() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
			.condition(QuestFilterCondition(key: "highway", op: .notEquals, value: "motorway")),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "motorway"])))
	}

	func testExists() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "motorway"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["amenity": "cafe"])))
	}

	func testMissing() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "surface", op: .missing)),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertTrue(quest.appliesTo(makeNode()))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["surface": "asphalt"])))
	}

	// MARK: - AND / OR Grouping

	func testAndGroup() throws {
		// highway exists AND surface missing
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
			.condition(QuestFilterCondition(key: "surface", op: .missing)),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "residential", "surface": "asphalt"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testOrGroup() throws {
		// highway=primary OR highway=secondary
		let tree = QuestFilterGroup(op: .or, children: [
			.condition(QuestFilterCondition(key: "highway", op: .equals, value: "primary")),
			.condition(QuestFilterCondition(key: "highway", op: .equals, value: "secondary")),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "secondary"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "tertiary"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testNestedGroups() throws {
		// highway exists AND (surface missing OR lanes missing)
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
			.group(QuestFilterGroup(op: .or, children: [
				.condition(QuestFilterCondition(key: "surface", op: .missing)),
				.condition(QuestFilterCondition(key: "lanes", op: .missing)),
			])),
		])
		let quest = try makeQuest(tree: tree)
		// missing both => match
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
		// missing just surface => match
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary", "lanes": "2"])))
		// missing just lanes => match
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary", "surface": "asphalt"])))
		// has both => no match
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "primary", "surface": "asphalt", "lanes": "2"])))
		// no highway => no match
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testEmptyAndMatchesAll() throws {
		// An empty AND group matches everything
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
			.group(QuestFilterGroup(op: .and, children: [])),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
	}

	func testEmptyOrMatchesNothing() throws {
		// An empty OR group matches nothing
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
			.group(QuestFilterGroup(op: .or, children: [])),
		])
		let quest = try makeQuest(tree: tree)
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
	}

	// MARK: - Error Cases

	func testEmptyKeyThrows() {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "", op: .exists)),
		])
		XCTAssertThrowsError(try makeQuest(tree: tree))
	}

	func testEmptyValueThrows() {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .equals, value: "")),
		])
		XCTAssertThrowsError(try makeQuest(tree: tree))
	}

	func testEmptyTreeThrows() {
		let tree = QuestFilterGroup(op: .and, children: [])
		XCTAssertThrowsError(try makeQuest(tree: tree))
	}

	func testInvalidLabelThrows() {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .exists)),
		])
		let def = QuestDefinitionWithFilters(
			title: "Bad Label",
			label: "too long",
			editKeys: ["name"],
			filterTree: tree,
			geometry: .init())
		XCTAssertThrowsError(try def.makeQuestInstance())
	}

	// MARK: - Geometry Filter Tests

	func testPointOnlyGeometry() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "amenity", op: .equals, value: "restaurant")),
		])
		let quest = try makeQuest(tree: tree, geometry: .init(point: true))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["amenity": "restaurant"])))
		XCTAssertFalse(quest.appliesTo(makeWay(tags: ["amenity": "restaurant"])))
	}

	func testEmptyGeometryMatchesAll() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "amenity", op: .equals, value: "restaurant")),
		])
		let quest = try makeQuest(tree: tree, geometry: .init())
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["amenity": "restaurant"])))
		XCTAssertTrue(quest.appliesTo(makeWay(tags: ["amenity": "restaurant"])))
	}

	func testAllTrueGeometryMatchesAll() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "amenity", op: .equals, value: "restaurant")),
		])
		let quest = try makeQuest(tree: tree,
		                          geometry: .init(point: true, line: true, area: true, vertex: true))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["amenity": "restaurant"])))
		XCTAssertTrue(quest.appliesTo(makeWay(tags: ["amenity": "restaurant"])))
	}

	// MARK: - JSON Decoding Tests

	func testJSONSimpleAndTree() throws {
		let json = """
		{
			"title": "Add Surface",
			"label": "Q",
			"editKeys": ["surface"],
			"filterTree": {
				"and": [
					{ "exists": "highway" },
					{ "missing": "surface" }
				]
			}
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "residential", "surface": "asphalt"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testJSONNestedOrTree() throws {
		let json = """
		{
			"title": "Add Details",
			"label": "Q",
			"editKeys": ["surface", "lanes"],
			"filterTree": {
				"and": [
					{ "exists": "highway" },
					{ "or": [
						{ "missing": "surface" },
						{ "missing": "lanes" }
					]}
				]
			}
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary", "lanes": "2"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "primary", "surface": "asphalt", "lanes": "2"])))
	}

	func testJSONEqualsAndNotEquals() throws {
		let json = """
		{
			"title": "Fix Road",
			"label": "Q",
			"editKeys": ["surface"],
			"filterTree": {
				"and": [
					{ "=": ["highway", "residential"] },
					{ "≠": ["surface", "asphalt"] }
				]
			}
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential", "surface": "gravel"])))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "residential", "surface": "asphalt"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
	}

	func testJSONLegacyFlatFilters() throws {
		// Old format with flat filter list, no filterTree
		let json = """
		{
			"title": "Add Surface",
			"label": "Q",
			"editKeys": ["surface"],
			"filters": [
				{ "tagKey": "highway", "tagValue": "*", "relation": "=", "included": "include" },
				{ "tagKey": "surface", "tagValue": "", "relation": "=", "included": "include" }
			]
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "residential", "surface": "asphalt"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testJSONLegacyOrGrouping() throws {
		// Old format: same key with = should be ORed
		let json = """
		{
			"title": "Fix Highway",
			"label": "Q",
			"editKeys": ["surface"],
			"filters": [
				{ "tagKey": "highway", "tagValue": "primary", "relation": "=", "included": "include" },
				{ "tagKey": "highway", "tagValue": "secondary", "relation": "=", "included": "include" }
			]
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "secondary"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "tertiary"])))
	}

	func testJSONLegacyExclude() throws {
		// Old format: exclude with = is equivalent to !=
		let json = """
		{
			"title": "Non-motorway Highway",
			"label": "Q",
			"editKeys": ["surface"],
			"filters": [
				{ "tagKey": "highway", "tagValue": "*", "relation": "=", "included": "include" },
				{ "tagKey": "highway", "tagValue": "motorway", "relation": "=", "included": "exclude" }
			]
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "motorway"])))
		XCTAssertFalse(quest.appliesTo(makeNode()))
	}

	func testJSONWithGeometry() throws {
		let json = """
		{
			"title": "Add Cuisine",
			"label": "Q",
			"editKeys": ["cuisine"],
			"filterTree": {
				"and": [
					{ "=": ["amenity", "restaurant"] }
				]
			},
			"geometry": { "point": true, "line": false, "area": false, "vertex": false }
		}
		"""
		let quest = try questFromJSON(json)
		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["amenity": "restaurant"])))
		XCTAssertFalse(quest.appliesTo(makeWay(tags: ["amenity": "restaurant"])))
	}

	func testJSONRoundTrip() throws {
		let tree = QuestFilterGroup(op: .and, children: [
			.condition(QuestFilterCondition(key: "highway", op: .equals, value: "residential")),
			.group(QuestFilterGroup(op: .or, children: [
				.condition(QuestFilterCondition(key: "surface", op: .missing)),
				.condition(QuestFilterCondition(key: "lanes", op: .missing)),
			])),
		])
		let original = QuestDefinitionWithFilters(
			title: "Test", label: "Q", editKeys: ["surface"],
			filterTree: tree, geometry: .init(point: true))

		let data = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(QuestDefinitionWithFilters.self, from: data)
		let quest = try decoded.makeQuestInstance()

		XCTAssertTrue(quest.appliesTo(makeNode(tags: ["highway": "residential"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "residential", "surface": "asphalt", "lanes": "2"])))
		XCTAssertFalse(quest.appliesTo(makeNode(tags: ["highway": "primary"])))
	}
}
