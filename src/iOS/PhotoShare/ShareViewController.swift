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

	var appURL: URL?
	var photoText = ""

	enum ShareResult {
		case openAppWithURL(URL)
		case enableOKButton(String, URL)
		case notFound(String?)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
		popupView.layer.cornerRadius = 10.0
		popupView.layer.masksToBounds = true
		popupView.layer.isOpaque = false
		buttonOK.isEnabled = false
		photoText = popupText.text!
		popupText.text = NSLocalizedString("Processing data...",
		                                   comment: "")
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		Task { @MainActor in
			let result: ShareResult = await processShareItem()
			switch result {
			case let .openAppWithURL(url):
				// immediately jump to location
				self.appURL = url
				self.buttonOK.isEnabled = true
				self.buttonPressOK()
			case let .enableOKButton(text, url):
				// give the user some text, and jump to location when they press OK
				self.appURL = url
				self.popupText.text = text
				self.buttonOK.isEnabled = true
			case let .notFound(text):
				// error message with given text
				if let text {
					popupText.text = text
				} else {
					popupText.text = NSLocalizedString("The URL content isn't recognized.",
					                                   comment: "Error message when sharing a URL to Go Map!!")
				}
			}
		}
	}

	// dummy function so we can get the selector for it, but we'll actually call the
	// instance that exists within UIApplication.
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

	func processShareItem() async -> ShareResult {
		for item in extensionContext?.inputItems ?? [] {
			for provider in (item as? NSExtensionItem)?.attachments ?? [] {
				if provider.hasItemConformingToTypeIdentifier("public.image") {
					// A photo
					if let url = try? await provider.loadItem(forTypeIdentifier: "public.image"),
					   let url = url as? URL,
					   let exif = EXIFInfo(url: url),
					   let url = urlFor(location: (exif.latitude, exif.longitude),
					                    zoom: nil,
					                    direction: exif.direction ?? 0.0)
					{
						return .enableOKButton(self.photoText, url)
					} else {
						var text = self.photoText
						text += "\n\n"
						text += NSLocalizedString(
							"Unfortunately the selected image does not contain location information.",
							comment: "")
						return .notFound(text)
					}
				} else if provider.hasItemConformingToTypeIdentifier("com.apple.mapkit.map-item") {
					// An MKMapItem. There should also be a URL we can use instead.
				} else if provider.hasItemConformingToTypeIdentifier("public.url") {
					guard let urlData = try? await provider.loadItem(forTypeIdentifier: "public.url") else {
						return .notFound(nil)
					}
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
						return .notFound(nil)
					}
					return await commonUrlHandler(for: url)
				} else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
					guard let text = try? await provider.loadItem(forTypeIdentifier: "public.plain-text") else {
						return .notFound(nil)
					}
					if let text = text as? String {
						return await commonPlainTextHandler(for: text)
					} else if let data = text as? Data,
					          let text = String(data: data, encoding: .utf8)
					{
						return await commonPlainTextHandler(for: text)
					} else {
						return .notFound(nil)
					}
				}
			}
		}
		return .notFound(nil)
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

	func commonPlainTextHandler(for text: String) async -> ShareResult {
		guard let url = extractURLs(from: text).first(where: { $0.scheme == "http" || $0.scheme == "https" })
		else {
			return .notFound(nil)
		}
		return await commonUrlHandler(for: url)
	}

	func commonUrlHandler(for url: URL) async -> ShareResult {
		guard let httpResponse = await LocationParser.resolveShortenedURL(url: url),
		      let url = httpResponse.url
		else {
			return .notFound(nil)
		}

		// decode as a location URL
		if let mapLoc = LocationParser.mapLocationFrom(url: url),
		   let url = urlFor(location: (mapLoc.latitude, mapLoc.longitude),
		                    zoom: mapLoc.zoom)
		{
			return .openAppWithURL(url)
		}

		if let mapLoc = await LocationParser.isGoogleMapsRedirectAsync(urlString: url.absoluteString),
		   let url = urlFor(location: (mapLoc.latitude, mapLoc.longitude),
		                    zoom: mapLoc.zoom)
		{
			return .openAppWithURL(url)
		}

		// check if it is a GPX file
		if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String,
		   contentType == "application/gpx+xml",
		   let url = url.absoluteString.data(using: .utf8)?.base64EncodedString(),
		   let appURL = URL(string: "gomaposm://?gpxurl=\(url)")
		{
			// pass the original url to the app which will download it
			return .openAppWithURL(appURL)
		}

		return .notFound(nil)
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

	func urlFor(location: (lat: Double, lon: Double), zoom: Double?, direction: Double = 0.0) -> URL? {
		var string = "gomaposm://?center=\(location.lat),\(location.lon)&direction=\(direction)"
		if let zoom {
			string += "&zoom=\(zoom)"
		}
		return URL(string: string)
	}

	@IBAction func buttonPressOK() {
		if let appURL {
			openApp(withUrl: appURL)
		}
		extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}

	@IBAction func buttonCancel() {
		extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}
}
