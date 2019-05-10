//
//  QueryFormViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/6/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

protocol QueryFormViewModelDelegate: class {
    /// Asks the delegate to present the preview with the given URL string.
    ///
    /// - Parameter url: The URL of the preview address as a string.
    func presentPreviewWithOverpassTurbo(url: String)
}

class QueryFormViewModel: NSObject {
    
    // MARK: Public properties
    
    var queryText = Observable<String>("")
    var errorMessage = Observable<String>("")
    var isPreviewButtonEnabled = Observable<Bool>(false)
    
    weak var delegate: QueryFormViewModelDelegate?
    
    // MARK: Private properties
    
    private let parser: OverpassQueryParsing
    private var questManager: QuestManaging
    
    /// The last successfully parsed query string.
    /// When the parser results in an error, this string is set to an empty string.
    private var mostRecentSuccessfulQuery = "" {
        didSet {
            isPreviewButtonEnabled.value = !mostRecentSuccessfulQuery.isEmpty
        }
    }
    
    // MARK: Initializer
    
    init(parser: OverpassQueryParsing,
         questManager: QuestManaging = QuestManager()) {
        self.parser = parser
        self.questManager = questManager
        
        super.init()
        
        if let activeQuery = questManager.activeQuestQuery {
            evaluateQuery(activeQuery)
        }
        self.queryText.value = self.mostRecentSuccessfulQuery
    }
    
    convenience override init() {
        let parser = OverpassQueryParser()
        
        assert(parser != nil, "Unable to create the query parser.")
        
        self.init(parser: parser!)
    }
    
    // MARK: Public methods
    
    func evaluateQuery(_ query: String) {
        guard !query.isEmpty else {
            mostRecentSuccessfulQuery = ""
            errorMessage.value = ""
            return
        }
        
        let result = parser.parse(query)
        
        switch result {
        case .error(let message):
            mostRecentSuccessfulQuery = ""
            errorMessage.value = message
        case .success(let baseObjectMatcher):
            mostRecentSuccessfulQuery = baseObjectMatcher == nil ? "" : query
            errorMessage.value = ""
        }
    }
    
    func presentPreview() {
        guard
            !mostRecentSuccessfulQuery.isEmpty,
            let escapedQuery = mostRecentSuccessfulQuery.addingPercentEncodingForRFC3986()
        else {
            // Without a proper query, there's no need to notify the delegate.
            return
        }
        
        let previewURL = "https://overpass-turbo.eu?w=\(escapedQuery)&R"
        delegate?.presentPreviewWithOverpassTurbo(url: previewURL)
    }
    
    func viewWillDisappear() {
        let queryToSave: String?
        if mostRecentSuccessfulQuery.isEmpty {
            queryToSave = nil
        } else {
            queryToSave = mostRecentSuccessfulQuery
        }
        
        questManager.activeQuestQuery = queryToSave
    }

}
