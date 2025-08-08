//
//  AnyJSON.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/29/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import Foundation

enum AnyJSON: Hashable, Codable {
	case null
	case string(String)
	case double(Double)
	case bool(Bool)
	case array([AnyJSON])
	case dictionary([String: AnyJSON])

	public var value: Any {
		switch self {
		case .null: return NSNull()
		case let .string(value): return value
		case let .double(value): return value
		case let .bool(value): return value
		case let .array(value): return value.map { $0.value }
		case let .dictionary(value): return value.mapValues { $0.value }
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .null: try container.encodeNil()
		case let .string(value): try container.encode(value)
		case let .double(value): try container.encode(value)
		case let .bool(value): try container.encode(value)
		case let .array(value): try container.encode(value)
		case let .dictionary(value): try container.encode(value)
		}
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else if let value = try? container.decode(Double.self) {
			self = .double(value)
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode([AnyJSON].self) {
			self = .array(value)
		} else if let value = try? container.decode([String: AnyJSON].self) {
			self = .dictionary(value)
		} else {
			let context = DecodingError.Context(codingPath: decoder.codingPath,
			                                    debugDescription: "Not a JSON type.")
			throw DecodingError.dataCorrupted(context)
		}
	}
}
