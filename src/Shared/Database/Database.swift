//
//  Database.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/26/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

@objc protocol Database {
    func querySqliteNodes() -> [NSNumber: OsmNode]?
    func querySqliteWays() -> [NSNumber: OsmWay]?
    func querySqliteRelations() -> [NSNumber: OsmRelation]?
}
