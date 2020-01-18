//
//  SettingsViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/16/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation

extension SettingsViewController {
    
    // MARK: UITableViewDataSource
    
    open override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let isLastSection = tableView.numberOfSections == section + 1
        if isLastSection {
            return createVersionDetailsString()
        }
        
        return nil
    }
    
    // MARK: Settings - Show FPS Label
    
    private static let showFPSLabelUserDefaultsKey = "showFPSLabel"
    
    var showFPSLabel: Bool {
        get { return UserDefaults.standard.bool(forKey: Self.showFPSLabelUserDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.showFPSLabelUserDefaultsKey) }
    }
    
    @objc func updateShowFPSLabelSwitchFromUserDefaults() {
        showFPSLabelSwitch.isOn = showFPSLabel
    }
    
    @IBAction func showFPSLabelSwitchDidChangeValue(_ sender: UISwitch) {
        showFPSLabel = sender.isOn
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
    
}
