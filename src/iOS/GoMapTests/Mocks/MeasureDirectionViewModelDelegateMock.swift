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
    var dismissCalled = false
    var dismissDirection: String?
}

extension MeasureDirectionViewModelDelegateMock: MeasureDirectionViewModelDelegate {
    func dismiss(_ direction: String?) {
        dismissCalled = true
        dismissDirection = direction
    }
}
