@testable import Go_Map__
import XCTest

/// Tests for way reversal logic, corresponding to iD editor's test/spec/actions/reverse.js
class ReverseWayTestCase: XCTestCase {
	var mapData: OsmMapData!

	override func setUp() {
		_ = createDedicatedUserDefaults()
		mapData = OsmMapData()
	}

	override func tearDown() {
		mapData = nil
	}

	// MARK: - Helpers

	/// Run canReverse on a way with the given tags and return the resulting tags
	private func reversedWayTags(_ tags: [String: String]) -> [String: String] {
		try! mapData.initWith(dict: [
			"nodes": [
				["id": 1, "lat": 0, "lon": 0],
				["id": 2, "lat": 0, "lon": 1]
			],
			"ways": [["id": 10, "nodes": [1, 2], "tags": tags]]
		])
		let way = mapData.ways[10]!
		let action = try! mapData.canReverse(way)
		action()
		return way.tags
	}

	/// Create a way with child nodes, reverse it, and return the specified node's tags
	private func reversedNodeTags(wayTags: [String: String] = [:],
	                              nodeTags: [String: String],
	                              nodeIndex: Int = 1) -> [String: String]
	{
		var wayDict: [String: Any] = ["id": 10, "nodes": [1, 2, 3]]
		if !wayTags.isEmpty {
			wayDict["tags"] = wayTags
		}
		try! mapData.initWith(dict: [
			"nodes": [
				["id": 1, "lat": 0, "lon": 0],
				["id": 2, "lat": 0, "lon": 1, "tags": nodeTags],
				["id": 3, "lat": 0, "lon": 2]
			],
			"ways": [wayDict]
		])
		let way = mapData.ways[10]!
		let action = try! mapData.canReverse(way)
		action()
		return mapData.nodes[Int64(nodeIndex + 1)]!.tags
	}

	// MARK: - reverseKey: suffix replacements

	func testReverseKeySuffixRightToLeft() {
		XCTAssertEqual(OsmMapData.reverseKey("cycleway:right"), "cycleway:left")
	}

	func testReverseKeySuffixLeftToRight() {
		XCTAssertEqual(OsmMapData.reverseKey("cycleway:left"), "cycleway:right")
	}

	func testReverseKeySuffixForwardToBackward() {
		XCTAssertEqual(OsmMapData.reverseKey("maxspeed:forward"), "maxspeed:backward")
	}

	func testReverseKeySuffixBackwardToForward() {
		XCTAssertEqual(OsmMapData.reverseKey("maxspeed:backward"), "maxspeed:forward")
	}

	// MARK: - reverseKey: infix replacements

	func testReverseKeyInfixRightToLeft() {
		XCTAssertEqual(OsmMapData.reverseKey("cycleway:right:surface"), "cycleway:left:surface")
	}

	func testReverseKeyInfixLeftToRight() {
		XCTAssertEqual(OsmMapData.reverseKey("cycleway:left:surface"), "cycleway:right:surface")
	}

	func testReverseKeyInfixForwardToBackward() {
		XCTAssertEqual(OsmMapData.reverseKey("maxspeed:forward:conditional"), "maxspeed:backward:conditional")
	}

	func testReverseKeyInfixBackwardToForward() {
		XCTAssertEqual(OsmMapData.reverseKey("maxspeed:backward:conditional"), "maxspeed:forward:conditional")
	}

	// MARK: - reverseKey: preserved keys

	func testReverseKeyPreservesNonDirectionalKeys() {
		XCTAssertEqual(OsmMapData.reverseKey("highway"), "highway")
		XCTAssertEqual(OsmMapData.reverseKey("name"), "name")
	}

	func testReverseKeyPreservesRedTurnRight() {
		XCTAssertEqual(OsmMapData.reverseKey("red_turn:right"), "red_turn:right")
	}

	func testReverseKeyPreservesRedTurnRightBicycle() {
		XCTAssertEqual(OsmMapData.reverseKey("red_turn:right:bicycle"), "red_turn:right:bicycle")
	}

	func testReverseKeyPreservesRedTurnLeft() {
		XCTAssertEqual(OsmMapData.reverseKey("red_turn:left"), "red_turn:left")
	}

	// MARK: - reverseKey: roundtrip

	func testReverseKeyRoundtripRightLeft() {
		let key = "cycleway:right"
		XCTAssertEqual(OsmMapData.reverseKey(OsmMapData.reverseKey(key)), key)
	}

	func testReverseKeyRoundtripForwardBackward() {
		let key = "maxspeed:forward"
		XCTAssertEqual(OsmMapData.reverseKey(OsmMapData.reverseKey(key)), key)
	}

	func testReverseKeyRoundtripInfixRightLeft() {
		let key = "cycleway:right:surface"
		XCTAssertEqual(OsmMapData.reverseKey(OsmMapData.reverseKey(key)), key)
	}

	// MARK: - reverseValue: incline

	func testReverseValueInclineUpToDown() {
		XCTAssertEqual(OsmMapData.reverseValue("incline", "up", allTags: [:]), "down")
	}

	func testReverseValueInclineDownToUp() {
		XCTAssertEqual(OsmMapData.reverseValue("incline", "down", allTags: [:]), "up")
	}

	func testReverseValueInclineUpDownRoundtrip() {
		let v1 = OsmMapData.reverseValue("incline", "up", allTags: [:])
		let v2 = OsmMapData.reverseValue("incline", v1, allTags: [:])
		XCTAssertEqual(v2, "up")
	}

	func testReverseValueNegatesNumericIncline() {
		XCTAssertEqual(OsmMapData.reverseValue("incline", "5", allTags: [:]), "-5")
	}

	func testReverseValueNegatesNumericInclineRoundtrip() {
		let v1 = OsmMapData.reverseValue("incline", "5", allTags: [:])
		let v2 = OsmMapData.reverseValue("incline", v1, allTags: [:])
		XCTAssertEqual(v2, "5")
	}

	func testReverseValueNegatesPositiveSignIncline() {
		XCTAssertEqual(OsmMapData.reverseValue("incline", "+5", allTags: [:]), "-5")
	}

	func testReverseValueNegatesNegativeIncline() {
		XCTAssertEqual(OsmMapData.reverseValue("incline", "-5", allTags: [:]), "5")
	}

	// MARK: - reverseValue: forward/backward

	func testReverseValueForwardToBackward() {
		XCTAssertEqual(OsmMapData.reverseValue("conveying", "forward", allTags: [:]), "backward")
		XCTAssertEqual(OsmMapData.reverseValue("direction", "forward", allTags: [:]), "backward")
		XCTAssertEqual(OsmMapData.reverseValue("priority", "forward", allTags: [:]), "backward")
		XCTAssertEqual(OsmMapData.reverseValue("trolley_wire", "forward", allTags: [:]), "backward")
		XCTAssertEqual(OsmMapData.reverseValue("railway:preferred_direction", "forward", allTags: [:]), "backward")
	}

	func testReverseValueBackwardToForward() {
		XCTAssertEqual(OsmMapData.reverseValue("conveying", "backward", allTags: [:]), "forward")
		XCTAssertEqual(OsmMapData.reverseValue("direction", "backward", allTags: [:]), "forward")
		XCTAssertEqual(OsmMapData.reverseValue("priority", "backward", allTags: [:]), "forward")
		XCTAssertEqual(OsmMapData.reverseValue("trolley_wire", "backward", allTags: [:]), "forward")
		XCTAssertEqual(OsmMapData.reverseValue("railway:preferred_direction", "backward", allTags: [:]), "forward")
	}

	func testReverseValueForwardsDropsS() {
		XCTAssertEqual(OsmMapData.reverseValue("conveying", "forwards", allTags: [:]), "backward")
	}

	func testReverseValueBackwardsDropsS() {
		XCTAssertEqual(OsmMapData.reverseValue("conveying", "backwards", allTags: [:]), "forward")
	}

	// MARK: - reverseValue: left/right

	func testReverseValueRightToLeft() {
		XCTAssertEqual(OsmMapData.reverseValue("sidewalk", "right", allTags: [:]), "left")
	}

	func testReverseValueLeftToRight() {
		XCTAssertEqual(OsmMapData.reverseValue("sidewalk", "left", allTags: [:]), "right")
	}

	// MARK: - reverseValue: up/down

	func testReverseValueUpToDown() {
		XCTAssertEqual(OsmMapData.reverseValue("direction", "up", allTags: [:]), "down")
	}

	func testReverseValueDownToUp() {
		XCTAssertEqual(OsmMapData.reverseValue("direction", "down", allTags: [:]), "up")
	}

	// MARK: - reverseValue: preserves non-directional values

	func testReverseValuePreservesNonDirectionalValue() {
		XCTAssertEqual(OsmMapData.reverseValue("highway", "residential", allTags: [:]), "residential")
	}

	func testReverseValuePreservesOneway() {
		// By default (without reverseOneway option), oneway is preserved
		XCTAssertEqual(OsmMapData.reverseValue("oneway", "yes", allTags: [:]), "yes")
	}

	// MARK: - reverseValue: skips descriptive keys

	func testReverseValueSkipsNameUp() {
		XCTAssertEqual(OsmMapData.reverseValue("name", "up", allTags: [:]), "up")
	}

	func testReverseValueSkipsNoteUp() {
		XCTAssertEqual(OsmMapData.reverseValue("note", "up", allTags: [:]), "up")
	}

	func testReverseValueSkipsRefDown() {
		XCTAssertEqual(OsmMapData.reverseValue("ref", "down", allTags: [:]), "down")
	}

	func testReverseValueSkipsDescriptionDown() {
		XCTAssertEqual(OsmMapData.reverseValue("description", "down", allTags: [:]), "down")
	}

	func testReverseValueSkipsNameForward() {
		XCTAssertEqual(OsmMapData.reverseValue("name", "forward", allTags: [:]), "forward")
	}

	func testReverseValueSkipsNoteForwards() {
		XCTAssertEqual(OsmMapData.reverseValue("note", "forwards", allTags: [:]), "forwards")
	}

	func testReverseValueSkipsRefBackward() {
		XCTAssertEqual(OsmMapData.reverseValue("ref", "backward", allTags: [:]), "backward")
	}

	func testReverseValueSkipsDescriptionBackwards() {
		XCTAssertEqual(OsmMapData.reverseValue("description", "backwards", allTags: [:]), "backwards")
	}

	func testReverseValueSkipsNameRight() {
		XCTAssertEqual(OsmMapData.reverseValue("name", "right", allTags: [:]), "right")
	}

	func testReverseValueSkipsNoteRight() {
		XCTAssertEqual(OsmMapData.reverseValue("note", "right", allTags: [:]), "right")
	}

	func testReverseValueSkipsRefLeft() {
		XCTAssertEqual(OsmMapData.reverseValue("ref", "left", allTags: [:]), "left")
	}

	func testReverseValueSkipsDescriptionLeft() {
		XCTAssertEqual(OsmMapData.reverseValue("description", "left", allTags: [:]), "left")
	}

	func testReverseValueSkipsSourceRight() {
		XCTAssertEqual(OsmMapData.reverseValue("source", "right", allTags: [:]), "right")
	}

	func testReverseValueSkipsWebsiteForward() {
		XCTAssertEqual(OsmMapData.reverseValue("website", "forward", allTags: [:]), "forward")
	}

	func testReverseValueSkipsCommentLeft() {
		XCTAssertEqual(OsmMapData.reverseValue("comment", "left", allTags: [:]), "left")
	}

	func testReverseValueSkipsWatchUp() {
		XCTAssertEqual(OsmMapData.reverseValue("watch", "up", allTags: [:]), "up")
	}

	func testReverseValueSkipsAttributionForward() {
		XCTAssertEqual(OsmMapData.reverseValue("attribution", "forward", allTags: [:]), "forward")
	}

	// MARK: - reverseValue: skips descriptive key components

	func testReverseValueSkipsNameColon() {
		// name:en should also be excluded
		XCTAssertEqual(OsmMapData.reverseValue("name:en", "left", allTags: [:]), "left")
	}

	func testReverseValueSkipsSourceColon() {
		XCTAssertEqual(OsmMapData.reverseValue("source:name", "forward", allTags: [:]), "forward")
	}

	// MARK: - reverseValue: turn:lanes preserved

	func testReverseValuePreservesTurnLanesRight() {
		XCTAssertEqual(OsmMapData.reverseValue("turn:lanes", "right", allTags: [:]), "right")
	}

	func testReverseValuePreservesTurnLanesMultiple() {
		XCTAssertEqual(OsmMapData.reverseValue("turn:lanes", "through|through|right", allTags: [:]),
		               "through|through|right")
	}

	func testReverseValuePreservesTurnLanesForward() {
		XCTAssertEqual(OsmMapData.reverseValue("turn:lanes:forward", "right", allTags: [:]), "right")
	}

	func testReverseValuePreservesTurnLanesBackward() {
		XCTAssertEqual(OsmMapData.reverseValue("turn:lanes:backward", "left", allTags: [:]), "left")
	}

	func testReverseValuePreservesTurnLanesBothWays() {
		XCTAssertEqual(OsmMapData.reverseValue("turn:lanes:both_ways", "left", allTags: [:]), "left")
	}

	// MARK: - reverseValue: conditional exclusions

	func testReverseValuePreservesSideOnCyclistWaitingAid() {
		let tags = ["highway": "cyclist_waiting_aid", "direction": "forward", "side": "right"]
		XCTAssertEqual(OsmMapData.reverseValue("side", "right", allTags: tags), "right")
	}

	func testReverseValueReversesSideWithoutCyclistWaitingAid() {
		// Without the cyclist_waiting_aid context, side=right should be reversed
		XCTAssertEqual(OsmMapData.reverseValue("side", "right", allTags: [:]), "left")
	}

	func testReverseValuePreservesRailwayTurnoutSide() {
		XCTAssertEqual(OsmMapData.reverseValue("railway:turnout_side", "right", allTags: [:]), "right")
	}

	// MARK: - Integration: reverses node order

	func testReversesNodeOrder() throws {
		try mapData.initWith(dict: [
			"nodes": [
				["id": 1, "lat": 0, "lon": 0],
				["id": 2, "lat": 0, "lon": 1]
			],
			"ways": [["id": 10, "nodes": [1, 2]]]
		])
		let node1 = mapData.nodes[1]!
		let node2 = mapData.nodes[2]!
		let way = mapData.ways[10]!

		let action = try mapData.canReverse(way)
		action()

		XCTAssertEqual(way.nodes[0], node2)
		XCTAssertEqual(way.nodes[1], node1)
	}

	// MARK: - Integration: preserves non-directional way tags

	func testPreservesNonDirectionalWayTags() {
		let tags = reversedWayTags(["highway": "residential"])
		XCTAssertEqual(tags, ["highway": "residential"])
	}

	func testPreservesOnewayTag() {
		let tags = reversedWayTags(["oneway": "yes"])
		XCTAssertEqual(tags["oneway"], "yes")
	}

	// MARK: - Integration: reverses directional keys on ways

	func testReversesRightLeftKeysOnWay() {
		let tags = reversedWayTags(["cycleway:right": "lane"])
		XCTAssertEqual(tags, ["cycleway:left": "lane"])
	}

	func testReversesRightLeftKeysOnWayRoundtrip() {
		var tags: [String: String] = ["cycleway:right": "lane"]
		tags = reversedWayTags(tags)
		XCTAssertEqual(tags, ["cycleway:left": "lane"])
		tags = reversedWayTags(tags)
		XCTAssertEqual(tags, ["cycleway:right": "lane"])
	}

	func testReversesInfixRightLeftKeysOnWay() {
		let tags = reversedWayTags(["cycleway:right:surface": "paved"])
		XCTAssertEqual(tags, ["cycleway:left:surface": "paved"])
	}

	func testReversesInfixRightLeftKeysOnWayRoundtrip() {
		var tags: [String: String] = ["cycleway:right:surface": "paved"]
		tags = reversedWayTags(tags)
		XCTAssertEqual(tags, ["cycleway:left:surface": "paved"])
		tags = reversedWayTags(tags)
		XCTAssertEqual(tags, ["cycleway:right:surface": "paved"])
	}

	func testReversesForwardBackwardKeysOnWay() {
		let tags = reversedWayTags(["maxspeed:forward": "25"])
		XCTAssertEqual(tags, ["maxspeed:backward": "25"])
	}

	func testReversesForwardBackwardKeysOnWayRoundtrip() {
		var tags: [String: String] = ["maxspeed:forward": "25"]
		tags = reversedWayTags(tags)
		XCTAssertEqual(tags, ["maxspeed:backward": "25"])
		tags = reversedWayTags(tags)
		XCTAssertEqual(tags, ["maxspeed:forward": "25"])
	}

	func testReversesMultipleDirectionalKeysOnWay() {
		let tags = reversedWayTags(["maxspeed:forward": "25", "maxspeed:backward": "30"])
		XCTAssertEqual(tags, ["maxspeed:backward": "25", "maxspeed:forward": "30"])
	}

	// MARK: - Integration: reverses directional values on ways

	func testReversesUpDownValuesOnWay() {
		XCTAssertEqual(reversedWayTags(["incline": "up"]), ["incline": "down"])
		XCTAssertEqual(reversedWayTags(["direction": "up"]), ["direction": "down"])
		XCTAssertEqual(reversedWayTags(["incline": "down"]), ["incline": "up"])
		XCTAssertEqual(reversedWayTags(["direction": "down"]), ["direction": "up"])
	}

	func testReversesForwardBackwardValuesOnWay() {
		XCTAssertEqual(reversedWayTags(["conveying": "forward"]), ["conveying": "backward"])
		XCTAssertEqual(reversedWayTags(["direction": "forward"]), ["direction": "backward"])
		XCTAssertEqual(reversedWayTags(["conveying": "backward"]), ["conveying": "forward"])
		XCTAssertEqual(reversedWayTags(["direction": "backward"]), ["direction": "forward"])
	}

	func testReversesForwardsBackwardsDropsS() {
		XCTAssertEqual(reversedWayTags(["conveying": "forwards"]), ["conveying": "backward"])
		XCTAssertEqual(reversedWayTags(["conveying": "backwards"]), ["conveying": "forward"])
	}

	func testReversesLeftRightValuesOnWay() {
		XCTAssertEqual(reversedWayTags(["sidewalk": "right"]), ["sidewalk": "left"])
		XCTAssertEqual(reversedWayTags(["sidewalk": "left"]), ["sidewalk": "right"])
	}

	func testSkipsUpDownOnDescriptiveKeysOnWay() {
		XCTAssertEqual(reversedWayTags(["name": "up"]), ["name": "up"])
		XCTAssertEqual(reversedWayTags(["note": "up"]), ["note": "up"])
		XCTAssertEqual(reversedWayTags(["ref": "down"]), ["ref": "down"])
		XCTAssertEqual(reversedWayTags(["description": "down"]), ["description": "down"])
	}

	func testSkipsForwardBackwardOnDescriptiveKeysOnWay() {
		XCTAssertEqual(reversedWayTags(["name": "forward"]), ["name": "forward"])
		XCTAssertEqual(reversedWayTags(["note": "forwards"]), ["note": "forwards"])
		XCTAssertEqual(reversedWayTags(["ref": "backward"]), ["ref": "backward"])
		XCTAssertEqual(reversedWayTags(["description": "backwards"]), ["description": "backwards"])
	}

	func testSkipsLeftRightOnDescriptiveKeysOnWay() {
		XCTAssertEqual(reversedWayTags(["name": "right"]), ["name": "right"])
		XCTAssertEqual(reversedWayTags(["note": "right"]), ["note": "right"])
		XCTAssertEqual(reversedWayTags(["ref": "left"]), ["ref": "left"])
		XCTAssertEqual(reversedWayTags(["description": "left"]), ["description": "left"])
	}

	// MARK: - Integration: reverses incline on ways

	func testReversesInclineUpDownOnWay() {
		var tags = reversedWayTags(["incline": "up"])
		XCTAssertEqual(tags, ["incline": "down"])
		tags = reversedWayTags(["incline": "down"])
		XCTAssertEqual(tags, ["incline": "up"])
	}

	func testNegatesNumericInclineOnWay() {
		var tags = reversedWayTags(["incline": "5"])
		XCTAssertEqual(tags, ["incline": "-5"])
		tags = reversedWayTags(["incline": "-5"])
		XCTAssertEqual(tags, ["incline": "5"])
	}

	// MARK: - Integration: turn:lanes key swap with preserved values

	func testTurnLanesForwardBackwardKeySwap() {
		let tags = reversedWayTags(["turn:lanes:forward": "right", "turn:lanes:backward": "left"])
		// Keys should swap (forward ↔ backward), but values should be preserved
		XCTAssertEqual(tags["turn:lanes:backward"], "right")
		XCTAssertEqual(tags["turn:lanes:forward"], "left")
	}

	func testTurnLanesForwardBackwardKeySwapMultiple() {
		let tags = reversedWayTags(["turn:lanes:forward": "through|right",
		                            "turn:lanes:backward": "through|through|left"])
		XCTAssertEqual(tags["turn:lanes:backward"], "through|right")
		XCTAssertEqual(tags["turn:lanes:forward"], "through|through|left")
	}

	func testTurnLanesBothWaysPreserved() {
		let tags = reversedWayTags(["turn:lanes:both_ways": "left"])
		XCTAssertEqual(tags["turn:lanes:both_ways"], "left")
	}

	// MARK: - Integration: reverses directional values on child nodes

	func testReversesForwardDirectionOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["direction": "forward", "highway": "stop"])
		XCTAssertEqual(tags["direction"], "backward")
	}

	func testReversesBackwardDirectionOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["direction": "backward", "highway": "stop"])
		XCTAssertEqual(tags["direction"], "forward")
	}

	func testReversesLeftDirectionOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["direction": "left", "highway": "stop"])
		XCTAssertEqual(tags["direction"], "right")
	}

	func testReversesRightDirectionOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["direction": "right", "highway": "stop"])
		XCTAssertEqual(tags["direction"], "left")
	}

	func testDoesNotAssignDirectionToDirectionlessChildNode() {
		let tags = reversedNodeTags(nodeTags: ["highway": "stop"])
		XCTAssertNil(tags["direction"])
	}

	func testPreservesNonDirectionalDirectionOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["direction": "empty", "highway": "stop"])
		XCTAssertEqual(tags["direction"], "empty")
	}

	func testPreservesNonDirectionalTagsOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_sign": "maxspeed"])
		XCTAssertEqual(tags["traffic_sign"], "maxspeed")
	}

	// MARK: - Integration: reverses directional keys on child nodes

	func testReversesTrafficSignForwardKeyOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_sign:forward": "stop"])
		XCTAssertEqual(tags["traffic_sign:backward"], "stop")
		XCTAssertNil(tags["traffic_sign:forward"])
	}

	func testReversesTrafficSignBackwardKeyOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_sign:backward": "stop"])
		XCTAssertEqual(tags["traffic_sign:forward"], "stop")
		XCTAssertNil(tags["traffic_sign:backward"])
	}

	func testReversesTrafficSignLeftKeyOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_sign:left": "stop"])
		XCTAssertEqual(tags["traffic_sign:right"], "stop")
		XCTAssertNil(tags["traffic_sign:left"])
	}

	func testReversesTrafficSignRightKeyOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_sign:right": "stop"])
		XCTAssertEqual(tags["traffic_sign:left"], "stop")
		XCTAssertNil(tags["traffic_sign:right"])
	}

	func testReversesTrafficSignalsDirectionForwardOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_signals:direction": "forward",
		                                       "highway": "traffic_signals"])
		XCTAssertEqual(tags["traffic_signals:direction"], "backward")
	}

	func testReversesTrafficSignalsDirectionBackwardOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_signals:direction": "backward",
		                                       "highway": "traffic_signals"])
		XCTAssertEqual(tags["traffic_signals:direction"], "forward")
	}

	func testReversesTrafficSignalsDirectionLeftOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_signals:direction": "left",
		                                       "highway": "traffic_signals"])
		XCTAssertEqual(tags["traffic_signals:direction"], "right")
	}

	func testReversesTrafficSignalsDirectionRightOnChildNode() {
		let tags = reversedNodeTags(nodeTags: ["traffic_signals:direction": "right",
		                                       "highway": "traffic_signals"])
		XCTAssertEqual(tags["traffic_signals:direction"], "left")
	}

	func testDoesNotAssignDirectionToDirectionlessTrafficSignals() {
		let tags = reversedNodeTags(nodeTags: ["highway": "traffic_signals"])
		XCTAssertNil(tags["traffic_signals:direction"])
	}

	func testPreservesNonDirectionalTrafficSignalsDirection() {
		let tags = reversedNodeTags(nodeTags: ["traffic_signals:direction": "empty",
		                                       "highway": "traffic_signals"])
		XCTAssertEqual(tags["traffic_signals:direction"], "empty")
	}

	// MARK: - Integration: does not reverse values relative to another reversed tag

	func testPreservesRedTurnRightOnChildNode() {
		let tags = reversedNodeTags(nodeTags: [
			"highway": "traffic_signals",
			"traffic_signals:direction": "forward",
			"red_turn:right": "no",
			"red_turn:right:bicycle": "yes"
		])
		XCTAssertEqual(tags["traffic_signals:direction"], "backward")
		XCTAssertEqual(tags["red_turn:right"], "no")
		XCTAssertEqual(tags["red_turn:right:bicycle"], "yes")
	}

	func testPreservesSideOnCyclistWaitingAidChildNode() {
		let tags = reversedNodeTags(nodeTags: [
			"highway": "cyclist_waiting_aid",
			"direction": "forward",
			"side": "right"
		])
		XCTAssertEqual(tags["direction"], "backward")
		XCTAssertEqual(tags["side"], "right")
	}

	func testPreservesRailwayTurnoutSideOnChildNode() {
		let tags = reversedNodeTags(nodeTags: [
			"direction": "forward",
			"railway:turnout_side": "right"
		])
		XCTAssertEqual(tags["direction"], "backward")
		XCTAssertEqual(tags["railway:turnout_side"], "right")
	}

	func testPreservesDrivingSideOnWay() {
		let tags = reversedWayTags(["highway": "primary", "driving_side": "left"])
		XCTAssertEqual(tags["driving_side"], "left")
	}

	func testPreservesTurnForwardBackwardKeySwap() {
		let tags = reversedWayTags(["highway": "primary", "turn:forward": "left", "turn:backward": "right"])
		// Keys swap (forward ↔ backward), but turn values are preserved
		XCTAssertEqual(tags["turn:backward"], "left")
		XCTAssertEqual(tags["turn:forward"], "right")
	}
}
