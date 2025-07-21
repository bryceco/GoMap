//
//  PhotoCapture.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/21/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import Foundation
import UIKit

private func dataFor(image: UIImage, location: CLLocation?, heading: CLHeading?) -> Data? {
	guard let imageData = image.jpegData(compressionQuality: 0.9),
	      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
	      let imageType = CGImageSourceGetType(source),
	      let metadataOrig = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
	else {
		return nil
	}

	var gpsDict: [String: Any] = [:]

	// Inject location values
	if let loc = location {
		let timeFormatter = DateFormatter()
		timeFormatter.timeZone = TimeZone(abbreviation: "UTC")
		timeFormatter.dateFormat = "HH:mm:ss"

		let dateFormatter = DateFormatter()
		dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
		dateFormatter.dateFormat = "yyyy:MM:dd"

		gpsDict[kCGImagePropertyGPSLatitude as String] = abs(loc.coordinate.latitude)
		gpsDict[kCGImagePropertyGPSLatitudeRef as String] = loc.coordinate.latitude >= 0 ? "N" : "S"
		gpsDict[kCGImagePropertyGPSLongitude as String] = abs(loc.coordinate.longitude)
		gpsDict[kCGImagePropertyGPSLongitudeRef as String] = loc.coordinate.longitude >= 0 ? "E" : "W"
		gpsDict[kCGImagePropertyGPSAltitude as String] = loc.altitude
		gpsDict[kCGImagePropertyGPSAltitudeRef as String] = loc.altitude >= 0 ? 0 : 1
		gpsDict[kCGImagePropertyGPSDateStamp as String] = dateFormatter.string(from: loc.timestamp)
		gpsDict[kCGImagePropertyGPSTimeStamp as String] = timeFormatter.string(from: loc.timestamp)
	}

	// Inject heading values
	if let hdg = heading {
		gpsDict[kCGImagePropertyGPSImgDirection as String] = hdg.trueHeading
		gpsDict[kCGImagePropertyGPSImgDirectionRef as String] = "T" // "T" for true north
	}

	var metadata = metadataOrig
	metadata[kCGImagePropertyGPSDictionary as String] = gpsDict

	// Write the new data to exif
	let outputData = NSMutableData()
	guard let destination = CGImageDestinationCreateWithData(outputData, imageType, 1, nil) else {
		return nil
	}
	CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
	CGImageDestinationFinalize(destination)

	return outputData as Data
}

private class CameraOverlayView: UIView {
	enum State {
		case capturing
		case reviewing
	}

	let cancelButton = UIButton(type: .system)
	let shutterButton = makeShutterButton(size: 50)
	let retakeButton = UIButton(type: .system)
	let acceptButton = UIButton(type: .system)

	private let previewView = UIImageView()
	private var currentState: State = .capturing

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = .clear
		setupButtons()
		switchToState(.capturing)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	private static func makeShutterButton(size: CGFloat) -> UIButton {
		let button = UIButton()
		button.backgroundColor = .white

		button.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			button.widthAnchor.constraint(equalToConstant: size),
			button.heightAnchor.constraint(equalTo: button.widthAnchor)
		])

		// Make circular
		button.layer.cornerRadius = size / 2
		button.layer.masksToBounds = true

		// Add black ring just inside edge
		let ringLayer = CAShapeLayer()
		let inset: CGFloat = 2.0
		let radius = (size / 2) - inset
		let ringPath = UIBezierPath(arcCenter: CGPoint(x: size / 2, y: size / 2),
		                            radius: radius,
		                            startAngle: 0,
		                            endAngle: .pi * 2,
		                            clockwise: true)
		ringLayer.path = ringPath.cgPath
		ringLayer.strokeColor = UIColor.black.cgColor
		ringLayer.fillColor = UIColor.clear.cgColor
		ringLayer.lineWidth = 1.0
		button.layer.addSublayer(ringLayer)
		return button
	}

	private func setupButtons() {
		if #available(iOS 13.0, *) {
			cancelButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
			acceptButton.setImage(UIImage(systemName: "checkmark.circle"), for: .normal)
			retakeButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
		} else {
			cancelButton.setTitle("Cancel", for: .normal)
			acceptButton.setTitle("Use Photo", for: .normal)
			retakeButton.setTitle("Retake", for: .normal)
		}
		[shutterButton, cancelButton, retakeButton, acceptButton].forEach { button in
			button.translatesAutoresizingMaskIntoConstraints = false
			addSubview(button)
		}

		NSLayoutConstraint.activate([
			cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			cancelButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),

			shutterButton.centerXAnchor.constraint(equalTo: centerXAnchor),
			shutterButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

			acceptButton.centerXAnchor.constraint(equalTo: centerXAnchor),
			acceptButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),

			retakeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			retakeButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor)
		])

		// Preview after image is captured
		previewView.contentMode = .scaleAspectFit
		previewView.isHidden = true
		addSubview(previewView)
		previewView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			previewView.leadingAnchor.constraint(equalTo: leadingAnchor),
			previewView.trailingAnchor.constraint(equalTo: trailingAnchor),
			previewView.topAnchor.constraint(equalTo: topAnchor),
			previewView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
	}

	func switchToState(_ state: State) {
		currentState = state

		switch state {
		case .capturing:
			shutterButton.isHidden = false
			retakeButton.isHidden = true
			acceptButton.isHidden = true
		case .reviewing:
			shutterButton.isHidden = true
			retakeButton.isHidden = false
			acceptButton.isHidden = false
		}
	}

	func showPreview(_ image: UIImage) {
		previewView.image = image
		previewView.alpha = 0
		previewView.isHidden = false
		UIView.animate(withDuration: 0.3) {
			self.previewView.alpha = 1
		}
	}

	func hidePreview() {
		previewView.isHidden = true
		previewView.image = nil
	}
}

class PhotoCapture: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
	private let picker = UIImagePickerController()
	private let overlayView = CameraOverlayView()
	private var capturedImage: UIImage?
	private var capturedImageData: Data?

	var locationManager: CLLocationManager?
	var onAccept: ((UIImage, Data) -> Void)?
	var onCancel: (() -> Void)?
	var onError: (() -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()

		if #available(iOS 13.0, *) {
			isModalInPresentation = true
		}

		picker.sourceType = .camera
		picker.allowsEditing = false
		picker.showsCameraControls = false
		picker.cameraOverlayView = overlayView
		picker.delegate = self

		addChild(picker)
		view.addSubview(picker.view)
		picker.view.frame = view.bounds
		overlayView.frame = view.bounds
		picker.didMove(toParent: self)

		// center picker in screen
		let screenSize = picker.view.bounds.size
		let cameraAspectRatio: CGFloat = 4.0 / 3.0 // Typical for iOS camera
		let previewHeight = screenSize.width * cameraAspectRatio
		let verticalOffset = (screenSize.height - previewHeight) / 2
		picker.cameraViewTransform = CGAffineTransform(translationX: 0, y: verticalOffset)

		// Set up overlay transitions
		overlayView.shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
		overlayView.retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
		overlayView.acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
		overlayView.cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
	}

	@objc private func shutterTapped() {
		picker.takePicture()
		overlayView.acceptButton.isEnabled = false
		overlayView.switchToState(.reviewing)
	}

	@objc private func retakeTapped() {
		overlayView.hidePreview()
		overlayView.switchToState(.capturing)
	}

	@objc private func acceptTapped() {
		if let image = capturedImage,
		   let data = capturedImageData
		{
			dismiss(animated: true)
			onAccept?(image, data)
		} else {
			onError?()
			dismiss(animated: true)
		}
	}

	@objc private func cancelTapped() {
		dismiss(animated: true)
		onCancel?()
	}

	func imagePickerController(_ picker: UIImagePickerController,
	                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
	{
		// get image
		let location = locationManager?.location
		let heading = locationManager?.heading
		guard let image = info[.originalImage] as? UIImage else {
			onError?()
			dismiss(animated: true)
			return
		}
		overlayView.showPreview(image)
		overlayView.switchToState(.reviewing)

		// converting to data is slow so we do it in the background so we can show the preview immediately
		DispatchQueue.global(qos: .userInitiated).async {
			let data = dataFor(image: image, location: location, heading: heading)
			DispatchQueue.main.sync {
				guard let data else {
					self.onError?()
					self.dismiss(animated: true)
					return
				}
				self.capturedImage = image
				self.capturedImageData = data
				self.overlayView.acceptButton.isEnabled = true
			}
		}
	}

	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		dismiss(animated: true)
	}
}
