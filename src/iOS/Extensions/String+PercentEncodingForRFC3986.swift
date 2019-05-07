//
//  String+PercentEncodingForRFC3986.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

extension String {
    func addingPercentEncodingForRFC3986() -> String? {
        let unreserved = "-._~/?"
        let allowed = NSMutableCharacterSet.alphanumeric()
        allowed.addCharacters(in: unreserved)
        
        return addingPercentEncoding(withAllowedCharacters: allowed as CharacterSet)
    }
}
