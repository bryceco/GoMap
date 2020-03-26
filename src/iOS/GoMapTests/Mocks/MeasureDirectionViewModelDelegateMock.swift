//
//  MeasureDirectionViewModelDelegateMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 4/3/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
@testable import Go_Map__

class MeasureDirectionViewModelDelegateMock: NSObject {
    var didFinishUpdatingTagCalled = false
    var key: String?
    var value: String?
}

extension MeasureDirectionViewModelDelegateMock: MeasureDirectionViewModelDelegate {
    func didFinishUpdatingTag(key: String, value: String?) {
        didFinishUpdatingTagCalled = true
        
        self.key = key
        self.value = value
    }
}
