//
//  PickerViewTableViewCell.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 09.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit

protocol PickerViewTableViewCellDelegate: AnyObject {
    func pickerViewCell(_ pickerViewCell: PickerViewTableViewCell,
                        didSelectOperation operation: EditFilterViewModel.Operation)
}

class PickerViewTableViewCell: UITableViewCell {
    
    @IBOutlet private var pickerView: UIPickerView!
    
    weak var delegate: PickerViewTableViewCellDelegate?
    
    func selectOperation(_ operation: EditFilterViewModel.Operation) {
        guard let row = EditFilterViewModel.Operation.allCases.firstIndex(of: operation) else { return }
        
        pickerView.selectRow(row, inComponent: 0, animated: false)
    }

}

extension PickerViewTableViewCell: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return EditFilterViewModel.Operation.allCases.count
    }
}

extension PickerViewTableViewCell: UIPickerViewDelegate {
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        guard let operation = EditFilterViewModel.Operation(rawValue: row) else { return nil }
        
        return operation.humanReadableString
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard let operation = EditFilterViewModel.Operation(rawValue: row) else { return }
        
        delegate?.pickerViewCell(self, didSelectOperation: operation)
    }
}
