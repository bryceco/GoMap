//
//  ShareViewController.swift
//  PhotoShare
//
//  Created by Bryce Cogswell on 7/19/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import UIKit
import Photos

class ShareViewController: UIViewController {

	@IBOutlet var buttonOK: UIButton!
	@IBOutlet var popupView: UIView!
	@IBOutlet var popupText: UILabel!

	var location: CLLocationCoordinate2D? = nil

	override func viewDidLoad() {
		super.viewDidLoad()
		self.popupView.layer.cornerRadius = 10.0
		self.popupView.layer.masksToBounds = true
		self.popupView.layer.isOpaque = false
		self.buttonOK.isEnabled = false
		getLocation()
	}

	@objc func openURL(_ url: URL) {
		return
	}

	func getLocation() {
		if let item = extensionContext?.inputItems.first as? NSExtensionItem,
		   let attachments = item.attachments
		{
			for provider in attachments {
				if provider.hasItemConformingToTypeIdentifier("public.image") {
					provider.loadItem(forTypeIdentifier: "public.image", options: nil) { (url, error) in
						if let url = url as? URL,
							let data = NSData(contentsOf: url as URL),
							let location = ExifGeolocation.location(forImage: data as Data)
						{
							self.location = location.coordinate
							self.buttonOK.isEnabled = true
						} else {
							var text = self.popupText.text!
							text += "\n\n"
							text += NSLocalizedString("Unfortunately the selected image does not contain location information.", comment: "")
							self.popupText.text = text
						}
					}
				}
			}
		}
	}

	func openApp(withUrl url: URL) {
		let selector = #selector(openURL(_:))
		var responder: UIResponder? = self as UIResponder
		while responder != nil {
			if responder!.responds(to: selector) && responder != self {
				responder!.perform(selector, with: url)
				return
			}
			responder = responder?.next
		}
	}

	@IBAction func buttonPressOK() {
		guard let coord = location else { return }
		let app = URL(string: "gomaposm://?center=\(coord.latitude),\(coord.longitude)")!
		self.openApp(withUrl: app)
		self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
	}

	@IBAction func buttonCancel() {
		let error = NSError()
		self.extensionContext!.cancelRequest(withError: error)
	}
}
