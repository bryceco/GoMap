//
//  QuestManagerMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
@testable import Go_Map__

class QuestManagerMock: NSObject, QuestManaging {
    var activeQuestQuery: String?
}
