//
//  DisplayViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 5/6/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

extension DisplayViewController {
    @objc func presentOverpassQueryViewController() {
        let viewController = QueryFormViewController()
        
        navigationController?.pushViewController(viewController, animated: true)
    }
}
