//
//  OverpassQueryParser.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/4/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
import JavaScriptCore

enum OverpassQueryParserResult {
    case success(BaseObjectMatching)
    case error(String)
}

protocol OverpassQueryParsing {
    func parse(_ query: String) -> OverpassQueryParserResult
}

class OverpassQueryParser: OverpassQueryParsing {
    
    // MARK: Private properties
    
    private let context: JSContext
    private let parseMethod: JSValue
    
    // MARK: Initializer
    
    init?() {
        guard let context = OverpassQueryParser.createContext() else {
            assertionFailure("Unable to create JSContext for parsing Overpass queries")
            return nil
        }
        self.context = context
        
        // Get the method that actually performs the parsing.
        guard let parseMethod = context.objectForKeyedSubscript("parse") else {
            assertionFailure("Unable to locate the method for parsing.")
            return nil
        }
        self.parseMethod = parseMethod
    }
    
    // MARK: Private methods
    
    private class func createContext() -> JSContext? {
        guard
            let parserPath = Bundle.main.path(forResource: "overpass-query-parser", ofType: "js"),
            let parserContents = try? String(contentsOfFile: parserPath)
        else {
            assertionFailure("Unable to read JavaScript source for parser.")
            return nil
        }
        
        guard let context = JSContext() else { return nil }
        context.evaluateScript(parserContents)
        
        return context
    }
    
    private func processParserResult(_ parserResult: [String: Any]) -> BaseObjectMatching? {
        guard let queryDetails = parserResult["query"] as? [String: Any] else { return nil }
        
        guard let queryOperation = queryDetails["query"] as? String else {
            assertionFailure("Unable to determine the query operation.")
            return nil
        }
        
        if queryOperation == "key", let key = queryDetails["key"] as? String {
            return KeyExistsQuery(key: key)
        } else if queryOperation == "nokey", let key = queryDetails["key"] as? String {
            return KeyExistsQuery(key: key, isNegated: true)
        }
        
        return nil
    }
    
    // MARK: OverpassQueryParsing
    
    func parse(_ query: String) -> OverpassQueryParserResult {
        let parseReturnValue = parseMethod.call(withArguments: [query])
        
        if let errorMessage = context.exception?.toString() {
            return .error(errorMessage)
        }
        
        guard
            let parserResult = parseReturnValue?.toDictionary() as? [String: Any],
            let resultingQuery = processParserResult(parserResult)
        else {
            // The method _must_ return an object. Not having one is very likely an error with the JavaScript itself.
            return .error("The parser did not return a value.")
        }
        
        return .success(resultingQuery)
    }
    
}
