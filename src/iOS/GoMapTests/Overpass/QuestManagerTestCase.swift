//
//  QuestManagerTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import XCTest

@testable import Go_Map__

class QuestManagerTestCase: XCTestCase {
    
    var manager: QuestManaging!
    var userDefaults: UserDefaults!
    var activeQueryUserDefaultsKey = "foo-bar"
    var notificationCenter: NotificationCenter!

    override func setUp() {
        super.setUp()
        
        // Create UserDefaults and make sure it's empty.
        userDefaults = UserDefaults(suiteName: String(describing: type(of: self)))
        userDefaults.dictionaryRepresentation().keys.forEach { key in
            userDefaults.removeObject(forKey: key)
        }
        
        notificationCenter = NotificationCenter()
        
        manager = QuestManager(userDefaults: userDefaults,
                               activeQueryUserDefaultsKey: activeQueryUserDefaultsKey,
                               notificationCenter: notificationCenter)
    }

    override func tearDown() {
        manager = nil
        userDefaults = nil
        
        super.tearDown()
    }

    func testActiveQuestQueryShouldBeStoredInUserDefaults() {
        let query = "camera:mount = pole"
        manager.activeQuestQuery = query
        
        // Create another manager instance from the same user defaults.
        let secondManager = QuestManager(userDefaults: userDefaults,
                                         activeQueryUserDefaultsKey: activeQueryUserDefaultsKey)
        XCTAssertEqual(secondManager.activeQuestQuery, query)
        
        // Change the value in the second manager and make sure the initial manager is updated as well.
        secondManager.activeQuestQuery = nil
        XCTAssertNil(manager.activeQuestQuery)
    }

}
