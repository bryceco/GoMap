//
//  AerialEditViewController.swift
//  Go Map!!
//
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//


class AerialEditViewController: UITableViewController {
    
    @IBOutlet var nameField: UITextField!
    @IBOutlet var urlField: UITextField!
    @IBOutlet var zoomField: UITextField!
    @IBOutlet var projectionField: UITextField!
    var picker =  UIPickerView()

	// these are initialized by the segue manager:
    var name: String?
    var url: String?
    var zoom: Int = 0
    var projection: String?
    var completion: ((_ service: AerialService) -> Void)?
    
    private let TMS_PROJECTION_NAME = "(TMS)"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        nameField.text = name
        urlField.text = url
        zoomField.text = "\(zoom)"
        projectionField.text = projection ?? ""
        picker.delegate = self
        
        picker.reloadAllComponents()
        var row: Int = 0
		if (self.projection?.count ?? 0) == 0 {
            row = 0
        } else {
            if let indexInSupportedProjection = AerialService.supportedProjections.firstIndex(of: projection ?? "") {
                row = indexInSupportedProjection + 1
            }
        }
        
        picker.selectRow(row, inComponent: 0, animated: false)
        
        projectionField.inputView = picker
    }
    
	func isBannedURL(_ url: String) -> Bool {
		// http://www.google.cn/maps/vt?lyrs=s@189&gl=cn&x={x}&y={y}&z={z}
		let regex = ".*\\.google(apis)?\\..*/(vt|kh)[\\?/].*([xyz]=.*){3}.*"
		let range = url.range(of: regex, options: [.regularExpression,.caseInsensitive])
		return range != nil
	}

    
    @IBAction func done(_ sender: Any) {
        // remove white space from subdomain list
        var url = urlField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
        url = url.replacingOccurrences(of: "%7B", with: "{")
        url = url.replacingOccurrences(of: "%7D", with: "}")
        
        if isBannedURL( url ) {
            return
        }
        
        let identifier = url
        
        var projection = projectionField.text ?? ""
		if projection == TMS_PROJECTION_NAME {
			projection = ""
        }
		let maxZoom = Int(zoomField.text ?? "0") ?? 0

		let service = AerialService(
			withName: nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? "",
            identifier: identifier,
            url: url,
			maxZoom: maxZoom,
            roundUp: true,
            startDate: nil,
            endDate: nil,
            wmsProjection: projection,
            polygon: nil,
            attribString: "",
            attribIcon: nil,
            attribUrl: "")
        completion?(service)
        
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func cancel(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func contentChanged(_ sender: Any) {
        var allowed = false
        if (nameField.text?.count ?? 0) > 0 && (urlField.text?.count ?? 0) > 0 {
            if !isBannedURL(urlField.text ?? "") {
                allowed = true
            }
        }
        navigationItem.rightBarButtonItem?.isEnabled = allowed
    }
}

extension AerialEditViewController: UIPickerViewDataSource {
	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}
	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return AerialService.supportedProjections.count + 1
	}
}

extension AerialEditViewController: UIPickerViewDelegate {
	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return row == 0 ? TMS_PROJECTION_NAME : AerialService.supportedProjections[row - 1]
	}
	func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
		projectionField.text = row == 0 ? TMS_PROJECTION_NAME : AerialService.supportedProjections[row - 1]
		contentChanged(projectionField ?? "")
	}
}
