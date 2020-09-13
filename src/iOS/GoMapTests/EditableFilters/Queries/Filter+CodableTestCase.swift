//
//  Filter+CodableTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 13.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

@testable import Go_Map__
import XCTest

class Filter_CodableTestCase: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: .keyExists

    func testCodable_withKeyExistsFilter() {
        /// Given
        let filter = Filter.keyExists(key: "man_made")

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    func testCodable_withNegatedKeyExistsFilter() {
        /// Given
        let filter = Filter.keyExists(key: "amenity", isNegated: true)

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    // MARK: .keyValue

    func testCodable_withKeyValueFilter() {
        /// Given
        let filter = Filter.keyValue(key: "man_made", value: "surveillance")

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    func testCodable_withNegatedKeyValueFilter() {
        /// Given
        let filter = Filter.keyValue(key: "amenity", value: "bench", isNegated: true)

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    // MARK: .regularExpression

    func testCodable_withRegularExpressionFilter() {
        /// Given
        let filter = Filter.regularExpression(key: "man_made", value: "surveill*")

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    func testCodable_withNegatedRegularExpressionFilter() {
        /// Given
        let filter = Filter.keyValue(key: "amenity", value: "be*", isNegated: true)

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    // MARK: .recursive

    func testCodable_withRecursiveFilterAndLogicalAnd() {
        /// Given
        let filter = Filter.recursive(logical: .and,
                                      filters: [.keyValue(key: "amenity", value: "bench"),
                                                .keyExists(key: "backrest")])

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }

    func testCodable_withRecursiveFilterAndLogicalOr() {
        /// Given
        let filter = Filter.recursive(logical: .or,
                                      filters: [.keyValue(key: "man_made", value: "surveillance"),
                                                .keyExists(key: "camera:mount")])

        do {
            /// When
            let filterAsData = try encoder.encode(filter)
            let decodedFilter = try decoder.decode(Filter.self, from: filterAsData)

            /// Then
            XCTAssertEqual(decodedFilter, filter)
        } catch {
            XCTFail()
        }
    }
}
