//
//  Filter.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 13.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

enum Filter {
    enum RecursiveLogical: Int, Codable {
        case and
        case or
    }

    case keyExists(key: String, isNegated: Bool)
    case keyValue(key: String, value: String, isNegated: Bool)
    case regularExpression(key: String, value: String, isNegated: Bool)
    case recursive(logical: RecursiveLogical, filters: [Filter])
}

extension Filter: Codable {
    private enum FilterType: String, Codable {
        case keyExists
        case keyValue
        case regularExpression
        case recursive
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case key
        case value
        case isNegated
        case logical
        case filters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(FilterType.self, forKey: .type)

        switch type {
        case .keyExists:
            let key = try container.decode(String.self, forKey: .key)
            let isNegated = try container.decode(Bool.self, forKey: .isNegated)
            self = .keyExists(key: key, isNegated: isNegated)
        case .keyValue:
            let key = try container.decode(String.self, forKey: .key)
            let value = try container.decode(String.self, forKey: .value)
            let isNegated = try container.decode(Bool.self, forKey: .isNegated)
            self = .keyValue(key: key, value: value, isNegated: isNegated)
        case .regularExpression:
            let key = try container.decode(String.self, forKey: .key)
            let value = try container.decode(String.self, forKey: .value)
            let isNegated = try container.decode(Bool.self, forKey: .isNegated)
            self = .regularExpression(key: key, value: value, isNegated: isNegated)
        case .recursive:
            let logical = try container.decode(RecursiveLogical.self, forKey: .logical)
            let filters = try container.decode([Filter].self, forKey: .filters)
            self = .recursive(logical: logical, filters: filters)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .keyExists(key, isNegated):
            try container.encode(FilterType.keyExists.rawValue, forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encode(isNegated, forKey: .isNegated)
        case let .keyValue(key, value, isNegated):
            try container.encode(FilterType.keyValue.rawValue, forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encode(value, forKey: .value)
            try container.encode(isNegated, forKey: .isNegated)
        case let .regularExpression(key, value, isNegated):
            try container.encode(FilterType.regularExpression.rawValue, forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encode(value, forKey: .value)
            try container.encode(isNegated, forKey: .isNegated)
        case let .recursive(logical, filters):
            try container.encode(FilterType.recursive.rawValue, forKey: .type)
            try container.encode(logical, forKey: .logical)
            try container.encode(filters, forKey: .filters)
        }
    }
}
