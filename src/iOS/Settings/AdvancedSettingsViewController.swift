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
	var hostnameButton: UIButton!

	override func viewDidLoad() {
		super.viewDidLoad()

		tableView.estimatedRowHeight = 44
		tableView.rowHeight = UITableView.automaticDimension

		// create button for source history
		hostnameButton = UIButton(type: .custom)
		hostnameButton.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
		hostnameButton.setTitle("🔽", for: .normal)
		hostnameButton.addTarget(self, action: #selector(showSourceHistory), for: .touchUpInside)
		hostname.rightView = hostnameButton
		hostname.rightViewMode = .always
	}

	@IBAction func textFieldReturn(_ sender: UITextField) {
		let mapData = AppDelegate.shared.mapView.editorLayer.mapData
		hostname.text = mapData.serverNameCanonicalized(hostname.text ?? "")

		sender.resignFirstResponder()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		let appDelegate = AppDelegate.shared
		let mapData = appDelegate.mapView.editorLayer.mapData
		hostname.text = mapData.getServer()
		originalHostname = hostname.text

		let app = UIApplication.shared as! MyApplication
		switchFPS.isOn = appDelegate.mapView.automatedFramerateTestActive
		switchTouches.isOn = app.showTouchCircles
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		let appDelegate = AppDelegate.shared
		let mapData = appDelegate.mapView.editorLayer.mapData
		if hostname.text != originalHostname {
			// FIXME: need to make this sequence an API
			appDelegate.mapView.removePin()
			appDelegate.mapView.editorLayer.selectedNode = nil
			appDelegate.mapView.editorLayer.selectedWay = nil
			appDelegate.mapView.editorLayer.selectedRelation = nil
			mapData.setServer(hostname.text!)
			appDelegate.mapView.editorLayer.setNeedsLayout()
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

	@IBAction func showSourceHistory(_ sender: Any) {
		let actionSheet = UIAlertController(
			title: nil,
			message: nil,
			preferredStyle: .actionSheet)
		for server in OsmServerList {
			actionSheet.addAction(UIAlertAction(title: server.fullName, style: .default, handler: { _ in
				self.hostname.text = server.apiURL
				self.textFieldReturn(self.hostname)
			}))
		}
		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
		                                    style: .cancel,
		                                    handler: nil))
		actionSheet.popoverPresentationController?.sourceView = hostnameButton
		actionSheet.popoverPresentationController?.sourceRect = hostnameButton.bounds
		present(actionSheet, animated: true)
	}
}
