//
//  BaseObjectMatching.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

/// Protocol for objects that can be used to match an `OsmBaseObject` against.
protocol BaseObjectMatching {
    
    /// Attempts to matches the given `OsmBaseObject`.
    ///
    /// - Parameter object: The object to match.
    /// - Returns: YES if the given object matches, NO if it does not.
    func matches(_ object: OsmBaseObject) -> Bool
    
}
