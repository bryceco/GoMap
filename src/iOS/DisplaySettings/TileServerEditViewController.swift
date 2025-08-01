//
//  TileServerEditViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import UIKit

class TileServerEditViewController: UITableViewController {
	@IBOutlet var nameField: UITextField!
	@IBOutlet var urlField: UITextField!
	@IBOutlet var zoomField: UITextField!
	@IBOutlet var projectionField: UITextField!
	var picker = UIPickerView()

	// these are initialized by the segue manager:
	var name = ""
	var url = ""
	var zoom = 0
	var projection = ""
	var completion: ((_ service: TileServer) -> Void)?

	private let TMS_PROJECTION_NAME = "(TMS)"

	override func viewDidLoad() {
		super.viewDidLoad()

		nameField.text = name
		urlField.text = url
		zoomField.text = "\(zoom)"
		projectionField.text = projection
		picker.delegate = self

		picker.reloadAllComponents()
		var row = 0
		if projection.count == 0 {
			row = 0
		} else {
			if let indexInSupportedProjection = TileServer.supportedProjections.firstIndex(of: projection) {
				row = indexInSupportedProjection + 1
			}
		}

		picker.selectRow(row, inComponent: 0, animated: false)

		projectionField.inputView = picker
	}

	func trimmedName() -> String {
		return nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
	}

	@IBAction func done(_ sender: Any) {
		// remove white space from subdomain list
		var url = urlField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
		url = url.replacingOccurrences(of: "%7B", with: "{")
		url = url.replacingOccurrences(of: "%7D", with: "}")

		let name = trimmedName()
		if name.isEmpty {
			return
		}

		if OSM_SERVER.isBannedURL(url) {
			return
		}

		let identifier = url

		var projection = projectionField.text ?? ""
		if projection == TMS_PROJECTION_NAME {
			projection = ""
		}
		let maxZoom = Int(zoomField.text ?? "0") ?? 0

		let service = TileServer(
			withName: name,
			identifier: identifier,
			url: url,
			best: false,
			overlay: false,
			apiKey: "",
			maxZoom: maxZoom,
			roundUp: true,
			startDate: nil,
			endDate: nil,
			wmsProjection: projection,
			geoJSON: nil,
			attribString: "",
			attribIconString: nil,
			attribUrl: "",
			isVector: false)
		completion?(service)

		navigationController?.popViewController(animated: true)
	}

	@IBAction func cancel(_ sender: Any) {
		navigationController?.popViewController(animated: true)
	}

	@IBAction func contentChanged(_ sender: Any) {
		var allowed = false
		if !trimmedName().isEmpty,
		   let url = urlField.text,
		   url.count > 0,
		   !OSM_SERVER.isBannedURL(url)
		{
			allowed = true
		}
		navigationItem.rightBarButtonItem?.isEnabled = allowed
	}
}

extension TileServerEditViewController: UIPickerViewDataSource {
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}

	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return TileServer.supportedProjections.count + 1
	}
}

extension TileServerEditViewController: UIPickerViewDelegate {
	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return row == 0 ? TMS_PROJECTION_NAME : TileServer.supportedProjections[row - 1]
	}

	func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		projectionField.text = row == 0 ? TMS_PROJECTION_NAME : TileServer.supportedProjections[row - 1]
		contentChanged(projectionField ?? "")
	}
}
