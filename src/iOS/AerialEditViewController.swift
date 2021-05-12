//
//  AerialEditViewController.swift
//  Go Map!!
//
//  Created by Ibrahim Hassan on 07/03/21.
//  Copyright © 2021 Bryce. All rights reserved.
//


class AerialEditViewController: UITableViewController {
    
    @IBOutlet var nameField: UITextField!
    @IBOutlet var urlField: UITextField!
    @IBOutlet var zoomField: UITextField!
    @IBOutlet var projectionField: UITextField!
    var picker =  UIPickerView()
    var projectionList: [String]?
    
    var name: String?
    var url: String?
    var zoom: NSNumber?
    var projection: String?
    var completion: ((_ service: AerialService?) -> Void)?
    
    private let TMS_PROJECTION_NAME = "(TMS)"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        nameField.text = name
        urlField.text = url
        zoomField.text = "\(zoom ?? 0)"
        projectionField.text = projection
        picker.delegate = self
        
        picker.reloadAllComponents()
        var row: Int = 0
        if self.projection?.count == 0 {
            row = 0
        } else {
            if let indexInSupportedProjection = AerialService.supportedProjections.firstIndex(of: projection ?? "") {
                row = indexInSupportedProjection + 1
            }
        }
        
        picker.selectRow(row, inComponent: 0, animated: false)
        
        projectionField.inputView = picker
    }
    
    func isBannedURL(_ url: String?) -> Bool {
        let pattern = ".*\\.google(apis)?\\..*/(vt|kh)[\\?/].*([xyz]=.*){3}.*"
        var regex: NSRegularExpression? = nil
        do {
            regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
        }
        let range = regex?.rangeOfFirstMatch(in: url ?? "", options: [], range: NSRange(location: 0, length: url?.count ?? 0))
        if range?.location != NSNotFound {
            return true
        }
        return false
    }
    
    @IBAction func done(_ sender: Any) {
        // remove white space from subdomain list
        var url = urlField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        url = url?.replacingOccurrences(of: "%7B", with: "{")
        url = url?.replacingOccurrences(of: "%7D", with: "}")
        
        if isBannedURL(urlField.text) {
            return
        }
        
        let identifier = url
        
        var projection = projectionField.text
        if projection?.count == 0 || (projection == TMS_PROJECTION_NAME) {
            projection = ""
        }
        
        let service = AerialService.aerial(
            withName: nameField.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            identifier: identifier,
            url: url,
            maxZoom: zoomField.text?.intValue ?? 0,
            roundUp: true,
            startDate: nil,
            endDate: nil,
            wmsProjection: projection,
            polygon: nil,
            attribString: nil,
            attribIcon: nil,
            attribUrl: nil)
        completion?(service)
        
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func cancel(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func contentChanged(_ sender: Any) {
        var allowed = false
        if (nameField.text?.count ?? 0) > 0 && (urlField.text?.count ?? 0) > 0 {
            if !isBannedURL(urlField.text) {
                allowed = true
            }
        }
        navigationItem.rightBarButtonItem?.isEnabled = allowed
    }
    


}

extension AerialEditViewController: UIPickerViewDataSource {
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        AerialService.supportedProjections.count + 1
    }
}

extension AerialEditViewController: UIPickerViewDelegate {
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        row == 0 ? TMS_PROJECTION_NAME : AerialService.supportedProjections[row - 1]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        projectionField.text = row == 0 ? TMS_PROJECTION_NAME : AerialService.supportedProjections[row - 1]
        contentChanged(projectionField ?? "")
    }
}

//TODO: Move to another file sometime later
//https://stackoverflow.com/a/55763210/
extension String {
    //Converts String to Int
    var intValue: Int? {
        if let num = NumberFormatter().number(from: self) {
            return num.intValue
        } else {
            return nil
        }
    }
    
    //    //Converts String to Double
    //    public func toDouble() -> Double? {
    //        if let num = NumberFormatter().number(from: self) {
    //            return num.doubleValue
    //        } else {
    //            return nil
    //        }
    //    }
    //
    //    /// EZSE: Converts String to Float
    //    public func toFloat() -> Float? {
    //        if let num = NumberFormatter().number(from: self) {
    //            return num.floatValue
    //        } else {
    //            return nil
    //        }
    //    }
    //
    //    //Converts String to Bool
    //    public func toBool() -> Bool? {
    //        return (self as NSString).boolValue
    //    }
}
