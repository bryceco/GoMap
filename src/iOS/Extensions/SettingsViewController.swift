//
//  SettingsViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/16/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

extension SettingsViewController {
    
    open override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let isLastSection = tableView.numberOfSections == section + 1
        if isLastSection {
            return createVersionDetailsString()
        }
        
        return nil
    }
    
    // MARK: Private methods
    
    private func createVersionDetailsString() -> String? {
        guard
            let appDelegate = UIApplication.shared.delegate as? AppDelegate,
            let appName = appDelegate.appName(),
            let appVersion = appDelegate.appVersion(),
            let appBuildNumber = appDelegate.appBuildNumber()
        else {
            assertionFailure("Unable to determine the app version details")
            return nil
        }
        
        return "\(appName) \(appVersion) (\(appBuildNumber))"
    }
    
    @objc func openTestFlightURL() {
        guard let url = URL(string: "https://testflight.apple.com/join/T96F9wYq") else { return }
        
        UIApplication.shared.openURL(url)
    }
    
}
