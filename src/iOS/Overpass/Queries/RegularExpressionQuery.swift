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
}

extension RegularExpressionQuery: BaseObjectMatching {
    
    func matches(_ object: OsmBaseObject) -> Bool {
        guard let tags = object.tags else { return false }
        
        return tags.first { tagKey, tagValue in
            return tagKey.range(of: key, options: .regularExpression) != nil && tagValue.range(of: value, options: .regularExpression) != nil
        } != nil
    }
    
}
