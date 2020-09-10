//
//  TextFieldTableViewCell.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 09.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit

class TextFieldTableViewCell: UITableViewCell {
    
    @IBOutlet private var textField: UITextField!
    
    func update(placeholder: String, text: String?) {
        textField.placeholder = placeholder
        textField.text = text
    }

}
