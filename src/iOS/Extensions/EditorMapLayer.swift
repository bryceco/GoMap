//
//  EditorMapLayer.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/10/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

@objc extension EditorMapLayer {
    
    func observeQuestChanges() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveActiveQuestChangedNotification(_:)),
                                               name: .QuestManagerDidUpdateActiveQuest,
                                               object: nil)
    }
    
    func didReceiveActiveQuestChangedNotification(_ note: Notification) {
        resetDisplayLayers()
    }
    
}
