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

extension AnyJSON {
	func prettyPrinted(tabWidth: Int, indentLevel: Int = 0) -> String {
		let tab = String(repeating: " ", count: tabWidth)
		let indent = String(repeating: tab, count: indentLevel)
		let nextIndent = String(repeating: tab, count: indentLevel + 1)

		switch self {
		case .null:
			return "null"
		case let .string(value):
			return "\"\(value)\""
		case let .double(value):
			return String(value)
		case let .bool(value):
			return String(value)
		case let .array(values):
			if values.isEmpty { return "[]" }
			let items = values
				.map { "\(nextIndent)\($0.prettyPrinted(tabWidth: tabWidth, indentLevel: indentLevel + 1))" }
			return "[\n" + items.joined(separator: ",\n") + "\n\(indent)]"
		case let .dictionary(dict):
			if dict.isEmpty { return "{}" }
			let items = dict.map {
				let key = "\"\($0.key)\""
				let value = $0.value.prettyPrinted(tabWidth: tabWidth, indentLevel: indentLevel + 1)
				return "\(nextIndent)\(key): \(value)"
			}
			return "{\n" + items.sorted().joined(separator: ",\n") + "\n\(indent)}"
		}
	}
}

#if DEBUG
func jsonAsPrettyString(_ json: Any) -> String? {
	if let data = json as? Data {
		guard let object = try? JSONSerialization.jsonObject(with: data)
		else { return nil }
		return jsonAsPrettyString(object)
	}
	guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
		  let string = String(data: data, encoding: .utf8)
	else {
		return nil
	}
	return string
}
#endif
