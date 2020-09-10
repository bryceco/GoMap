//
//  EditFilterViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 09.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

protocol EditFilterViewModelDelegate: AnyObject {
    /// Asks the delegate to add rows at the given `IndexPath`s.
    /// - Parameter indexPaths: The index paths at which to add row.
    func addRows(at indexPaths: [IndexPath])
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
        let rows: [Row]
    }
    
    enum Row {
        /// Cell with a text field that can be edited.
        case textField(placeholder: String, value: String?)
        
        /// Cell that toggles the picker view.
        case operationPickerToggle(operation: Operation)
        
        /// Cell that contains the picker view that allows the user to select an `Operation`.
        case operationPicker(operation: Operation)
    }
    
    // MARK: Public properties
    
    private(set) var sections = [Section]()
}
