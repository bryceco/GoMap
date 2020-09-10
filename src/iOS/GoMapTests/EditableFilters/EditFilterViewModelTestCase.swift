//
//  EditFilterViewModelTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 10.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import XCTest
@testable import Go_Map__

class EditFilterViewModelTestCase: XCTestCase {
    
    var viewModel: EditFilterViewModel!

    override func setUpWithError() throws {
        viewModel = EditFilterViewModel()
    }

    override func tearDownWithError() throws {
        viewModel = nil
    }

}
