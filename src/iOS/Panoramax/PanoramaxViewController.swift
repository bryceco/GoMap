//
//  PanoramaxViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/25/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import UIKit
@preconcurrency import WebKit

protocol PanoramaxDelegate: AnyObject {
	// Callback allowing the caller to assign the photoID of the uploaded image to
	// the OSM object's "panoramax" tag.
	func panoramaxUpdate(photoID: String)
}

// This is just a container for a WKWebView that we use when opening the Panoramax website.
// Using WKWebView allows us to share our cookies so the user doesn't need to authenticate
// to it separately.
class PanoramaxWebViewController: UIViewController, WKNavigationDelegate {
	@IBOutlet var webView: WKWebView!

	var panoramax: PanoramaxServer!
	var url: URL?

	class func create() -> PanoramaxWebViewController {
		let sb = UIStoryboard(name: "Panoramax", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "PanoramaxWebViewController")
		return vc as! Self
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		webView.navigationDelegate = self

		var request = URLRequest(url: url!)
		request.setUserAgent()
		webView.load(request)
	}

	// Delegate function
	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void)
	{
		// Don't know why this is necessary, but WebKit doesn't call our URI
		// for us the way SFSafariViewController does. So intercept the URL
		// and call our function directly:
		if let url = navigationAction.request.url,
		   url.absoluteString == PanoramaxServer.redirect_uri
		{
			panoramax.authRedirectHandler(url: url, options: [:])
			decisionHandler(.cancel)
			return
		}
		decisionHandler(.allow)
	}

	@IBAction
	func close() {
		dismiss(animated: true)
	}

	@IBAction
	func openSafari() {
		guard let url = webView.url,
		      UIApplication.shared.canOpenURL(url)
		else {
			return
		}
		UIApplication.shared.open(url, options: [:], completionHandler: nil)
	}
}

class PanoramaxViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	var panoramax: PanoramaxServer!
	var photoID = "" // Provided by caller if there's a pre-existing panoramax photo to display
	var tags: [String: String] = [:] // Provided by caller to specify tags to upload with new photos
	var delegate: PanoramaxDelegate?
	var location: LatLon = .zero
	let locationManager = CLLocationManager()

	@IBOutlet var photoView: UIImageView!
	@IBOutlet var photoUser: UILabel!
	@IBOutlet var photoDate: UILabel!
	@IBOutlet var websiteButton: UIButton!
	@IBOutlet var captureButton: UIButton!
	var progress: UIActivityIndicatorView!

	class func create() -> PanoramaxViewController {
		let sb = UIStoryboard(name: "Panoramax", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "Panoramax")
		return vc as! Self
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		photoView.layer.borderColor = UIColor.black.cgColor
		photoView.layer.borderWidth = 2.0
		photoView.layer.cornerRadius = 5.0
		photoView.layer.masksToBounds = true

		websiteButton.layer.borderWidth = 1.0
		websiteButton.layer.borderColor = UIColor.black.cgColor
		websiteButton.layer.cornerRadius = 5.0
		websiteButton.setTitle("", for: .normal)

		captureButton.setTitle("", for: .normal)
		let tintedImage = captureButton.image(for: .normal)!.withRenderingMode(.alwaysTemplate)
		captureButton.setImage(tintedImage, for: .normal)
		captureButton.tintColor = .systemBlue

		// create progress indicator
		if #available(iOS 13.0, *) {
			progress = UIActivityIndicatorView(style: .large)
		} else {
			progress = UIActivityIndicatorView(style: .gray)
		}
		view.addSubview(progress)
		progress.color = .blue
		progress.center = view.center

		photoUser.text = ""
		photoDate.text = ""
		if !photoID.isEmpty {
			fetchPhotoAndMetadata()
		}

		// start location services in case user takes a photo
		locationManager.startUpdatingLocation()
		locationManager.startUpdatingHeading()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Configure the preview image
		let size = photoView.bounds.height
		let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
		let photo = UIImage(systemName: "photo", withConfiguration: config)!
			.withRenderingMode(.alwaysTemplate)
		photoView.image = photo
		photoView.tintColor = .systemBlue
	}

	@IBAction
	func done(_ sender: Any) {
		dismiss(animated: true)
	}

	@IBAction
	func openPanoramaxWebsite(_ sender: Any) {
		// We use WKWebview instead of SFSafariViewController so that we
		// can share the authentication cookie with it.
		let webVC = PanoramaxWebViewController.create()
		webVC.modalTransitionStyle = .coverVertical
		webVC.panoramax = panoramax
		webVC.url = panoramax.serverURL
		present(webVC, animated: true)
	}

	var photoPicker: PhotoCapture!

	@IBAction
	func captureAndUploadPhotograph(_ sender: Any) {
		_ = [
			// leaving these here for future use, since translators already translated them
			NSLocalizedString("Take New Photo", comment: ""),
			NSLocalizedString("Choose Existing Photo",
			                  comment: "Text displayed in an action sheet when the user wants to upload a photograph from their photo library.")
		]
		photoPicker = PhotoCapture()
		photoPicker.locationManager = locationManager
		photoPicker.onCancel = {}
		photoPicker.onError = {}
		photoPicker.onAccept = { image, imageData in
			Task {
				try await self.uploadImage(image: image, imageData: imageData)
			}
		}
		photoPicker.modalPresentationStyle = .fullScreen
		present(photoPicker, animated: true)
	}

	// UIImagePickerController delegate function
	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		picker.dismiss(animated: true)
	}

	// UIImagePickerController delegate function
	func imagePickerController(_ picker: UIImagePickerController,
	                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
	{
		picker.dismiss(animated: true)

		guard let image = info[.originalImage] as? UIImage,
		      let imageURL = info[.imageURL] as? URL,
		      let imageData = try? Data(contentsOf: imageURL)
		else {
			return
		}
		Task {
			try await uploadImage(image: image, imageData: imageData)
		}
	}

	@MainActor
	func uploadImage(image: UIImage, imageData: Data) async throws {
		// get date and name
		let date = Date()
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		let name = formatter.string(from: date) + ".jpg"

		// Run upload in a detached task so the UI isn't blocked. Semantic tag
		// upload is handled by the server's background queue after this returns.
		Task {
			progress.startAnimating()
			captureButton.isEnabled = false
			defer {
				self.progress.stopAnimating()
				self.progress.isHidden = true
				self.captureButton.isEnabled = true
			}
			do {
				let photoID: String
				do {
					photoID = try await panoramax.uploadAndEnqueue(imageData: imageData,
					                                               name: name,
					                                               date: date,
					                                               tags: tags)
				} catch {
					if case let .badStatusCode(code, _) = error as? UrlSessionError,
					   code == 401
					{
						try await self.panoramax.authorizeUser(withVC: self)
						// try again
						// Without the pause the server doesn't always accept our cookie
						try await Task.sleep(nanoseconds: 100_000000)
						try await self.uploadImage(image: image, imageData: imageData)
						return
					}
					throw error
				}
				self.photoID = photoID
				self.photoView.image = image
				self.photoDate.text = Self.formattedTimestamp(date: date)
				self.photoUser.text = AppDelegate.shared.userName
				self.delegate?.panoramaxUpdate(photoID: photoID)
			} catch {
				self.showError(error)
			}
		}
	}

	func fetchPhotoAndMetadata() {
		progress.startAnimating()

		let url1Photo = URL(string: "https://api.panoramax.xyz/api/pictures/\(photoID)/sd.jpg")!
		let url2Photo = panoramax.serverURL.appendingPathComponent("api/pictures/\(photoID)/sd.jpg")

		let url1Meta = URL(string: "https://api.panoramax.xyz/api/search?ids=\(photoID)")!
		let url2Meta = URL(string: panoramax.serverURL.absoluteString + "/api/search?ids=\(photoID)")!

		Task {
			async let photoTask: Void = {
				let data = (try? Data(contentsOf: url1Photo)) ?? (try? Data(contentsOf: url2Photo))
				await MainActor.run {
					if let data {
						self.photoView.image = UIImage(data: data)
					}
				}
			}()

			async let metaTask: Void = {
				var meta = try? await self.fetchUserMetadata(url: url1Meta)
				if meta == nil {
					meta = try? await self.fetchUserMetadata(url: url2Meta)
				}
				if let meta {
					await MainActor.run {
						self.photoUser.text = meta.name ?? ""
						self.photoDate.text = meta.date ?? ""
					}
				} else {
					await MainActor.run {
						self.photoUser.text = NSLocalizedString("Photo not available",
						                                        comment: "")
					}
				}
			}()

			// Wait for both tasks to finish
			_ = await(photoTask, metaTask)

			await MainActor.run {
				self.progress.stopAnimating()
				self.progress.isHidden = true
			}
		}
	}

	func fetchUserMetadata(url: URL) async throws -> (name: String?, date: String?)? {
		// Lots more metadata is present, but this is all we need:
		struct Welcome: Decodable {
			let features: [Feature]
		}
		struct Feature: Decodable {
			let providers: [Provider]
			let properties: Properties
		}
		struct Properties: Decodable {
			let created: String
			let datetime: String
		}
		struct Provider: Decodable {
			let name: String
		}
		let data = try Data(contentsOf: url)
		let welcome = try JSONDecoder().decode(Welcome.self, from: data)
		let metaName = welcome.features.first?.providers.first?.name
		let metaDate: String?
		if let date = welcome.features.first?.properties.datetime,
		   let date = ISO8601DateFormatter().date(from: date)
		{
			metaDate = Self.formattedTimestamp(date: date)
		} else {
			metaDate = nil
		}
		guard metaName != nil || metaDate != nil else { return nil }
		return (metaName, metaDate)
	}

	@MainActor
	func showError(_ error: Error) {
		let alertError = UIAlertController(title: "Error",
		                                   message: error.localizedDescription,
		                                   preferredStyle: .alert)
		alertError.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
		                                   style: .cancel, handler: nil))
		present(alertError, animated: true)
	}

	@MainActor
	private class func formattedTimestamp(date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
		formatter.timeZone = TimeZone.current
		let text = formatter.string(from: date)
		return text
	}

	private func lighten(image: UIImage) -> UIImage? {
		let context = CIContext(options: nil)
		guard let currentFilter = CIFilter(name: "CIColorControls") else { return nil }
		let beginImage = CIImage(image: image)
		currentFilter.setValue(beginImage, forKey: kCIInputImageKey)
		currentFilter.setValue(0.5, forKey: kCIInputBrightnessKey) // Adjust brightness to make the image lighter
		currentFilter.setValue(0.0, forKey: kCIInputSaturationKey) // Ensure the image stays grayscale
		guard let outputImage = currentFilter.outputImage,
		      let cgimg = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
		return UIImage(cgImage: cgimg)
	}

	func printCookies() {
		print("\n")
		for cookie in HTTPCookieStorage.shared.cookies ?? [] {
			guard cookie.name == "session" else { continue }
			print("Cookie Name: \(cookie.name)")
			print("Cookie Value: \(cookie.value)")
			print("Cookie Domain: \(cookie.domain)")
			print("Cookie Path: \(cookie.path)")
			print("Cookie Expires: \(cookie.expiresDate?.description ?? "Session Cookie")")
			print("------------")
		}
	}
}
