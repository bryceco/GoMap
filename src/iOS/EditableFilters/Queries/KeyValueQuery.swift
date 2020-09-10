//
//  KeyValueQuery.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/5/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

struct KeyValueQuery {
    let key: String
    let value: String
    let isNegated: Bool

    init(key: String, value: String, isNegated: Bool = false) {
        self.key = key
        self.value = value
        self.isNegated = isNegated
    }
}

extension KeyValueQuery: BaseObjectMatching {
    func matches(_ object: OsmBaseObject) -> Bool {
        guard let valueOfObject = object.tags?[key] else {
            /// The object does not have a tag with the given key.
            if isNegated {
                /// Treat the absence of a tag with the given key as a match when the query is negated.
                return true
            } else {
                return false
            }
        }

        return valueOfObject == value
    }
}
