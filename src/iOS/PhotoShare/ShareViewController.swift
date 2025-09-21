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
	case BASEMAP
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
				if found {
					break
				}
				if provider.hasItemConformingToTypeIdentifier("public.image") {
					// A photo
					found = true
					provider.loadItem(forTypeIdentifier: "public.image", options: nil) { url, _ in
						if let url = url as? URL,
						   let exif = EXIFInfo(url: url)
						{
							DispatchQueue.main.async {
								self.location = CLLocationCoordinate2D(latitude: exif.latitude,
								                                       longitude: exif.longitude)
								self.zoom = nil
								self.direction = exif.direction ?? 0.0
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
				} else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
					found = true
					provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { text, _ in
						if let text = text as? String {
							self.commonPlainTextHandler(for: text)
						} else if let data = text as? Data,
						          let text = String(data: data, encoding: .utf8)
						{
							self.commonPlainTextHandler(for: text)
						} else {
							self.setUnrecognizedText()
						}
					}
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
						self.commonUrlHandler(for: url)
					}
				}
			}
		}
		if !found {
			buttonCancel()
		}
	}

	func extractURLs(from text: String) -> [URL] {
		let types: NSTextCheckingResult.CheckingType = .link
		guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }

		let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
		return matches.compactMap { match in
			guard let range = Range(match.range, in: text) else { return nil }
			return URL(string: String(text[range]))
		}
	}

	func commonPlainTextHandler(for text: String) {
		guard let url = extractURLs(from: text).first(where: { $0.scheme == "http" || $0.scheme == "https" })
		else {
			setUnrecognizedText()
			return
		}
		commonUrlHandler(for: url)
	}

	func commonUrlHandler(for url: URL) {
		Task {
			guard let httpResponse = await LocationParser.resolveShortenedURL(url: url),
			      let url = httpResponse.url
			else {
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

			if LocationParser.isGoogleMapsRedirect(urlString: url.absoluteString, callback: { loc in
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

			// check if it is a GPX file
			if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String,
			   contentType == "application/gpx+xml"
			{
				DispatchQueue.main.async {
					// pass the original url to the app which will download it
					let url: String = url.absoluteString.data(using: .utf8)!
						.base64EncodedString()
					let app = URL(string: "gomaposm://?gpxurl=\(url)")!
					self.openApp(withUrl: app)
					self.extensionContext!.completeRequest(
						returningItems: [],
						completionHandler: nil)
				}
				return
			}

			// not recognized
			self.setUnrecognizedText()
		}
	}

	@objc @discardableResult private func openApp(withUrl url: URL) -> Bool {
		var responder: UIResponder? = self
		while responder != nil {
			if let application = responder as? UIApplication {
				if #available(iOS 18.0, *) {
					application.open(url, options: [:], completionHandler: nil)
					return true
				} else {
					return application.perform(#selector(openURL(_:)), with: url) != nil
				}
			}
			responder = responder?.next
		}
		return false
	}

	@IBAction func buttonPressOK() {
		if let coord = location {
			var string = "gomaposm://?center=\(coord.latitude),\(coord.longitude)&direction=\(direction)"
			if let zoom = zoom {
				string += "&zoom=\(zoom)"
			}
			let openURL = URL(string: string)!
			openApp(withUrl: openURL)
		}
		extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}

	@IBAction func buttonCancel() {
		extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}
}
