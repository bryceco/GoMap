//
//  MapViewQuestAnnotationManager.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/10/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

@objc protocol MapViewQuestAnnotationManaging {
    func shouldShowQuestAnnotation(for baseObject: OsmBaseObject) -> Bool
}

@objc class MapViewQuestAnnotationManager: NSObject, MapViewQuestAnnotationManaging {
    
    // MARK: Private properties
    
    private let questManager: QuestManaging
    private let queryParser: OverpassQueryParsing
    
    private var lastParsedQuery: String?
    private var lastMatcher: BaseObjectMatching?
    
    // MARK: Initializer
    
    init(questManager: QuestManaging, queryParser: OverpassQueryParsing) {
        self.questManager = questManager
        self.queryParser = queryParser
    }
    
    convenience override init() {
        let questManager = QuestManager()
        
        let parser = OverpassQueryParser()
        assert(parser != nil, "Unable to create the query parser.")
        
        self.init(questManager: questManager, queryParser: parser!)
    }
    
    // MARK: MapViewQuestAnnotationManaging
    
    func shouldShowQuestAnnotation(for baseObject: OsmBaseObject) -> Bool {
        guard let activeQuery = questManager.activeQuestQuery else {
            // Without an active query, there's no need to show an annotation.
            return false
        }
        
        guard activeQuery != lastParsedQuery else {
            // We've already parsed this query before, and there's no need to do it again.
            return lastMatcher?.matches(baseObject) ?? false
        }
        
        // Remember the query that was parsed last.
        lastParsedQuery = activeQuery
        
        guard
            case let .success(parsedMatcher) = queryParser.parse(activeQuery),
            let matcher = parsedMatcher
        else {
            lastMatcher = nil
            
            return false
        }
        
        // Remember the parsed matcher.
        lastMatcher = matcher
        
        return matcher.matches(baseObject)
    }

}
