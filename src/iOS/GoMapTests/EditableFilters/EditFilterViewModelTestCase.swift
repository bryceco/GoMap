//
//  EditFilterViewModelTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 10.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import XCTest
@testable import Go_Map__

class EditFilterViewModelTestCase: XCTestCase {
    
    var viewModel: EditFilterViewModel!
    var delegateMock: EditFilterViewModelDelegateMock!

    override func setUpWithError() throws {
        viewModel = EditFilterViewModel()
        
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock
    }

    override func tearDownWithError() throws {
        viewModel = nil
        delegateMock = nil
    }
    
    // MARK: addCondition()
    
    func testAddCondition_shouldAskDelegateToInsertSection() {
        /// When
        viewModel.addCondition()
        
        /// Then
        XCTAssertTrue(delegateMock.didCallAddSection)
    }
    
    func testAddCondition_whenThereAreNoConditionsYet_shouldAskDelegateToInsertRowsInFirstSection() {
        /// When
        viewModel.addCondition()
        
        /// Then
        XCTAssertEqual(delegateMock.addSection, 0)
    }
    
    func testAddCondition_whenThereIsAlreadyACondition_shouldAskDelegateToInsertRowsInSecondSection() {
        /// Given
        viewModel.addCondition()
        
        /// Reset the delegate, since the `addRows(at:)` will be called again.
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock
        
        /// When
        viewModel.addCondition()
        
        /// Then
        XCTAssertEqual(delegateMock.addSection, 1)
    }
    
    func testAddCondition_shouldAddSection() {
        /// Given
        let initialNumberOfSections = viewModel.sections.count
        
        /// When
        viewModel.addCondition()
        
        /// Then
        XCTAssertEqual(viewModel.sections.count, initialNumberOfSections + 1)
    }
    
    func testAddCondition_shouldAddSectionWhereFirstRowIsEmptyTagKeyTextFieldCell() {
        /// When
        viewModel.addCondition()
        
        /// Then
        let expectedRow: EditFilterViewModel.Row = .textField(placeholder: "Key", value: nil)
        XCTAssertEqual(viewModel.sections.last?.rows[0], expectedRow)
    }
    
    func testAddCondition_shouldAddSectionWhereSecondRowIsOperationPickerToggle() {
        /// Given
        guard let defaultOperation = EditFilterViewModel.Operation.allCases.first else {
            XCTFail()
            return
        }
        
        /// When
        viewModel.addCondition()
        
        /// Then
        let expectedRow: EditFilterViewModel.Row = .operationPickerToggle(operation: defaultOperation)
        XCTAssertEqual(viewModel.sections.last?.rows[1], expectedRow)
    }
    
    func testAddCondition_shouldAddSectionWhereThirdRowIsEmptyTagValueTextFieldCell() {
        /// When
        viewModel.addCondition()
        
        /// Then
        let expectedRow: EditFilterViewModel.Row = .textField(placeholder: "Value", value: nil)
        XCTAssertEqual(viewModel.sections.last?.rows[2], expectedRow)
    }
    
    func testAddCondition_shouldAskDelegateToShowKeyboardForFirstCellInNewSection() {
        /// Given
        viewModel.addCondition()
        viewModel.addCondition()
        viewModel.addCondition()
        
        /// Reset the delegate, since the `showKeyboardForTextFieldCell(at:)` will be called again.
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock
        
        /// When
        viewModel.addCondition()
        
        /// Then
        XCTAssertTrue(delegateMock.didCallShowKeyboardForTextFieldCell)
        XCTAssertEqual(delegateMock.textFieldCellIndexPath, IndexPath(row: 0, section: 3))
    }

}
