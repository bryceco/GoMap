//
//  ShareViewController.swift
//  PhotoShare
//
//  Created by Bryce Cogswell on 7/19/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Photos
import UIKit

/// This extension allows different types of things to the app:
///	* Sharing a photo jumps to the location defined in the EXIF
///	* Sharing a URL to a GPX loads the GPX
///	* Sharing a URL containing a lat/lon jumps to the location
///	* Sharing an Apple Maps location is the same as a location URL
///	* You cannot share a Google Maps location because it doesn't include lat/lon

/// Duplicated so we can re-use the URL parsing code in LocationParser
enum MapViewState: Int {
	case EDITOR
	case EDITORAERIAL
	case AERIAL
	case MAPNIK
}

/// Duplicated so we can re-use the URL parsing code in LocationParser
struct MapLocation {
	var longitude = 0.0
	var latitude = 0.0
	var zoom = 0.0
	var direction = 0.0
	var viewState: MapViewState? = nil
}

class ShareViewController: UIViewController, URLSessionTaskDelegate {
	@IBOutlet var buttonOK: UIButton!
	@IBOutlet var popupView: UIView!
	@IBOutlet var popupText: UILabel!

	var location: CLLocationCoordinate2D?
	var zoom: Double?
	var direction = 0.0
	var photoText: String!

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
		popupView.layer.cornerRadius = 10.0
		popupView.layer.masksToBounds = true
		popupView.layer.isOpaque = false
		buttonOK.isEnabled = false
		photoText = popupText.text
		popupText.text = NSLocalizedString("Processing data...",
		                                   comment: "")
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		processShareItem()
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

	func setUnrecognizedText() {
		DispatchQueue.main.async {
			self.popupText.text = NSLocalizedString("The URL content isn't recognized.",
			                                        comment: "Error message when sharing a URL to Go Map!!")
		}
	}

	func processShareItem() {
		var found = false
		for item in extensionContext?.inputItems ?? [] {
			for provider in (item as? NSExtensionItem)?.attachments ?? [] {
				if provider.hasItemConformingToTypeIdentifier("public.image") {
					// A photo
					found = true
					provider.loadItem(forTypeIdentifier: "public.image", options: nil) { url, _ in
						if let url = url as? URL,
						   let data = NSData(contentsOf: url as URL),
						   let location = ExifGeolocation.location(forImage: data as Data)
						{
							DispatchQueue.main.async {
								self.location = location.coordinate
								self.zoom = nil
								self.direction = location.course
								self.buttonOK.isEnabled = true
								self.popupText.text = self.photoText
							}
						} else {
							DispatchQueue.main.async {
								var text = self.photoText!
								text += "\n\n"
								text += NSLocalizedString(
									"Unfortunately the selected image does not contain location information.",
									comment: "")
								self.popupText.text = text
							}
						}
					}
				} else if provider.hasItemConformingToTypeIdentifier("com.apple.mapkit.map-item") {
					// An MKMapItem. There should also be a URL we can use instead.
				} else if provider.hasItemConformingToTypeIdentifier("public.url") {
					found = true
					provider.loadItem(forTypeIdentifier: "public.url", options: nil) { urlData, _ in

						// sometimes its a url, other times data containing a url
						let url: URL
						if let url2 = urlData as? URL {
							url = url2
						} else if let data = urlData as? Data,
						          let string = String(data: data, encoding: .utf8),
						          let url2 = URL(string: string)
						{
							url = url2
						} else {
							// error
							self.setUnrecognizedText()
							return
						}

						// decode as a location URL
						if let loc = LocationParser.mapLocationFrom(url: url) {
							DispatchQueue.main.async {
								self.location = CLLocationCoordinate2D(latitude: loc.latitude,
								                                       longitude: loc.longitude)
								self.zoom = loc.zoom
								self.buttonOK.isEnabled = true
								self.buttonPressOK()
							}
							return
						}

						if LocationParser.isGoogleMapsRedirect(url: url, callback: { loc in
							DispatchQueue.main.async {
								guard let loc = loc else {
									self.setUnrecognizedText()
									return
								}
								self.location = CLLocationCoordinate2D(latitude: loc.latitude,
								                                       longitude: loc.longitude)
								self.zoom = loc.zoom
								self.buttonOK.isEnabled = true
								self.buttonPressOK()
							}
						}) {
							return
						}

						// decode as a GPX file
						if true {
							// try downloading the headers for the URL to see if it's "application/gpx+xml"
							let request = NSMutableURLRequest(url: url)
							request.httpMethod = "HEAD"
							let task = URLSession.shared.dataTask(with: request as URLRequest) { _, response, _ in
								if let httpResponse = response as? HTTPURLResponse,
								   let contentType = httpResponse.allHeaderFields["Content-Type"] as? String,
								   contentType == "application/gpx+xml"
								{
									DispatchQueue.main.async {
										// pass the original url to the app which will download it
										let url: String = url.absoluteString.data(using: .utf8)!.base64EncodedString()
										let app = URL(string: "gomaposm://?gpxurl=\(url)")!
										self.openApp(withUrl: app)
										self.extensionContext!.completeRequest(
											returningItems: [],
											completionHandler: nil)
									}
									return
								}
								self.setUnrecognizedText()
							}
							task.resume()
							return
						}
					}
				}
			}
		}
		if !found {
			extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
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
		var string = "gomaposm://?center=\(coord.latitude),\(coord.longitude)&direction=\(direction)"
		if let zoom = zoom {
			string += "&zoom=\(zoom)"
		}
		let app = URL(string: string)!
		openApp(withUrl: app)
		extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
	}

	@IBAction func buttonCancel() {
		extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
	}
}
