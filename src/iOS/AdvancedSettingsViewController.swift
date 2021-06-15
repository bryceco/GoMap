//
//  AdvancedSettingsViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class AdvancedSettingsViewController: UITableViewController {
    
    @IBOutlet var hostname: UITextField!
    @IBOutlet var switchFPS: UISwitch!
    @IBOutlet var switchTouches: UISwitch!
    
    private var originalHostname: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.estimatedRowHeight = 44
        self.tableView.rowHeight = UITableView.automaticDimension
    }
    
    @IBAction func textFieldReturn(_ sender: UITextField) {
        sender.resignFirstResponder()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let appDelegate = AppDelegate.shared
        let mapData = appDelegate.mapView.editorLayer.mapData
        self.hostname.text = mapData.getServer()
        self.originalHostname = self.hostname.text
        
        let app = UIApplication.shared as! MyApplication
        self.switchFPS.isOn = appDelegate.mapView.automatedFramerateTestActive
        self.switchTouches.isOn = app.showTouchCircles
	}
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    
        let appDelegate = AppDelegate.shared
        let mapData = appDelegate.mapView.editorLayer.mapData
        if hostname.text != originalHostname {
			// FIXME: need to make this sequence an API
			AppDelegate.shared.mapView.removePin()
			AppDelegate.shared.mapView.editorLayer.selectedNode = nil
			AppDelegate.shared.mapView.editorLayer.selectedWay = nil
			AppDelegate.shared.mapView.editorLayer.selectedRelation = nil
			mapData.setServer( hostname.text! )
		}
    }
    
    @IBAction func switchFPS(_ sender: Any) {
        let toggle = sender as! UISwitch
        let appDelegate = AppDelegate.shared
        appDelegate.mapView.automatedFramerateTestActive = toggle.isOn
    }
    
    @IBAction func switchTouch(_ sender: Any) {
        let toggle = sender as! UISwitch
        let app = UIApplication.shared as! MyApplication
        app.showTouchCircles = toggle.isOn
    }
}
