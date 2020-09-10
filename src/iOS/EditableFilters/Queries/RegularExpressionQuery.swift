//
//  RegularExpressionQuery.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/5/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

struct RegularExpressionQuery {
    let key: String
    let value: String
    let isNegated: Bool

    init(key: String, value: String, isNegated: Bool = false) {
        self.key = key
        self.value = value
        self.isNegated = isNegated
    }
}

extension RegularExpressionQuery: BaseObjectMatching {
    func matches(_ object: OsmBaseObject) -> Bool {
        guard let tags = object.tags else { return false }

        let regularExpressionDoesMatch = tags.first { tagKey, tagValue in
            tagKey.range(of: key, options: .regularExpression) != nil && tagValue.range(of: value, options: .regularExpression) != nil
        } != nil

        if isNegated {
            return !regularExpressionDoesMatch
        } else {
            return regularExpressionDoesMatch
        }
    }
}
