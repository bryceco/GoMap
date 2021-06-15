//
//  POIPresetValuePickerController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class POIPresetValuePickerController: UITableViewController {
    
    var tag = ""
    var valueDefinitions: [PresetValue]?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.rowHeight = UITableView.automaticDimension
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        valueDefinitions?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell?
        let preset = valueDefinitions?[indexPath.row]

        if preset?.details != nil {
            cell = tableView.dequeueReusableCell(withIdentifier: "SubtitleCell", for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "BasicCell", for: indexPath)
        }

        if preset?.name != nil {
            cell?.textLabel?.text = preset?.name
            cell?.detailTextLabel?.text = preset?.details
        } else {
            var text = preset?.tagValue.replacingOccurrences(of: "_", with: " ")
            text = text?.capitalized
            cell?.textLabel?.text = text
            cell?.detailTextLabel?.text = nil
        }

        let tabController = tabBarController as? POITabBarController
        let selected = tabController?.keyValueDict[tag] == preset?.tagValue
        cell?.accessoryType = selected ? .checkmark : .none

        return cell!
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let preset = valueDefinitions?[indexPath.row]
        let tab = tabBarController as? POITabBarController
        tab?.keyValueDict[tag] = preset?.tagValue

        navigationController?.popViewController(animated: true)
    }
}
