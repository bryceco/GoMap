//
//  OverpassQueryParserMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
@testable import Go_Map__

class OverpassQueryParserMock: NSObject {
    var didCallParse = false
    var query: String?
    var mockedResult: OverpassQueryParserResult = .success(BaseObjectMatcherMock())
}

extension OverpassQueryParserMock: OverpassQueryParsing {
    
    func parse(_ query: String) -> OverpassQueryParserResult {
        didCallParse = true
        self.query = query
        
        return mockedResult
    }
    
}
