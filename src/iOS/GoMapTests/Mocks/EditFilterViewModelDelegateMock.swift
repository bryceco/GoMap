//
//  EditFilterViewModelDelegateMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 10.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

@testable import Go_Map__

final class EditFilterViewModelDelegateMock: NSObject {
    private(set) var didCallAddRows = false
    private(set) var addRowsIndexPaths = [IndexPath]()
}

extension EditFilterViewModelDelegateMock: EditFilterViewModelDelegate {
    func addRows(at indexPaths: [IndexPath]) {
        didCallAddRows = true
        
        addRowsIndexPaths = indexPaths
    }
}
