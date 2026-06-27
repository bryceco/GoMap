//
//  EditorMapLayerSelectionTestCase.swift
//  GoMapTests
//
//  Tests the tap-selection decision logic that determines whether a tapped way is
//  selected directly or promoted to a containing relation.
//  Regression coverage for issue #969 ("Shows parking as managed forest"): a parking
//  area that is also a member of a forest multipolygon should select as the parking
//  on the first tap, not as the forest relation.
//

@testable import Go_Map__
import XCTest

final class EditorMapLayerSelectionTestCase: XCTestCase {
	private func makeWay(tags: [String: String]) -> OsmWay {
		let way = OsmWay(asUserCreated: "test")
		way.setTags(tags, undo: nil)
		return way
	}

	private func makeRelation(tags: [String: String], members: [OsmBaseObject] = []) -> OsmRelation {
		let relation = OsmRelation(asUserCreated: "test")
		relation.setTags(tags, undo: nil)
		for (index, obj) in members.enumerated() {
			relation.addMember(OsmMember(obj: obj, role: "outer"), atIndex: index, undo: nil)
		}
		return relation
	}

	// MARK: relationToPromote

	/// #969: a parking way that is a member of a forest multipolygon must NOT promote to the
	/// forest, so the user selects the parking on the first tap.
	func testTaggedWayInMultipolygonIsNotPromoted() {
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"])
		XCTAssertTrue(forest.isMultipolygon())
		let result = EditorMapLayer.relationToPromote(parentRelations: [forest],
		                                              wayHasInterestingTags: true)
		XCTAssertNil(result, "a way with its own interesting tags should select the way, not the relation")
	}

	/// A tag-less member way (the common multipolygon ring) still promotes to its container.
	func testTaglessWayInMultipolygonStillPromotes() {
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"])
		let result = EditorMapLayer.relationToPromote(parentRelations: [forest],
		                                              wayHasInterestingTags: false)
		XCTAssertEqual(result, forest)
	}

	/// A way with no parent relations is never promoted.
	func testWayWithoutParentsIsNotPromoted() {
		XCTAssertNil(EditorMapLayer.relationToPromote(parentRelations: [],
		                                              wayHasInterestingTags: false))
		XCTAssertNil(EditorMapLayer.relationToPromote(parentRelations: [],
		                                              wayHasInterestingTags: true))
	}

	/// A tag-less way whose only parent is a non-container relation (e.g. a route) still
	/// promotes to that parent, matching the prior behavior.
	func testTaglessWayPromotesToNonContainerParent() {
		let route = makeRelation(tags: ["type": "route", "route": "bicycle"])
		XCTAssertFalse(route.isMultipolygon())
		let result = EditorMapLayer.relationToPromote(parentRelations: [route],
		                                              wayHasInterestingTags: false)
		XCTAssertEqual(result, route)
	}

	// MARK: tapSelectionPick

	/// First tap with nothing selected prefers the tagged way over its containing relation.
	func testTapPrefersTaggedWayOverContainingRelation() {
		let parking = makeWay(tags: ["amenity": "parking"])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"], members: [parking])
		let pick = EditorMapLayer.tapSelectionPick(among: [parking, forest],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: false)
		XCTAssertTrue(pick === parking)
	}

	/// First tap with nothing selected prefers the relation when the candidate way is tag-less.
	func testTapPrefersRelationWhenWayIsTagless() {
		let ring = makeWay(tags: [:])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"], members: [ring])
		let pick = EditorMapLayer.tapSelectionPick(among: [ring, forest],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: false)
		XCTAssertTrue(pick === forest)
	}

	/// Drill-down: with a relation already selected, a re-tap prefers a member way of it.
	func testTapDrillsFromSelectedRelationToMemberWay() {
		let parking = makeWay(tags: ["amenity": "parking"])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"], members: [parking])
		let pick = EditorMapLayer.tapSelectionPick(among: [parking, forest],
		                                           selectedRelation: forest,
		                                           hasExistingSelection: true)
		XCTAssertTrue(pick === parking)
	}

	/// With an existing selection and a single candidate, the deterministic fallback returns
	/// that candidate (rather than deferring to the caller's nondeterministic tiebreak).
	func testTapFallsBackToSoleCandidateWhenSelectionExists() {
		let parking = makeWay(tags: ["amenity": "parking"])
		let pick = EditorMapLayer.tapSelectionPick(among: [parking],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: true)
		XCTAssertTrue(pick === parking)
	}

	/// A tagged way that is NOT a member of the candidate relation must not steal the relation's
	/// first-tap selection (the relation must remain selectable).
	func testTapDoesNotStealRelationForUnrelatedTaggedWay() {
		let footway = makeWay(tags: ["highway": "footway"])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"]) // footway is not a member
		let pick = EditorMapLayer.tapSelectionPick(among: [footway, forest],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: false)
		XCTAssertTrue(pick === forest)
	}

	/// The tagged-member preference applies even when something else is already selected, so
	/// the #969 fix is not limited to a fresh tap.
	func testTapPrefersTaggedMemberEvenWhenSelectionExists() {
		let parking = makeWay(tags: ["amenity": "parking"])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"], members: [parking])
		let pick = EditorMapLayer.tapSelectionPick(among: [parking, forest],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: true)
		XCTAssertTrue(pick === parking)
	}

	/// Equal-distance ties resolve deterministically regardless of candidate input order.
	func testTapSelectionIsOrderIndependent() {
		let wayA = makeWay(tags: ["amenity": "parking"])
		let wayB = makeWay(tags: ["amenity": "parking"])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"], members: [wayA, wayB])
		let pick1 = EditorMapLayer.tapSelectionPick(among: [wayA, wayB, forest],
		                                            selectedRelation: nil,
		                                            hasExistingSelection: false)
		let pick2 = EditorMapLayer.tapSelectionPick(among: [forest, wayB, wayA],
		                                            selectedRelation: nil,
		                                            hasExistingSelection: false)
		XCTAssertTrue(pick1 === pick2)
		XCTAssertTrue(pick1 === wayA || pick1 === wayB)
	}

	/// A tagged member of a NON-container relation (route, turn-restriction) must NOT win over the
	/// relation: such relations have no geometry of their own and are only reachable by tapping a
	/// member, so the relation must be selectable on the first tap.
	func testTapDoesNotPreferTaggedMemberOfNonContainerRelation() {
		let road = makeWay(tags: ["highway": "path"])
		let route = makeRelation(tags: ["type": "route", "route": "hiking"], members: [road])
		let pick = EditorMapLayer.tapSelectionPick(among: [road, route],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: false)
		XCTAssertTrue(pick === route)
	}

	/// When a tag-less way ties with both a non-container relation and a container relation, the
	/// container is preferred (matching relationToPromote), deterministically.
	func testTapPrefersContainerRelationOverNonContainer() {
		let ring = makeWay(tags: [:])
		let route = makeRelation(tags: ["type": "route", "route": "hiking"], members: [ring])
		let forest = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"], members: [ring])
		let pick = EditorMapLayer.tapSelectionPick(among: [ring, route, forest],
		                                           selectedRelation: nil,
		                                           hasExistingSelection: false)
		XCTAssertTrue(pick === forest)
	}

	/// relationToPromote chooses the same container regardless of parentRelations order.
	func testRelationToPromoteIsDeterministicAmongContainers() {
		let mp1 = makeRelation(tags: ["type": "multipolygon", "landuse": "forest"])
		let mp2 = makeRelation(tags: ["type": "multipolygon", "natural": "wood"])
		let pick1 = EditorMapLayer.relationToPromote(parentRelations: [mp1, mp2],
		                                             wayHasInterestingTags: false)
		let pick2 = EditorMapLayer.relationToPromote(parentRelations: [mp2, mp1],
		                                             wayHasInterestingTags: false)
		XCTAssertNotNil(pick1)
		XCTAssertTrue(pick1 === pick2)
	}
}
