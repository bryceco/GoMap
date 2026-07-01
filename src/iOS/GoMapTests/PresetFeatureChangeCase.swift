//
//  PresetFeatureChangeCase.swift
//  GoMapTests
//
//  Tests for PresetFeature.objectTagsUpdatedForFeature(), which updates an
//  object's tags when the user changes its preset.
//

@testable import Go_Map__
import XCTest

class PresetFeatureChangeCase: XCTestCase {
	let db = PresetsDatabase.shared

	// Changing shop/bakery → shop/yes:
	// - "shop" should become "yes" (shop/yes preset explicitly sets shop=yes)
	// - "name" should be preserved
	func testShopBakeryToShopYes() throws {
		let oldTags = ["shop": "bakery", "name": "Acme Bakery"]
		let newFeature = try XCTUnwrap(db.presetFeatureForFeatureID("shop/yes"))
		let newTags = newFeature.objectTagsUpdatedForFeature(oldTags, geometry: .POINT, location: .none)

		XCTAssertEqual(newTags["shop"], "yes",
		               "shop=bakery should be replaced by shop=yes when changing to the shop/yes preset")
		XCTAssertEqual(newTags["name"], "Acme Bakery",
		               "name should be preserved when changing preset")
	}

	// Changing building → amenity/school:
	// School has "building" as a field key, so the building preset is still "compatible"
	// with the school's reduced tags (its matchObjectTagsScore > 0). Therefore the
	// field-key removal pass should be skipped, and building-specific tags like
	// "height" and "roof:shape" should be preserved.
	// https://github.com/openstreetmap/iD/issues/12071
	func testBuildingToSchoolPreservesCompatibleTags() throws {
		let oldTags = ["building": "yes", "height": "10", "roof:shape": "flat", "name": "Riverside School"]
		let newFeature = try XCTUnwrap(db.presetFeatureForFeatureID("amenity/school"))
		let newTags = newFeature.objectTagsUpdatedForFeature(oldTags, geometry: .AREA, location: .none)

		XCTAssertEqual(newTags["amenity"], "school",
		               "amenity=school should be set")
		XCTAssertEqual(newTags["name"], "Riverside School",
		               "name should be preserved")
		XCTAssertEqual(newTags["height"], "10",
		               "height should be preserved: school is still a building, so building-specific tags should remain")
		XCTAssertEqual(newTags["roof:shape"], "flat",
		               "roof:shape should be preserved: school is still a building, so building-specific tags should remain")
	}

	// Changing amenity/restaurant/pizza → amenity/restaurant:
	// The pizza preset's addTags include cuisine=pizza, which is a specialization of
	// the restaurant preset. When converting to the parent, cuisine should be removed
	// because it was part of the sub-preset's defining tags, not a user-added tag.
	func testPizzaRestaurantToRestaurantRemovesCuisine() throws {
		let oldTags = ["amenity": "restaurant", "cuisine": "pizza", "name": "Mario's"]
		let newFeature = try XCTUnwrap(db.presetFeatureForFeatureID("amenity/restaurant"))
		let newTags = newFeature.objectTagsUpdatedForFeature(oldTags, geometry: .POINT, location: .none)

		XCTAssertEqual(newTags["amenity"], "restaurant",
		               "amenity=restaurant should be set")
		XCTAssertEqual(newTags["name"], "Mario's",
		               "name should be preserved")
		XCTAssertNil(newTags["cuisine"],
		             "cuisine should be removed: it was part of the pizza sub-preset's defining tags")
	}

	// Changing highway/path → highway/track:
	// The path-specific tags sac_scale, and trail_visibility are in path's
	// moreFields but not track's. However, since path and track are siblings under the
	// highway hierarchy and share many properties (smoothness, width, surface), these
	// user-entered tags should be preserved rather than silently removed.
	//
	// See https://github.com/openstreetmap/id-tagging-schema/issues/2408
	// Once that issue is resolved we can see how to make this test pass
	func testPathToTrackPreservesPathTags() throws {
		let oldTags = [
			"highway": "path",
			"informal": "yes",
			"obstacle": "vegetation",
			"sac_scale": "mountain_hiking",
			"smoothness": "horrible",
			"surface": "grass",
			"trail_visibility": "bad",
			"width": "2"
		]
		let newFeature = try XCTUnwrap(db.presetFeatureForFeatureID("highway/track"))
		let newTags = newFeature.objectTagsUpdatedForFeature(oldTags, geometry: .LINE, location: .none)

		XCTAssertEqual(newTags["highway"], "track")
		XCTAssertEqual(newTags["smoothness"], "horrible",
		               "smoothness is a field of both path and track, should be preserved")
		XCTAssertEqual(newTags["width"], "2",
		               "width is a field of both path and track, should be preserved")
		XCTAssertEqual(newTags["sac_scale"], "mountain_hiking",
		               "sac_scale should be preserved when changing from path to track")
		XCTAssertEqual(newTags["trail_visibility"], "bad",
		               "trail_visibility should be preserved when changing from path to track")
	}
}
