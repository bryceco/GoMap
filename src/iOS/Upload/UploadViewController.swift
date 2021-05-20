//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  UploadViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import MessageUI
import QuartzCore
import UIKit

class UploadViewController: UIViewController, UITextViewDelegate, MFMailComposeViewControllerDelegate {
    var mapData: OsmMapData?
    @IBOutlet var _commentContainerView: UIView!
    @IBOutlet var _xmlTextView: UITextView!
    @IBOutlet var _commentTextView: UITextView!
    @IBOutlet var _sourceTextField: UITextField!
    @IBOutlet var _commitButton: UIBarButtonItem!
    @IBOutlet var _cancelButton: UIBarButtonItem!
    @IBOutlet var _progressView: UIActivityIndicatorView!
    @IBOutlet var _sendMailButton: UIButton!
    @IBOutlet var _editXmlButton: UIButton!
    @IBOutlet var _clearCommentButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let color = UIColor.gray.withAlphaComponent(0.5)
        _commentContainerView.layer.borderColor = color.cgColor
        _commentContainerView.layer.borderWidth = 2.0
        _commentContainerView.layer.cornerRadius = 10.0
        
        _sourceTextField.layer.borderColor = color.cgColor
        _sourceTextField.layer.borderWidth = 2.0
        _sourceTextField.layer.cornerRadius = 10.0
        
        _xmlTextView.layer.borderColor = color.cgColor
        _xmlTextView.layer.borderWidth = 2.0
        _xmlTextView.layer.cornerRadius = 10.0
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
		let mapView = AppDelegate.shared.mapView
        mapData = mapView?.editorLayer.mapData
        
        let comment = UserDefaults.standard.object(forKey: "uploadComment") as? String
        _commentTextView.text = comment
        
        let source = UserDefaults.standard.object(forKey: "uploadSource") as? String
        _sourceTextField.text = source
        
        let text = mapData?.changesetAsAttributedString()
        if text == nil {
            _commitButton.isEnabled = false
            let font = UIFont.preferredFont(forTextStyle: .body)
            _xmlTextView.attributedText = NSAttributedString(string: NSLocalizedString("Nothing to upload, no changes have been made.", comment: ""), attributes: [
                NSAttributedString.Key.font: font
            ])
        } else {
            _commitButton.isEnabled = true
            _xmlTextView.attributedText = text
        }
        
        _sendMailButton.isEnabled = text != nil
        _editXmlButton.isEnabled = text != nil
        
        _clearCommentButton.isHidden = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UserDefaults.standard.set(_commentTextView.text, forKey: "uploadComment")
        UserDefaults.standard.set(_sourceTextField.text, forKey: "uploadSource")
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        return true
    }
    
    @IBAction func clearCommentText(_ sender: Any) {
        _commentTextView.text = ""
        _clearCommentButton.isHidden = true
    }
    
    @IBAction func commit(_ sender: Any?) {
		let appDelegate = AppDelegate.shared
		if (appDelegate.userName?.count ?? 0) == 0 || appDelegate.userPassword?.count == 0 {
            performSegue(withIdentifier: "loginSegue", sender: self)
            return
        }
        
        if !UserDefaults.standard.bool(forKey: "userDidPreviousUpload") {
            let alert = UIAlertController(
                title: NSLocalizedString("Attention", comment: ""),
                message: NSLocalizedString("You are about to make changes to the live OpenStreetMap database. Your changes will be visible to everyone in the world.\n\nTo continue press Commit once again, otherwise press Cancel.", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: NSLocalizedString("Commit", comment: ""), style: .default, handler: { [self] action in
                UserDefaults.standard.set(true, forKey: "userDidPreviousUpload")
                commit(nil)
            }))
            present(alert, animated: true)
            return
        }
        
        mapData?.credentialsUserName = appDelegate.userName
        mapData?.credentialsPassword = appDelegate.userPassword
        
        _progressView.startAnimating()
        _commitButton.isEnabled = false
        _cancelButton.isEnabled = false
        _sendMailButton.isEnabled = false
        _editXmlButton.isEnabled = false
        
        _commentTextView.resignFirstResponder()
        _xmlTextView.resignFirstResponder()
        
        var comment = _commentTextView.text
        comment = comment?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        var source = _sourceTextField.text
        source = source?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        let completion: ((String?) -> Void)? = { [self] error in
            _progressView.stopAnimating()
            _commitButton.isEnabled = true
            _cancelButton.isEnabled = true
            if let error = error {
                let alert = UIAlertController(
                    title: NSLocalizedString("Unable to upload changes", comment: ""),
                    message: error,
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
                present(alert, animated: true)
                
                if !_xmlTextView.isEditable {
                    _sendMailButton.isEnabled = true
                    _editXmlButton.isEnabled = true
                }
            } else {
                
                dismiss(animated: true)
                
                // flash success message
                let popTime = DispatchTime.now() + Double(Int64(0.3 * Double(NSEC_PER_SEC)))
                DispatchQueue.main.asyncAfter(deadline: popTime, execute: {
                    appDelegate.mapView.editorLayer.setNeedsLayout()
                    appDelegate.mapView.flashMessage(NSLocalizedString("Upload complete!", comment: ""), duration: 1.5)
                    
                    // record number of uploads
                    let appVersion = appDelegate.appVersion()
					let uploadKey = "uploadCount-\(appVersion)"
                    var editCount = UserDefaults.standard.integer(forKey: uploadKey)
                    editCount += 1
					UserDefaults.standard.set(editCount, forKey: uploadKey)
					appDelegate.mapView.ask(toRate: editCount)
                })
            }
        }
        
        var imagery: String? = nil
        if appDelegate.mapView.viewState == MAPVIEW_EDITORAERIAL || appDelegate.mapView.viewState == MAPVIEW_AERIAL {
            imagery = appDelegate.mapView.aerialLayer.aerialService?.name
        }
        
        if _xmlTextView.isEditable {
            
            // upload user-edited text
            let xmlText = _xmlTextView.text
            var xmlDoc: DDXMLDocument? = nil
            do {
                xmlDoc = try DDXMLDocument(xmlString: xmlText ?? "", options: 0)
            } catch {
                completion?(NSLocalizedString("The XML is improperly formed", comment: ""))
                return
            }
			mapData?.uploadChangesetXml(xmlDoc, comment: comment, source: source, imagery: imagery, completion: completion)
        } else {
            // normal upload
            mapData?.uploadChangeset(withComment: comment, source: source, imagery: imagery, completion: completion)
        }
    }
    
    @IBAction func editXml(_ sender: Any) {
        var xml = mapData?.changesetAsXml()
        xml = (xml ?? "") + "\n\n\n\n\n\n\n\n\n\n\n\n"
        _xmlTextView.attributedText = nil
        _xmlTextView.text = xml
        _xmlTextView.isEditable = true
        _sendMailButton.isEnabled = false
        _editXmlButton.isEnabled = false
        
        let alert = UIAlertController(
            title: NSLocalizedString("Edit XML", comment: ""),
            message: NSLocalizedString("Modifying the raw XML data allows you to correct errors that prevent uploading.\n\nIt is an advanced operation that should only be undertaken if you have a thorough understanding of the OSM changeset format.", comment: ""),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        present(alert, animated: true)
    }
    
    @IBAction func sendMail(_ sender: Any) {
        if MFMailComposeViewController.canSendMail() {
			let appDelegate = AppDelegate.shared

            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            let appName = appDelegate.appName()
            mail.setSubject(String.localizedStringWithFormat(NSLocalizedString("%@ changeset", comment: ""), appName))
			let xml = mapData?.changesetAsXml()
            if let data = xml?.data(using: .utf8) {
                mail.addAttachmentData(data, mimeType: "application/xml", fileName: "osmChange.osc")
            }
            present(mail, animated: true)
        } else {
            let error = UIAlertController(
                title: NSLocalizedString("Cannot compose message", comment: ""),
                message: NSLocalizedString("Mail delivery is not available on this device", comment: ""),
                preferredStyle: .alert)
            error.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
            present(error, animated: true)
        }
    }
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        dismiss(animated: true)
    }
    
    func textViewDidChange(_ textView: UITextView) {
        if textView == _commentTextView {
            _clearCommentButton.isHidden = _commentTextView.text.count == 0
        }
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView == _commentTextView {
            _clearCommentButton.isHidden = _commentTextView.text.count == 0
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView == _commentTextView {
            _clearCommentButton.isHidden = true
        }
    }
    
    // this is for navigating from the changeset back to the location of the modified object
    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        let appDelegate = AppDelegate.shared
        let name = url.absoluteString
        if name.count == 0 {
            return false
        }
        var ident = Int64((name as NSString).substring(from: 1)) ?? 0
        switch name[name.index(name.startIndex, offsetBy: 0)] {
        case "n":
			ident = OsmBaseObject.extendedIdentifierForType( OSM_TYPE._NODE, identifier: ident)
        case "w":
			ident = OsmBaseObject.extendedIdentifierForType( OSM_TYPE._WAY, identifier: ident)
        case "r":
			ident = OsmBaseObject.extendedIdentifierForType( OSM_TYPE._RELATION, identifier: ident)
        default:
            return false
        }
        guard let object = appDelegate.mapView.editorLayer.mapData.object(withExtendedIdentifier: NSNumber(value: ident))
		else { return false }
        appDelegate.mapView.editorLayer.selectedRelation = object.isRelation()
        appDelegate.mapView.editorLayer.selectedWay = object.isWay()
        appDelegate.mapView.editorLayer.selectedNode = object.isNode()
        appDelegate.mapView.placePushpinForSelection()
        cancel(nil)
        return false
    }
    
    @IBAction func cancel(_ sender: Any?) {
        dismiss(animated: true)
    }
}
