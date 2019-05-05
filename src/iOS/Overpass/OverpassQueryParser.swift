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
    case success(BaseObjectMatching?)
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
        
        return query(from: queryDetails)
    }
    
    /// Method that recursively creates the query from the given key/value pairs.
    ///
    /// - Parameter keyValuePairs: Key/value pairs with details on the query.
    /// - Returns: The query from the key/value pairs, if any.
    private func query(from keyValuePairs: [String: Any]) -> BaseObjectMatching? {
        if
            let logicalString = keyValuePairs["logical"] as? String,
            let logical = RecursiveQuery.Logical(rawValue: logicalString),
            let childQueryKeyValuePairs = keyValuePairs["queries"] as? [[String: Any]] {
            // This is a recursive query.
            let childQueries = childQueryKeyValuePairs.compactMap({ query(from: $0) })
            
            return RecursiveQuery(logical: logical, queries: childQueries)
        } else if let queryOperation = keyValuePairs["query"] as? String {
            if queryOperation == "key", let key = keyValuePairs["key"] as? String {
                return KeyExistsQuery(key: key)
            } else if queryOperation == "nokey", let key = keyValuePairs["key"] as? String {
                return KeyExistsQuery(key: key, isNegated: true)
            } else if queryOperation == "type", let typeString = keyValuePairs["type"] as? String, let type = ElementType(rawValue: typeString) {
                return TypeQuery(type: type)
            }
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
            let parserResult = parseReturnValue?.toDictionary() as? [String: Any]
        else {
            // The method _must_ return an object. Not having one is very likely an error with the JavaScript itself.
            return .error("The parser did not return a value.")
        }
        
        let resultingQuery = processParserResult(parserResult)
        return .success(resultingQuery)
    }
    
}
