//
//  EditFilterViewModelTestCase.swift
//  GoMapTests
//
//  Created by Wolfgang Timme on 10.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

@testable import Go_Map__
import XCTest

class EditFilterViewModelTestCase: XCTestCase {
    var viewModel: EditFilterViewModel!
    var delegateMock: EditFilterViewModelDelegateMock!

    override func setUpWithError() throws {
        setupViewModel()
    }

    override func tearDownWithError() throws {
        viewModel = nil
        delegateMock = nil
    }

    // MARK: Helper methods

    private func setupViewModel(availableFilterTypes: [Filter.FilterType: String] = [:],
                                filters: [Filter] = [])
    {
        viewModel = EditFilterViewModel(availableFilterTypes: availableFilterTypes,
                                        filters: filters)

        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock
    }

    // MARK: init(queries:)

    func testInit_whenFirstQueryIsKeyExistsQuery_shouldResultInOneSectionWithTextFieldCellAndExistsOperationToggleCell() {
        /// Given
        let key = "some-key"
        let filter = Filter.keyExists(key: key)

        /// When
        setupViewModel(filters: [filter])

        /// Then
        XCTAssertEqual(viewModel.sections.count, 1)

        let expectedRows = [EditFilterViewModel.Row.textField(placeholder: "Key", value: key),
                            EditFilterViewModel.Row.operationPickerToggle(operation: .exists)]
        XCTAssertEqual(viewModel.sections[0].rows, expectedRows)
    }

    func testInit_whenFirstQueryIsNegatedKeyExistsQuery_shouldResultInOneSectionWithTextFieldCellAndDoesNotExistOperationToggleCell() {
        /// Given
        let key = "some-key"
        let filter = Filter.keyExists(key: key, isNegated: true)

        /// When
        setupViewModel(filters: [filter])

        /// Then
        XCTAssertEqual(viewModel.sections.count, 1)

        let expectedRows = [EditFilterViewModel.Row.textField(placeholder: "Key", value: key),
                            EditFilterViewModel.Row.operationPickerToggle(operation: .doesNotExist)]
        XCTAssertEqual(viewModel.sections[0].rows, expectedRows)
    }

    func testInit_whenFirstQueryIsKeyValueQuery_shouldResultInOneSectionWithTextFieldCellAndEqualsOperationToggleCellAndAnotherTextFieldCell() {
        /// Given
        let key = "some-key"
        let value = "example-value"
        let filter = Filter.keyValue(key: key, value: value)

        /// When
        setupViewModel(filters: [filter])

        /// Then
        XCTAssertEqual(viewModel.sections.count, 1)

        let expectedRows = [EditFilterViewModel.Row.textField(placeholder: "Key", value: key),
                            EditFilterViewModel.Row.operationPickerToggle(operation: .equals),
                            EditFilterViewModel.Row.textField(placeholder: "Value", value: value)]
        XCTAssertEqual(viewModel.sections[0].rows, expectedRows)
    }

    func testInit_whenFirstQueryIsNegatedKeyValueQuery_shouldResultInOneSectionWithTextFieldCellAndDoesNotEqualOperationToggleCellAndAnotherTextFieldCell() {
        /// Given
        let key = "some-key"
        let value = "example-value"
        let filter = Filter.keyValue(key: key, value: value, isNegated: true)

        /// When
        setupViewModel(filters: [filter])

        /// Then
        XCTAssertEqual(viewModel.sections.count, 1)

        let expectedRows = [EditFilterViewModel.Row.textField(placeholder: "Key", value: key),
                            EditFilterViewModel.Row.operationPickerToggle(operation: .doesNotEqual),
                            EditFilterViewModel.Row.textField(placeholder: "Value", value: value)]
        XCTAssertEqual(viewModel.sections[0].rows, expectedRows)
    }

    func testInit_whenFirstQueryIsRegularExpressionQuery_shouldResultInOneSectionWithTextFieldCellAndMatchesOperationToggleCellAndAnotherTextFieldCell() {
        /// Given
        let key = "man_*"
        let value = "surveill*"
        let filter = Filter.regularExpression(key: key, value: value)

        /// When
        setupViewModel(filters: [filter])

        /// Then
        XCTAssertEqual(viewModel.sections.count, 1)

        let expectedRows = [EditFilterViewModel.Row.textField(placeholder: "Key", value: key),
                            EditFilterViewModel.Row.operationPickerToggle(operation: .matches),
                            EditFilterViewModel.Row.textField(placeholder: "Value", value: value)]
        XCTAssertEqual(viewModel.sections[0].rows, expectedRows)
    }

    func testInit_whenFirstQueryNegatedIsRegularExpressionQuery_shouldResultInOneSectionWithTextFieldCellAndDoesNotMatchOperationToggleCellAndAnotherTextFieldCell() {
        /// Given
        let key = "man_*"
        let value = "surveill*"
        let filter = Filter.regularExpression(key: key, value: value, isNegated: true)

        /// When
        setupViewModel(filters: [filter])

        /// Then
        XCTAssertEqual(viewModel.sections.count, 1)

        let expectedRows = [EditFilterViewModel.Row.textField(placeholder: "Key", value: key),
                            EditFilterViewModel.Row.operationPickerToggle(operation: .doesNotMatch),
                            EditFilterViewModel.Row.textField(placeholder: "Value", value: value)]
        XCTAssertEqual(viewModel.sections[0].rows, expectedRows)
    }

    // MARK: addCondition()

    func testAddCondition_shouldAskDelegateToInsertSection() {
        /// When
        viewModel.addCondition()

        /// Then
        XCTAssertTrue(delegateMock.didCallInsertSection)
    }

    func testAddCondition_whenThereAreNoConditionsYet_shouldAskDelegateToInsertRowsInFirstSection() {
        /// When
        viewModel.addCondition()

        /// Then
        XCTAssertEqual(delegateMock.insertSection, 0)
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
        XCTAssertEqual(delegateMock.insertSection, 1)
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

    // MARK: selectRow(at:)

    func testSelectRow_whenRowIsFirstOrThirdOne_shouldNotAskDelegateToAddRows() {
        /// Given
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 0, section: 0))
        viewModel.selectRow(at: IndexPath(row: 2, section: 0))

        /// Then
        XCTAssertFalse(delegateMock.didCallAddRows)
    }

    func testSelectRow_whenSectionDoesNotExist_shouldNotAskDelegateToAddRows() {
        /// Given
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 1, section: 9999))

        /// Then
        XCTAssertFalse(delegateMock.didCallAddRows)
    }

    func testSelectRow_whenRowDoesNotExist_shouldNotAskDelegateToAddRows() {
        /// Given
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 9999, section: 0))

        /// Then
        XCTAssertFalse(delegateMock.didCallAddRows)
    }

    func testSelectRow_whenRowIsSecondOne_shouldInsertOperationPickerCellAtThirdPositionInSection() {
        /// Given
        guard let defaultOperation = EditFilterViewModel.Operation.allCases.first else {
            XCTFail()
            return
        }

        viewModel.addCondition()
        viewModel.addCondition()
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 1, section: 2))

        /// Then
        XCTAssertEqual(viewModel.sections[2].rows.count, 4)
        XCTAssertEqual(viewModel.sections[2].rows[2], EditFilterViewModel.Row.operationPicker(operation: defaultOperation))
    }

    func testSelectRow_whenRowIsSecondOne_shouldInsertOperationPickerCellWithOperationOfTheSecondRowAtThirdPositionInSection() {
        /// Given
        let operation: EditFilterViewModel.Operation = .doesNotEqual
        viewModel.addCondition()

        /// Open picker and change operation.
        viewModel.changeOperationForSection(0, toOperation: operation)

        /// When
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Then
        XCTAssertEqual(viewModel.sections[0].rows[2], EditFilterViewModel.Row.operationPicker(operation: operation))
    }

    func testSelectRow_whenRowIsSecondOne_shouldAskDelegateToAddRowAtThirdPosition() {
        /// Given
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Then
        XCTAssertTrue(delegateMock.didCallAddRows)
        XCTAssertEqual(delegateMock.addRowsIndexPaths, [IndexPath(row: 2, section: 0)])
    }

    func testSelectRow_whenRowIsSecondOneAndTappedForTheSecondTime_shouldRemoveOperationPickerCellFromThirdPositionInSection() {
        /// Given
        viewModel.addCondition()
        viewModel.addCondition()
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 1, section: 2))
        viewModel.selectRow(at: IndexPath(row: 1, section: 2))

        /// Then
        XCTAssertEqual(viewModel.sections[2].rows.count, 3)
    }

    func testSelectRow_whenRowIsSecondOneAndTappedForTheSecondTime_shouldAskDelegateToRemoveRowAtThirdPosition() {
        /// Given
        viewModel.addCondition()

        /// When
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Then
        XCTAssertTrue(delegateMock.didCallRemoveRows)
        XCTAssertEqual(delegateMock.removeRowsIndexPaths, [IndexPath(row: 2, section: 0)])
    }

    // MARK: changeOperationForSection(_:toOperation:)

    func testChangeOperationForSection_whenGivenAnInvalidSection_shouldNotAskDelegateToSetText() {
        /// When
        viewModel.changeOperationForSection(9999, toOperation: .doesNotEqual)

        /// Then
        XCTAssertFalse(delegateMock.didCallSetTextForTextLabelCell)
    }

    func testChangeOperationForSection_whenGivenAValidSection_shouldAskDelegateToSetTextForTheOperationPickerToggleCell() {
        /// Given
        let updatedOperation: EditFilterViewModel.Operation = .doesNotExist
        viewModel.addCondition()

        /// When
        viewModel.changeOperationForSection(0, toOperation: updatedOperation)

        /// Then
        XCTAssertTrue(delegateMock.didCallSetTextForTextLabelCell)
        XCTAssertEqual(delegateMock.setTextForTextLabelCellArguments?.indexPath, IndexPath(row: 1, section: 0))
        XCTAssertEqual(delegateMock.setTextForTextLabelCellArguments?.text, updatedOperation.humanReadableString)
    }

    func testChangeOperationForSection_whenGivenAValidSection_shouldUpdateRowInDataModel() {
        /// Given
        let updatedOperation: EditFilterViewModel.Operation = .matches

        viewModel.addCondition()
        viewModel.addCondition()
        viewModel.addCondition()

        /// When
        viewModel.changeOperationForSection(2, toOperation: updatedOperation)

        /// Then
        let expectedSecondRow = EditFilterViewModel.Row.operationPickerToggle(operation: updatedOperation)
        let secondRow = viewModel.sections[2].rows[1]
        XCTAssertEqual(secondRow, expectedSecondRow)
    }

    func testChangeOperationForSection_whenSetToExists_shouldAskDelegateRemoveLastCell() {
        /// Given
        viewModel.addCondition()

        /// When

        /// Expand the picker.
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Change the operation mode.
        viewModel.changeOperationForSection(0, toOperation: .exists)

        /// Then
        XCTAssertTrue(delegateMock.didCallRemoveRows)
        XCTAssertEqual(delegateMock.removeRowsIndexPaths, [IndexPath(row: 3, section: 0)])
    }

    func testChangeOperationForSection_whenGivenAValidSection_shouldRemoveRowFromDataModel() {
        /// Given
        viewModel.addCondition()

        /// When

        /// Expand the picker.
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Change the operation mode.
        viewModel.changeOperationForSection(0, toOperation: .exists)

        /// Then
        XCTAssertEqual(viewModel.sections[0].rows.count, 3)
    }

    func testChangeOperationForSection_whenSetToExistsButWasDoesNotExistBefore_shouldNotAskDelegateRemoveLastCell() {
        /// Given
        viewModel.addCondition()

        /// When

        /// Expand the picker.
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Change the operation mode once.
        viewModel.changeOperationForSection(0, toOperation: .doesNotExist)

        /// Reset the delegate, so that we are able to tell whether `removeRows(at:)` was called.
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock

        /// Change the operation mode once more.
        viewModel.changeOperationForSection(0, toOperation: .exists)

        /// Then
        XCTAssertFalse(delegateMock.didCallRemoveRows)
    }

    func testChangeOperationForSection_whenSetToMatchesAndWasExistsBefore_shouldAskDelegateToAddLastCell() {
        /// Given
        viewModel.addCondition()

        /// When

        /// Expand the picker.
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Change the operation mode once.
        viewModel.changeOperationForSection(0, toOperation: .exists)

        /// Reset the delegate, so that we are able to tell whether `addRows(at:)` was called.
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock

        /// Change the operation mode once more.
        viewModel.changeOperationForSection(0, toOperation: .matches)

        /// Then
        XCTAssertTrue(delegateMock.didCallAddRows)
        XCTAssertEqual(delegateMock.addRowsIndexPaths, [IndexPath(row: 3, section: 0)])
    }

    func testChangeOperationForSection_whenSetToEqualsAndWasDoesNotExistBefore_shouldAddRowToDataModel() {
        /// Given
        viewModel.addCondition()
        viewModel.addCondition()
        viewModel.addCondition()

        /// When

        /// Expand the picker.
        viewModel.selectRow(at: IndexPath(row: 1, section: 2))

        /// Change the operation mode once.
        viewModel.changeOperationForSection(2, toOperation: .doesNotExist)

        /// Reset the delegate, so that we are able to tell whether `addRows(at:)` was called.
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock

        /// Change the operation mode once more.
        viewModel.changeOperationForSection(2, toOperation: .equals)

        /// Then
        let expectedFourthRow = EditFilterViewModel.Row.textField(placeholder: "Value", value: nil)
        let fourthRow = viewModel.sections[2].rows[3]
        XCTAssertEqual(fourthRow, expectedFourthRow)
    }

    func testChangeOperationForSection_whenSetToMatchesAndWasDoesNotMatchBefore_shouldNotAskDelegateToAddLastCell() {
        /// Given
        viewModel.addCondition()

        /// When

        /// Expand the picker.
        viewModel.selectRow(at: IndexPath(row: 1, section: 0))

        /// Change the operation mode once.
        viewModel.changeOperationForSection(0, toOperation: .doesNotMatch)

        /// Reset the delegate, so that we are able to tell whether `addRows(at:)` was called.
        delegateMock = EditFilterViewModelDelegateMock()
        viewModel.delegate = delegateMock

        /// Change the operation mode once more.
        viewModel.changeOperationForSection(0, toOperation: .matches)

        /// Then
        XCTAssertFalse(delegateMock.didCallAddRows)
    }
}
