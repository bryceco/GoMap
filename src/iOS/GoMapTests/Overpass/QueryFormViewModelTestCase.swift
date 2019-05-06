//
//  QueryFormViewModelTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class QueryFormViewModelTestCase: XCTestCase {
    
    var viewModel: QueryFormViewModel!

    override func setUp() {
        super.setUp()
        
        viewModel = QueryFormViewModel()
    }

    override func tearDown() {
        viewModel = nil
        
        super.tearDown()
    }
    
    // MARK: queryText
    
    func testQueryTextShouldInitiallyBeEmpty() {
        XCTAssertTrue(viewModel.queryText.value.isEmpty)
    }

}
