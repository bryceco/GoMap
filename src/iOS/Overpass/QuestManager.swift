//
//  QuestManager.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/7/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

protocol QuestManaging {
    var activeQuestQuery: String? { get set }
}

final class QuestManager: NSObject, QuestManaging {
    
    // MARK: Private properties
    
    private let userDefaults: UserDefaults
    private let activeQueryUserDefaultsKey: String
    private let notificationCenter: NotificationCenter
    
    // MARK: Initializer
    
    init(userDefaults: UserDefaults = .standard,
         activeQueryUserDefaultsKey: String = "activeQuestQuery",
         notificationCenter: NotificationCenter = .default) {
        self.userDefaults = userDefaults
        self.activeQueryUserDefaultsKey = activeQueryUserDefaultsKey
        self.notificationCenter = notificationCenter
    }
    
    var activeQuestQuery: String? {
        get { return userDefaults.string(forKey: activeQueryUserDefaultsKey) }
        set { userDefaults.set(newValue, forKey: activeQueryUserDefaultsKey) }
    }
}
