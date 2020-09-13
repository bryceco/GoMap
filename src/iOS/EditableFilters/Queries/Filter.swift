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
