//
//  QueryFormViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/6/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

class QueryFormViewModel: NSObject {
    
    // MARK: Public properties
    
    var queryText = Observable<String>("")
    var errorMessage = Observable<String>("")
    var isSaveButtonEnabled = Observable<Bool>(false)
    
    // MARK: Private properties
    
    private let parser: OverpassQueryParsing
    
    // MARK: Initializer
    
    init(parser: OverpassQueryParsing) {
        self.parser = parser
    }
    
    convenience override init() {
        let parser = OverpassQueryParser()
        
        assert(parser != nil, "Unable to create the query parser.")
        
        self.init(parser: parser!)
    }
    
    // MARK: Public methods
    
    func evaluateQuery(_ query: String) {
        let result = parser.parse(query)
        
        switch result {
        case .error(let message):
            errorMessage.value = message
        case .success(_):
            errorMessage.value = ""
        }
    }

}
