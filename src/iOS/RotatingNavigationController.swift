//
//  RotatingNavigationController.swift
//  Go Map!!
//
//  Created by Ibrahim Hassan on 17/03/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

class RotatingNavigationController: UINavigationController {
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
}
