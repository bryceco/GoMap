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
	var mapData: OsmMapData!
	@IBOutlet var commentContainerView: UIView!
	@IBOutlet var xmlTextView: UITextView!
	@IBOutlet var commentTextView: UITextView!
	@IBOutlet var sourceTextField: UITextField!
	@IBOutlet var commitButton: UIBarButtonItem!
	@IBOutlet var cancelButton: UIBarButtonItem!
	@IBOutlet var progressView: UIActivityIndicatorView!
	@IBOutlet var sendMailButton: UIButton!
	@IBOutlet var editXmlButton: UIButton!
	@IBOutlet var clearCommentButton: UIButton!

	override func viewDidLoad() {
		super.viewDidLoad()

		let color = UIColor.gray.withAlphaComponent(0.5)
		commentContainerView.layer.borderColor = color.cgColor
		commentContainerView.layer.borderWidth = 2.0
		commentContainerView.layer.cornerRadius = 10.0

		sourceTextField.layer.borderColor = color.cgColor
		sourceTextField.layer.borderWidth = 2.0
		sourceTextField.layer.cornerRadius = 10.0

		xmlTextView.layer.borderColor = color.cgColor
		xmlTextView.layer.borderWidth = 2.0
		xmlTextView.layer.cornerRadius = 10.0
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		let mapView = AppDelegate.shared.mapView
		mapData = mapView?.editorLayer.mapData

		let comment = UserDefaults.standard.object(forKey: "uploadComment") as? String
		commentTextView.text = comment

		let source = UserDefaults.standard.object(forKey: "uploadSource") as? String
		sourceTextField.text = source

		let text = mapData?.changesetAsAttributedString()
		if text == nil {
			commitButton.isEnabled = false
			let font = UIFont.preferredFont(forTextStyle: .body)
			xmlTextView.attributedText = NSAttributedString(
				string: NSLocalizedString("Nothing to upload, no changes have been made.", comment: ""),
				attributes: [
					NSAttributedString.Key.font: font
				])
		} else {
			commitButton.isEnabled = true
			xmlTextView.attributedText = text
		}

		sendMailButton.isEnabled = text != nil
		editXmlButton.isEnabled = text != nil

		clearCommentButton.isHidden = true
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		UserDefaults.standard.set(commentTextView.text, forKey: "uploadComment")
		UserDefaults.standard.set(sourceTextField.text, forKey: "uploadSource")
	}

	func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			textView.resignFirstResponder()
			return false
		}
		return true
	}

	@IBAction func clearCommentText(_ sender: Any) {
		commentTextView.text = ""
		clearCommentButton.isHidden = true
	}

	@IBAction func commit(_ sender: Any?) {
		let appDelegate = AppDelegate.shared
		if appDelegate.userName.count == 0 || appDelegate.userPassword.count == 0 {
			performSegue(withIdentifier: "loginSegue", sender: self)
			return
		}

		if !UserDefaults.standard.bool(forKey: "userDidPreviousUpload") {
			let alert = UIAlertController(
				title: NSLocalizedString("Attention", comment: ""),
				message: NSLocalizedString(
					"You are about to make changes to the live OpenStreetMap database. Your changes will be visible to everyone in the world.\n\nTo continue press Commit once again, otherwise press Cancel.",
					comment: ""),
				preferredStyle: .alert)
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("Commit", comment: ""), style: .default,
				                         handler: { [self] _ in
				                         	UserDefaults.standard.set(true, forKey: "userDidPreviousUpload")
				                         	commit(nil)
				                         }))
			present(alert, animated: true)
			return
		}

		progressView.startAnimating()
		commitButton.isEnabled = false
		cancelButton.isEnabled = false
		sendMailButton.isEnabled = false
		editXmlButton.isEnabled = false

		commentTextView.resignFirstResponder()
		xmlTextView.resignFirstResponder()

		var comment = commentTextView.text ?? ""
		comment = comment.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

		var source = sourceTextField.text ?? ""
		source = source.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

		let completion: ((String?) -> Void) = { [self] error in
			progressView.stopAnimating()
			commitButton.isEnabled = true
			cancelButton.isEnabled = true
			if let error = error {
				let alert = UIAlertController(
					title: NSLocalizedString("Unable to upload changes", comment: ""),
					message: error,
					preferredStyle: .alert)
				alert
					.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
				present(alert, animated: true)

				if !xmlTextView.isEditable {
					sendMailButton.isEnabled = true
					editXmlButton.isEnabled = true
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

		var imagery: String = ""
		if appDelegate.mapView.viewState == MapViewState.EDITORAERIAL || appDelegate.mapView.viewState == MapViewState
			.AERIAL
		{
			imagery = appDelegate.mapView.aerialLayer.tileServer.name
		}

		if xmlTextView.isEditable {
			// upload user-edited text
			let xmlText = xmlTextView.text ?? ""
			let xmlDoc: DDXMLDocument
			do {
				xmlDoc = try DDXMLDocument(xmlString: xmlText, options: 0)
			} catch {
				completion(NSLocalizedString("The XML is improperly formed", comment: ""))
				return
			}
			mapData?.uploadChangesetXml(
				xmlDoc,
				comment: comment,
				source: source,
				imagery: imagery,
				completion: completion)
		} else {
			// normal upload
			mapData?.uploadChangeset(withComment: comment, source: source, imagery: imagery, completion: completion)
		}
	}

	@IBAction func editXml(_ sender: Any) {
		var xml = mapData?.changesetAsXml() ?? ""
		xml = xml + "\n\n\n\n\n\n\n\n\n\n\n\n"
		xmlTextView.attributedText = nil
		xmlTextView.text = xml
		xmlTextView.isEditable = true
		sendMailButton.isEnabled = false
		editXmlButton.isEnabled = false

		let alert = UIAlertController(
			title: NSLocalizedString("Edit XML", comment: ""),
			message: NSLocalizedString(
				"Modifying the raw XML data allows you to correct errors that prevent uploading.\n\nIt is an advanced operation that should only be undertaken if you have a thorough understanding of the OSM changeset format.",
				comment: ""),
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

	func mailComposeController(
		_ controller: MFMailComposeViewController,
		didFinishWith result: MFMailComposeResult,
		error: Error?)
	{
		dismiss(animated: true)
	}

	func textViewDidChange(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
		}
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = true
		}
	}

	// this is for navigating from the changeset back to the location of the modified object
	func textView(
		_ textView: UITextView,
		shouldInteractWith url: URL,
		in characterRange: NSRange,
		interaction: UITextItemInteraction) -> Bool
	{
		let appDelegate = AppDelegate.shared
		let name = url.absoluteString
		if name.count == 0 {
			return false
		}
		var ident = Int64((name as NSString).substring(from: 1)) ?? 0
		switch name[name.index(name.startIndex, offsetBy: 0)] {
		case "n":
			ident = OsmExtendedIdentifier(.NODE, ident).rawValue
		case "w":
			ident = OsmExtendedIdentifier(.WAY, ident).rawValue
		case "r":
			ident = OsmExtendedIdentifier(.RELATION, ident).rawValue
		default:
			return false
		}
		guard let object = appDelegate.mapView.editorLayer.mapData.object(withExtendedIdentifier: ident)
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
