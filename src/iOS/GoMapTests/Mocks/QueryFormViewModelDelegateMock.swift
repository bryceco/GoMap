//
//  QueryFormViewModelDelegateMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
@testable import Go_Map__

class QueryFormViewModelDelegateMock: NSObject {
    var didCallPresentPreview = false
    var previewURL: String?
}

extension QueryFormViewModelDelegateMock: QueryFormViewModelDelegate {
    
    func presentPreviewWithOverpassTurbo(url: String) {
        didCallPresentPreview = true
        previewURL = url
    }
    
}
