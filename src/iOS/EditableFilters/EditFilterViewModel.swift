//
//  EditFilterViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 09.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

protocol EditFilterViewModelDelegate: AnyObject {
    /// Asks the delegate to add a section at the given index.
    /// - Parameter section: The index at which to add the section.
    func addSection(_ section: Int)
    
    /// Asks the delegate to add rows at the given `IndexPath`s.
    /// - Parameter indexPaths: The index paths at which to add row.
    func addRows(at indexPaths: [IndexPath])
    
    /// Asks the delegate to remove rows at the given `IndexPath`s.
    /// - Parameter indexPaths: The index paths at which to remove rows.
    func removeRows(at indexPaths: [IndexPath])
    
    /// Asks the delegate to show the keyboard and make the `UITextField` in the cell at the given `IndexPath` the first responder.
    /// - Parameter indexPath: The index path for the text field cell that the keyboard should be shown for.
    func showKeyboardForTextFieldCell(at indexPath: IndexPath)
}

final class EditFilterViewModel {
    // MARK: Types
    
    enum Operation: Int, CaseIterable {
        case equals
        case doesNotEqual
        case matches
        case doesNotMatch
        case exists
        case doesNotExist
        
        var humanReadableString: String {
            switch self {
            case .equals:
                return "Equals"
            case .doesNotEqual:
                return "Does not equal"
            case .exists:
                return "Exists"
            case .doesNotExist:
                return "Does not exist"
            case .matches:
                return "Matches"
            case .doesNotMatch:
                return "Does not match"
            }
        }
    }
    
    struct Section {
        var rows: [Row]
    }
    
    enum Row: Equatable {
        /// Cell with a text field that can be edited.
        case textField(placeholder: String, value: String?)
        
        /// Cell that toggles the picker view.
        case operationPickerToggle(operation: Operation)
        
        /// Cell that contains the picker view that allows the user to select an `Operation`.
        case operationPicker(operation: Operation)
    }
    
    // MARK: Public properties
    
    private(set) var sections = [Section]()
    
    weak var delegate: EditFilterViewModelDelegate?
    
    // MARK: Public methods
    
    func addCondition() {
        guard let defaultOperation = Operation.allCases.first else {
            assertionFailure("Failed to determine the default operation for new condition.")
            return
        }
        
        let newSection = Section(rows: [.textField(placeholder: "Key", value: nil),
                                        .operationPickerToggle(operation: defaultOperation),
                                        .textField(placeholder: "Value", value: nil),])
        sections.append(newSection)
        
        let indexOfNewSection = sections.count - 1
        delegate?.addSection(indexOfNewSection)
        
        delegate?.showKeyboardForTextFieldCell(at: IndexPath(row: 0, section: indexOfNewSection))
    }
}
