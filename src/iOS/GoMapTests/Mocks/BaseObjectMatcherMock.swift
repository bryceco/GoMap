//
//  BaseObjectMatcherMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/5/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
@testable import Go_Map__

class BaseObjectMatcherMock: NSObject {
    /// Is used to compare mocks.
    let identifier = UUID()

    var object: OsmBaseObject?
    var doesMatch: Bool

    init(doesMatch: Bool = false) {
        self.doesMatch = doesMatch
    }
}

extension BaseObjectMatcherMock: BaseObjectMatching {
    func matches(_ object: OsmBaseObject) -> Bool {
        self.object = object

        return doesMatch
    }
}
