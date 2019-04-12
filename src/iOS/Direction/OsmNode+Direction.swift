//
//  OsmNode+Direction.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/10/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

extension OsmNode {
    
    /// The direction in which the node is facing.
    /// Since Objective-C is not able to work with optionals, the direction is `NSNotFound`
    /// if the node does not have a direction value instead of being `nil`.
    @objc var direction: Int {
        get {
            let keys = ["direction", "camera:direction"]
            for directionKey in keys {
                if
                    let value = tags?[directionKey],
                    let valueAsString = value as? String,
                    let direction = direction(from: valueAsString) {
                    return direction
                }
            }
            
            return NSNotFound
        }
    }
    
    private func direction(from string: String) -> Int? {
        if let direction = Int(string) {
            return direction
        }
        
        let cardinalDirectionToDegree: [String: Int] = ["N": 0,
                                                        "NE": 45,
                                                        "E": 90,
                                                        "SE": 135,
                                                        "S": 180,
                                                        "SW": 225,
                                                        "W": 270,
                                                        "NW": 315]
        if let direction = cardinalDirectionToDegree[string] {
            return direction
        }
        
        return nil
    }
}
