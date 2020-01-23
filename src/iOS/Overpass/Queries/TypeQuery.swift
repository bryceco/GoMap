//
//  TypeQuery.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

enum ElementType: String {
    case node, way, relation
}

struct TypeQuery {
    let type: ElementType
}

extension TypeQuery: BaseObjectMatching {
    
    func matches(_ object: OsmBaseObject) -> Bool {
        switch type {
        case .node:
            return object is OsmNode
        case .way:
            return object is OsmWay
        case .relation:
            return object is OsmRelation
        }
    }
    
}
