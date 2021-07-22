//
//  ShareViewController.swift
//  PhotoShare
//
//  Created by Bryce Cogswell on 7/19/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

import Photos
import UIKit

class ShareViewController: UIViewController, URLSessionTaskDelegate {
	@IBOutlet var buttonOK: UIButton!
	@IBOutlet var popupView: UIView!
	@IBOutlet var popupText: UILabel!

	var location: CLLocationCoordinate2D?

	override func viewDidLoad() {
		super.viewDidLoad()
		popupView.layer.cornerRadius = 10.0
		popupView.layer.masksToBounds = true
		popupView.layer.isOpaque = false
		buttonOK.isEnabled = false
		getLocation()
	}

	@objc func openURL(_ url: URL) {}

	// intercept redirect when dealing with google maps
	func urlSession(_ session: URLSession,
					task: URLSessionTask,
					willPerformHTTPRedirection response: HTTPURLResponse,
					newRequest request: URLRequest,
					completionHandler: (URLRequest?) -> Void)
	{
		completionHandler(nil)
	}

	func getLocation() {
		if let item = extensionContext?.inputItems.first as? NSExtensionItem,
		   let attachments = item.attachments
		{
			var found = false
			for provider in attachments {
				if provider.hasItemConformingToTypeIdentifier("public.image") {
					found = true
					provider.loadItem(forTypeIdentifier: "public.image", options: nil) { url, _ in
						if let url = url as? URL,
						   let data = NSData(contentsOf: url as URL),
						   let location = ExifGeolocation.location(forImage: data as Data)
						{
							DispatchQueue.main.async {
								self.location = location.coordinate
								self.buttonOK.isEnabled = true
							}
						} else {
							var text = self.popupText.text!
							text += "\n\n"
							text += NSLocalizedString(
								"Unfortunately the selected image does not contain location information.",
								comment: "")
							DispatchQueue.main.async {
								self.popupText.text = text
							}
						}
					}
				} else if provider.hasItemConformingToTypeIdentifier("com.apple.mapkit.map-item") {
					// an MKMapItem
				} else if provider.hasItemConformingToTypeIdentifier("public.url") {
					found = true
					provider.loadItem(forTypeIdentifier: "public.url", options: nil) { url, error in
						// decode as apple maps
						if let url = url as? URL,
							let comps = URLComponents(url: url, resolvingAgainstBaseURL: true),
							comps.host == "maps.apple.com",
							let item = comps.queryItems?.first(where: { $0.name == "ll" }),
							let latLon = item.value
						{
							let scanner = Scanner(string: latLon)
							var lat = 0.0, lon = 0.0
							if scanner.scanDouble(&lat),
							   scanner.scanString(",", into:nil),
							   scanner.scanDouble(&lon)
							{
								DispatchQueue.main.async {
									self.location = CLLocationCoordinate2D(latitude: lat, longitude: lon)
									self.buttonOK.isEnabled = true
									self.buttonPressOK()
								}
								return
							}
						}

						#if false
						// decode as google maps
						if let url = url as? URL,
							let comps = URLComponents(url: url, resolvingAgainstBaseURL: true),
							comps.host == "goo.gl"
						{
							// need to get the redirect to find the actual location
							let configuration = URLSessionConfiguration.default
							let session = URLSession(configuration: configuration,
													 delegate: self,
													 delegateQueue: nil)
							let task = session.dataTask(with: url)
							task.resume()
						}
						#endif

						// error
						DispatchQueue.main.async {
							self.popupText.text = NSLocalizedString("The shared content does not contain a location.",
																	comment: "Error message when sharing a map location from Apple Maps to Go Map!!")
						}
					}
				}
			}
			if !found {
				extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
			}
		}
	}

	func openApp(withUrl url: URL) {
		let selector = #selector(openURL(_:))
		var responder: UIResponder? = self as UIResponder
		while responder != nil {
			if responder!.responds(to: selector),
			   responder != self
			{
				responder!.perform(selector, with: url)
				return
			}
			responder = responder?.next
		}
	}

	@IBAction func buttonPressOK() {
		guard let coord = location else { return }
		let app = URL(string: "gomaposm://?center=\(coord.latitude),\(coord.longitude)")!
		openApp(withUrl: app)
		extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
	}

	@IBAction func buttonCancel() {
		let error = NSError()
		extensionContext!.cancelRequest(withError: error)
	}
}
