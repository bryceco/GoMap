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

func sanitizedURL(_ urlString: String) -> String {
	let sensitiveKeys = ["token", "auth", "api_key", "access_token", "connectid", "signature"]

	guard var components = URLComponents(string: urlString) else { return urlString }
	components.queryItems = components.queryItems?.map { item in
		if sensitiveKeys.contains(item.name.lowercased()) {
			return URLQueryItem(name: item.name, value: "{apikey}")
		} else {
			return item
		}
	}
	return components.url?.absoluteString ?? urlString
}

class UploadViewController: UIViewController, UITextViewDelegate {
	var mapData: OsmMapData!
	@IBOutlet var commentContainerView: UIView!
	@IBOutlet var xmlTextView: UITextView!
	@IBOutlet var commentTextView: UITextView!
	@IBOutlet var sourceTextField: UITextField!
	@IBOutlet var commitButton: UIBarButtonItem!
	@IBOutlet var cancelButton: UIBarButtonItem!
	@IBOutlet var progressView: UIActivityIndicatorView!
	@IBOutlet var exportOscButton: UIButton!
	@IBOutlet var editXmlButton: UIButton!
	@IBOutlet var clearCommentButton: UIButton!
	@IBOutlet var commentHistoryButton: UIButton!
	@IBOutlet var sourceHistoryButton: UIButton!
	@IBOutlet var changesetCommentPlaceholder: UILabel!

	var recentCommentList = MostRecentlyUsed<String>(maxCount: 5,
	                                                 userPrefsKey: UserPrefs.shared.recentCommitComments)
	var recentSourceList = MostRecentlyUsed<String>(maxCount: 5,
	                                                userPrefsKey: UserPrefs.shared.recentSourceComments)

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

		// create button for source history
		sourceHistoryButton = UIButton(type: .custom)
		sourceHistoryButton.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
		sourceHistoryButton.setTitle("🔽", for: .normal)
		sourceHistoryButton.addTarget(self, action: #selector(showSourceHistory), for: .touchUpInside)
		sourceTextField.rightView = sourceHistoryButton
		sourceTextField.rightViewMode = .always

		if #available(iOS 13.0, *) {
			progressView.style = .large
		} else {
			progressView.style = .whiteLarge
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		let mapView = AppDelegate.shared.mapView
		mapData = mapView?.editorLayer.mapData

		commentTextView.text = UserPrefs.shared.uploadComment.value
		sourceTextField.text = UserPrefs.shared.uploadSource.value
		sourceTextField.placeholder = "survey, Bing, knowledge" // overrules translations: see #557
		changesetCommentPlaceholder.isHidden = commentTextView.text.count > 0

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

		exportOscButton.isEnabled = text != nil
		editXmlButton.isEnabled = text != nil

		clearCommentButton.isHidden = true

		commentHistoryButton.isHidden = recentCommentList.count == 0
		sourceTextField.rightViewMode = recentSourceList.count > 0 ? .always : .never
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		UserPrefs.shared.uploadComment.value = commentTextView.text
		UserPrefs.shared.uploadSource.value = sourceTextField.text
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

	private func showHistorySheet(_ list: [String], button: UIButton, textView: UIView) {
		let actionSheet = UIAlertController(
			title: nil,
			message: nil,
			preferredStyle: .actionSheet)
		for message in list {
			actionSheet.addAction(UIAlertAction(title: message, style: .default, handler: { _ in
				if let view = textView as? UITextView {
					view.text = message
					view.resignFirstResponder()
				} else if let view = textView as? UITextField {
					view.text = message
					view.resignFirstResponder()
				}
				self.changesetCommentPlaceholder.isHidden = self.commentTextView.text.count > 0
			}))
		}
		actionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
		                                    style: .cancel,
		                                    handler: nil))
		actionSheet.popoverPresentationController?.sourceView = button
		actionSheet.popoverPresentationController?.sourceRect = button.bounds
		present(actionSheet, animated: true)
	}

	@IBAction func showCommitMessageHistory(_ sender: Any) {
		showHistorySheet(recentCommentList.items, button: commentHistoryButton, textView: commentTextView)
	}

	@IBAction func showSourceHistory(_ sender: Any) {
		showHistorySheet(recentSourceList.items, button: sourceHistoryButton, textView: sourceTextField)
	}

	@IBAction func commit(_ sender: Any?) {
		let appDelegate = AppDelegate.shared
		guard let oAuth = OSM_SERVER.oAuth2,
		      oAuth.isAuthorized()
		else {
			performSegue(withIdentifier: "loginSegue", sender: self)
			return
		}

		guard
			let didPrev = UserPrefs.shared.userDidPreviousUpload.value,
			didPrev
		else {
			let alert = UIAlertController(
				title: NSLocalizedString("Attention", comment: ""),
				message: NSLocalizedString(
					"You are about to make changes to the live OpenStreetMap database. Your changes will be visible to everyone in the world.\n\nTo continue press Commit once again, otherwise press Cancel.",
					comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
			                              style: .cancel,
			                              handler: nil))
			alert.addAction(UIAlertAction(title: NSLocalizedString("Commit", comment: ""),
			                              style: .default,
			                              handler: { [self] _ in
			                              	UserPrefs.shared.userDidPreviousUpload.value = true
			                              	commit(nil)
			                              }))
			present(alert, animated: true)
			return
		}

		progressView.startAnimating()
		commitButton.isEnabled = false
		cancelButton.isEnabled = false
		exportOscButton.isEnabled = false
		editXmlButton.isEnabled = false

		commentTextView.resignFirstResponder()
		xmlTextView.resignFirstResponder()

		var comment = commentTextView.text ?? ""
		comment = comment.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
		if comment != "" {
			recentCommentList.updateWith(comment)
		}

		var source = sourceTextField.text ?? ""
		source = source.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
		if source != "" {
			recentSourceList.updateWith(source)
		}

		let locale = PresetLanguages.preferredLanguageCode()

		let completion: ((Error?) -> Void) = { [self] error in
			progressView.stopAnimating()
			commitButton.isEnabled = true
			cancelButton.isEnabled = true
			if let error = error as? UrlSessionError,
			   case let .badStatusCode(code, _) = error,
			   code == 401
			{
				// authentication error, so redirect to login page
				OSM_SERVER.oAuth2?.removeAuthorization()
				performSegue(withIdentifier: "loginSegue", sender: self)
				return
			} else if let error = error {
				let alert = UIAlertController(
					title: NSLocalizedString("Unable to upload changes", comment: ""),
					message: error.localizedDescription,
					preferredStyle: .alert)
				alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
				                              style: .cancel,
				                              handler: nil))
				present(alert, animated: true)

				if !xmlTextView.isEditable {
					exportOscButton.isEnabled = true
					editXmlButton.isEnabled = true
				}
			} else {
				dismiss(animated: true)

				// flash success message
				MainActor.runAfter(nanoseconds: 300_000000) {
					appDelegate.mapView.editorLayer.setNeedsLayout()
					appDelegate.mapView.flashMessage(title: nil,
					                                 message: NSLocalizedString("Upload complete!", comment: ""),
					                                 duration: 1.5)

					// record number of uploads
					var editCount = UserPrefs.shared.uploadCountPerVersion.value ?? 0
					editCount += 1
					UserPrefs.shared.uploadCountPerVersion.value = editCount
					appDelegate.mapView.ask(toRate: editCount)
				}
			}
		}

		var imagery = ""
		if appDelegate.mapView.viewState == MapViewState.EDITORAERIAL ||
			appDelegate.mapView.viewState == MapViewState.AERIAL
		{
			let server = appDelegate.mapView.aerialLayer.tileServer
			if server.identifier.hasPrefix("http:") || server.identifier.hasPrefix("https:") {
				// custom user imagery
				imagery = sanitizedURL(server.identifier)
			} else {
				imagery = server.name
			}
		}

		if xmlTextView.isEditable {
			// upload user-edited text
			let xmlText = xmlTextView.text ?? ""
			let xmlDoc: DDXMLDocument
			do {
				xmlDoc = try DDXMLDocument(xmlString: xmlText, options: 0)
			} catch {
				completion(error)
				return
			}
			mapData?.openChangesetAndUpload(
				xml: xmlDoc,
				comment: comment,
				source: source,
				imagery: imagery,
				locale: locale,
				completion: completion)
		} else {
			// normal upload
			mapData?.uploadChangeset(withComment: comment,
			                         source: source,
			                         imagery: imagery,
			                         locale: locale,
			                         completion: completion)
		}
	}

	@IBAction func editXml(_ sender: Any) {
		var xml = mapData?.changesetAsXml() ?? ""
		xml = xml + "\n\n\n\n\n\n\n\n\n\n\n\n"
		xmlTextView.attributedText = nil
		xmlTextView.text = xml
		xmlTextView.isEditable = true
		exportOscButton.isEnabled = false
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

	@IBAction func exportOscFile(_ sender: Any) {
		if let xml = mapData?.changesetAsXml(),
		   let text = xml.data(using: .utf8),
		   let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
		   .appendingPathComponent("osmChange.osc"),
		   (try? text.write(to: path, options: .atomicWrite)) != nil
		{
			let objectsToShare = [path] as [Any]
			let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)

			// Excluded activities
			activityVC.excludedActivityTypes = [UIActivity.ActivityType.addToReadingList]

			activityVC.popoverPresentationController?.sourceView = sender as? UIView
			present(activityVC, animated: true, completion: nil)
		}
	}

	func textViewDidChange(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
			changesetCommentPlaceholder.isHidden = commentTextView.text.count > 0
		}
	}

	func textViewDidBeginEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = commentTextView.text.count == 0
			changesetCommentPlaceholder.isHidden = true
		}
	}

	func textViewDidEndEditing(_ textView: UITextView) {
		if textView == commentTextView {
			clearCommentButton.isHidden = true
			changesetCommentPlaceholder.isHidden = commentTextView.text.count > 0
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
		let ident = Int64(name.dropFirst()) ?? 0
		let extendedId: OsmExtendedIdentifier
		switch name.prefix(1) {
		case "n":
			extendedId = OsmExtendedIdentifier(.NODE, ident)
		case "w":
			extendedId = OsmExtendedIdentifier(.WAY, ident)
		case "r":
			extendedId = OsmExtendedIdentifier(.RELATION, ident)
		default:
			return false
		}
		guard let object = appDelegate.mapView.editorLayer.mapData.object(withExtendedIdentifier: extendedId)
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
