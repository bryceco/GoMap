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
                    let direction = direction(from: value) {
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

        let cardinalDirectionToDegree: [String: Float] = ["north": 0,
														  "N": 0,
														  "NNE": 22.5,
														  "NE": 45,
														  "ENE": 67.5,
														  "east": 90,
														  "E": 90,
														  "ESE": 112.5,
														  "SE": 135,
														  "SSE": 157.5,
														  "south": 180,
														  "S": 180,
														  "SSW": 202.5,
														  "SW": 225,
														  "WSW": 247.5,
														  "west": 270,
														  "W": 270,
														  "WNW": 292.5,
														  "NW": 315]
        if let direction = cardinalDirectionToDegree[string] {
            return Int(direction)
        }
        
        return nil
    }
}
