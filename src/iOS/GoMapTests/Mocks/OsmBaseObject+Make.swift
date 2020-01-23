//
//  OsmBaseObject+Make.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/1/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

@testable import Go_Map__

extension OsmBaseObject {
    
    static func makeBaseObjectWithTag(_ key: String, _ value: String) -> OsmBaseObject {
        let object = OsmBaseObject.init()
        
        object.constructTag(key, value: value)
        
        return object
    }
    
}
