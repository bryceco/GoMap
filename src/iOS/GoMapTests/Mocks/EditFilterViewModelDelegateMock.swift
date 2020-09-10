//
//  EditFilterViewModelDelegateMock.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 10.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

@testable import Go_Map__

final class EditFilterViewModelDelegateMock: NSObject {
    private(set) var didCallInsertSection = false
    private(set) var insertSection: Int?

    private(set) var didCallAddRows = false
    private(set) var addRowsIndexPaths = [IndexPath]()

    private(set) var didCallRemoveRows = false
    private(set) var removeRowsIndexPaths = [IndexPath]()

    private(set) var didCallShowKeyboardForTextFieldCell = false
    private(set) var textFieldCellIndexPath: IndexPath?

    private(set) var didCallSetTextForTextLabelCell = false
    private(set) var setTextForTextLabelCellArguments: (indexPath: IndexPath, text: String)?
}

extension EditFilterViewModelDelegateMock: EditFilterViewModelDelegate {
    func insertSection(_ section: Int) {
        didCallInsertSection = true

        insertSection = section
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

    func setTextForTextLabelCell(at indexPath: IndexPath, to text: String) {
        didCallSetTextForTextLabelCell = true

        setTextForTextLabelCellArguments = (indexPath, text)
    }
}
