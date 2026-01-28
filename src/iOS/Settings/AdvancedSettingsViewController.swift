//
//  AdvancedSettingsViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class AdvancedSettingsViewController: UITableViewController, UIAdaptivePresentationControllerDelegate {
	@IBOutlet var hostname: UITextField!
	@IBOutlet var switchFPS: UISwitch!
	@IBOutlet var switchTouches: UISwitch!
	@IBOutlet var switchMaxFPS: UISwitch!

	private var originalServer: OsmServer?
	var hostnameButton: UIButton!

	override func viewDidLoad() {
		super.viewDidLoad()

		self.presentationController?.delegate = self

		tableView.estimatedRowHeight = 44
		tableView.rowHeight = UITableView.automaticDimension

		// create button for source history
		hostnameButton = UIButton(type: .custom)
		hostnameButton.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
		hostnameButton.setTitle("🔽", for: .normal)
		hostnameButton.addTarget(self, action: #selector(showServersList), for: .touchUpInside)
		hostname.rightView = hostnameButton
		hostname.rightViewMode = .always
	}

	@IBAction func textFieldReturn(_ sender: UITextField) {
		hostname.text = OsmServer.serverNameCanonicalized(hostname.text ?? "")
		sender.resignFirstResponder()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		let appDelegate = AppDelegate.shared
		hostname.text = OSM_SERVER.apiURL.absoluteString
		originalServer = OSM_SERVER

		let app = UIApplication.shared as! MyApplication
		switchFPS.isOn = appDelegate.mainView.fpsLabel.automatedFramerateTestActive
		switchTouches.isOn = app.showTouchCircles

		switchMaxFPS.isOn = UserPrefs.shared.maximizeFrameRate.value ?? false
	}

	func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
		guard
			let server = OsmServer.serverForUrl(string: hostname.text!)
		else {
			// don't dismiss
			return false
		}
		OSM_SERVER = server
		AppDelegate.shared.mapView.unselectAll()
		AppDelegate.shared.mapView.setNeedsLayout()
		return true
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)

		OSM_SERVER = OsmServer.serverForUrl(string: hostname.text!) ?? OsmServerList.first!
		AppDelegate.shared.mapView.unselectAll()
		AppDelegate.shared.mapView.setNeedsLayout()
	}

	@IBAction func switchShowFPS(_ sender: Any) {
		let toggle = sender as! UISwitch
		let appDelegate = AppDelegate.shared
		appDelegate.mainView.fpsLabel.automatedFramerateTestActive = toggle.isOn
	}

	@IBAction func switchShowTouches(_ sender: Any) {
		let toggle = sender as! UISwitch
		let app = UIApplication.shared as! MyApplication
		app.showTouchCircles = toggle.isOn
	}

	@IBAction func switchUseMaxFPS(_ sender: Any) {
		let toggle = sender as! UISwitch
		UserPrefs.shared.maximizeFrameRate.value = toggle.isOn
		DisplayLink.shared.setFrameRate()

		if let mapLibre = AppDelegate.shared.mapLayersView.basemapLayer as? MapLibreVectorTilesView {
			// Call this after updating DisplayLink speed
			mapLibre.setPreferredFrameRate()
		}
	}

	@IBAction func showServersList(_ sender: Any) {
		let actionSheet = UIAlertController(title: nil,
		                                    message: nil,
		                                    preferredStyle: .actionSheet)
		for server in OsmServerList {
			actionSheet.addAction(UIAlertAction(title: server.fullName, style: .default, handler: { _ in
				self.hostname.text = server.apiURL.absoluteString
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
