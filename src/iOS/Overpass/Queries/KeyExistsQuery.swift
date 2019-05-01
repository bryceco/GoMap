//
//  KeyExistsQuery.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

struct KeyExistsQuery {
    let key: String
    let isNegated: Bool
    
    init(key: String, isNegated: Bool = false) {
        self.key = key
        self.isNegated = isNegated
    }
}

extension KeyExistsQuery: BaseObjectMatching {
    
    func matches(_ object: OsmBaseObject) -> Bool {
        let keyExists = object.tags?.keys.contains(key) ?? false
        
        if isNegated {
            return !keyExists
        } else {
            return keyExists
        }
    }
    
}
