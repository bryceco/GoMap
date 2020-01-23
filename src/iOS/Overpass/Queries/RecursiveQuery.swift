//
//  RecursiveQuery.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

struct RecursiveQuery {
    enum Logical: String, CaseIterable {
        case and, or
    }
    
    let logical: Logical
    let queries: [BaseObjectMatching]
    
    init(logical: Logical = .or, queries: [BaseObjectMatching]) {
        self.logical = logical
        self.queries = queries
    }
}

extension RecursiveQuery: BaseObjectMatching {
    
    func matches(_ object: OsmBaseObject) -> Bool {
        guard queries.count > 0 else {
            // Without child queries, the recursive query does not match any object.
            return false
        }
        
        switch logical {
        case .and:
            return queries.first { !$0.matches(object) } == nil
        case .or:
            return queries.first { $0.matches(object) } != nil
        }
    }
    
}
