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
        
        guard
            case let .success(parsedMatcher) = queryParser.parse(activeQuery),
            let matcher = parsedMatcher
        else {
            return false
        }
        
        return matcher.matches(baseObject)
    }

}
