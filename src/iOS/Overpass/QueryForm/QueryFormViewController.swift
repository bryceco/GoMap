//
//  QueryFormViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/6/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import UIKit

class QueryFormViewController: UIViewController {
    
    // MARK: Private properties
    
    @IBOutlet weak var stackViewBottomConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Overpass Query"
    }
    
}
