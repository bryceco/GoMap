//
//  EditFilterViewModelDelegateMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 10.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

@testable import Go_Map__

final class EditFilterViewModelDelegateMock: NSObject {
    private(set) var didCallAddSection = false
    private(set) var addSection: Int?
    
    private(set) var didCallAddRows = false
    private(set) var addRowsIndexPaths = [IndexPath]()
    
    private(set) var didCallRemoveRows = false
    private(set) var removeRowsIndexPaths = [IndexPath]()
    
    private(set) var didCallShowKeyboardForTextFieldCell = false
    private(set) var textFieldCellIndexPath: IndexPath?
}

extension EditFilterViewModelDelegateMock: EditFilterViewModelDelegate {
    func addSection(_ section: Int) {
        didCallAddSection = true
        
        addSection = section
    }
    
    func addRows(at indexPaths: [IndexPath]) {
        didCallAddRows = true
        
        addRowsIndexPaths = indexPaths
    }
    
    func removeRows(at indexPaths: [IndexPath]) {
        didCallRemoveRows = true
        
        removeRowsIndexPaths = indexPaths
    }
    
    func showKeyboardForTextFieldCell(at indexPath: IndexPath) {
        didCallShowKeyboardForTextFieldCell = true
        
        textFieldCellIndexPath = indexPath
    }
}
