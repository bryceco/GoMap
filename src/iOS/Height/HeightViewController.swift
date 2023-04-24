//
//  HeightViewController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/19/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

import AVFoundation
import CoreMotion
import UIKit

private let InsetPercent: CGFloat = 0.15

class HeightViewController: UIViewController {
	private var captureSession: AVCaptureSession?
	private var previewLayer: AVCaptureVideoPreviewLayer?
	private var coreMotion: CMMotionManager?
	private var cameraFOV = 0.0
	private var canZoom = false
	@IBOutlet var distanceLabel: UIButton!
	@IBOutlet var heightLabel: UIButton!
	@IBOutlet var applyButton: UIButton!
	@IBOutlet var cancelButton: UIButton!
	private var rulerViews: [Int: UILabel] = [:]
	private var rulerLayers: [Int: CAShapeLayer] = [:]
	private var isExiting = false
	private var scrollPosition: CGFloat = 0.0
	private var totalZoom = 0.0
	private var currentHeight = ""

	var callback: ((_ newValue: String) -> Void)?

	class func unableToInstantiate(withUserWarning vc: UIViewController) -> Bool {
		if AppDelegate.shared.mapView.gpsState == GPS_STATE.NONE {
			let alert = UIAlertController(
				title: NSLocalizedString("Error", comment: "Error dialog title"),
				message: NSLocalizedString("This action requires GPS to be turned on", comment: ""),
				preferredStyle: .alert)
			alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
			vc.present(alert, animated: true)
			return true
		}
		if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
			let error = NSLocalizedString(
				"In order to measure height, please enable camera access in the app's settings.",
				comment: "")
			AppDelegate.askUserToOpenSettings(withAlertTitle: "Error", message: error, parentVC: vc)
			return true
		}
		return false
	}

	class func instantiate() -> HeightViewController {
		let sb = UIStoryboard(name: "Height", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "HeightViewController") as? HeightViewController
		return vc!
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		rulerViews = [:]
		rulerLayers = [:]

		view.backgroundColor = UIColor.black

		applyButton.layer.cornerRadius = 5
		applyButton.layer.backgroundColor = UIColor.black.cgColor
		applyButton.layer.borderColor = UIColor.white.cgColor
		applyButton.layer.borderWidth = 1.0
		applyButton.layer.zPosition = 1

		cancelButton.layer.cornerRadius = 5
		cancelButton.layer.backgroundColor = UIColor.black.cgColor
		cancelButton.layer.borderColor = UIColor.white.cgColor
		cancelButton.layer.borderWidth = 1.0
		cancelButton.layer.zPosition = 1

		distanceLabel.backgroundColor = nil
		distanceLabel.layer.cornerRadius = 5
		distanceLabel.layer.backgroundColor = UIColor(red: 0.4, green: 0.4, blue: 1.0, alpha: 0.75).cgColor
		distanceLabel.layer.zPosition = 1

		heightLabel.backgroundColor = nil
		heightLabel.layer.cornerRadius = 5
		heightLabel.layer.backgroundColor = UIColor(red: 0, green: 0, blue: 1.0, alpha: 0.75).cgColor
		heightLabel.layer.zPosition = 1

		totalZoom = 1.0
		scrollPosition = 20

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
		view.addGestureRecognizer(tap)

		let pan = UIPanGestureRecognizer(target: self, action: #selector(didPan(_:)))
		view.addGestureRecognizer(pan)

		let pinch = UIPinchGestureRecognizer(target: self, action: #selector(didPinch(_:)))
		view.addGestureRecognizer(pinch)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		coreMotion = CMMotionManager()
		coreMotion?.deviceMotionUpdateInterval = 1.0 / 30
		let currentQueue = OperationQueue.current
		weak var weakSelf = self
		if let currentQueue = currentQueue {
			coreMotion?.startDeviceMotionUpdates(
				using: .xTrueNorthZVertical,
				to: currentQueue,
				withHandler: { motion, _ in
					if let motion = motion {
						weakSelf?.refreshRulerLabels(motion)
					}
				})
		}

		_ = startCameraPreview()

		if canZoom {
			let rc = view.bounds
			let lineMargin: CGFloat = 30
			let arrowWidth: CGFloat = 10
			let arrowLength: CGFloat = 20
			let layer = CAShapeLayer()
			let path = UIBezierPath()
			let inset = ceil(rc.size.height * InsetPercent)
			// lower line
			path.move(to: CGPoint(x: 0, y: inset))
			path.addLine(to: CGPoint(x: rc.size.width, y: inset))
			// upper line
			path.move(to: CGPoint(x: 0, y: rc.size.height - inset))
			path.addLine(to: CGPoint(x: rc.size.width, y: rc.size.height - inset))
			// vertical
			path.move(to: CGPoint(x: lineMargin, y: inset + 2))
			path.addLine(to: CGPoint(x: lineMargin, y: rc.size.height - inset - 2))
			// top arrow
			path.move(to: CGPoint(x: lineMargin - arrowWidth, y: inset + arrowLength))
			path.addLine(to: CGPoint(x: lineMargin, y: inset + 2))
			path.addLine(to: CGPoint(x: lineMargin + arrowWidth, y: inset + arrowLength))
			// bottom arrow
			path.move(to: CGPoint(x: lineMargin - arrowWidth, y: rc.size.height - inset - arrowLength))
			path.addLine(to: CGPoint(x: lineMargin, y: rc.size.height - inset - 2))
			path.addLine(to: CGPoint(x: lineMargin + arrowWidth, y: rc.size.height - inset - arrowLength))

			layer.path = path.cgPath
			layer.strokeColor = UIColor.green.cgColor
			layer.fillColor = nil
			layer.lineWidth = 2
			layer.frame = view.bounds
			view.layer.addSublayer(layer)
		}
	}

	func startCameraPreview() -> Bool {
		captureSession = AVCaptureSession()

		guard let captureSession = captureSession,
		      let videoDevice = AVCaptureDevice.default(for: .video),
		      let videoIn = try? AVCaptureDeviceInput(device: videoDevice),
		      captureSession.canAddInput(videoIn)
		else {
			return false
		}
		captureSession.addInput(videoIn)

		let format = videoDevice.formats.reversed().first(where: { $0.videoMaxZoomFactor > 10 })
			?? videoDevice.formats.last!
		do {
			try videoDevice.lockForConfiguration()
			videoDevice.activeFormat = format
			videoDevice.unlockForConfiguration()
		} catch {}

		// can camera zoom?
		canZoom = videoDevice.activeFormat.videoMaxZoomFactor >= 10.0

		// get FOV
		cameraFOV = Double(videoDevice.activeFormat.videoFieldOfView)
		if cameraFOV == 0 {
			cameraFOV = calculateCameraFOV()
		}
		cameraFOV *= .pi / 180

		previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
		guard let previewLayer = previewLayer else { return false }
		previewLayer.videoGravity = .resizeAspectFill
		previewLayer.bounds = view.layer.bounds
		previewLayer.position = view.layer.bounds.center()
		previewLayer.zPosition = -1 // buttons and labels need to be above video
		view.layer.addSublayer(previewLayer)

		captureSession.startRunning()

		return true
	}

	@objc func didTap(_ tap: UITapGestureRecognizer) {
		var pos = tap.location(in: view)
		guard let input = captureSession?.inputs.last as? AVCaptureDeviceInput else { return }
		do {
			try input.device.lockForConfiguration()
			let rc = view.bounds
			pos.x = (pos.x - rc.origin.x) / rc.size.width
			pos.y = (pos.y - rc.origin.y) / rc.size.height
			input.device.exposurePointOfInterest = pos
			input.device.unlockForConfiguration()
		} catch {}
	}

	@objc func didPan(_ pan: UIPanGestureRecognizer) {
		let delta = pan.translation(in: view)
		scrollPosition -= delta.y
		pan.setTranslation(CGPoint(x: 0, y: 0), in: view)
	}

	@objc func didPinch(_ pinch: UIPinchGestureRecognizer) {
		if canZoom {
			guard let input = captureSession?.inputs.last as? AVCaptureDeviceInput else { return }
			let device = input.device

			let maxZoom = device.activeFormat.videoMaxZoomFactor
			totalZoom *= Double(pinch.scale)
			if totalZoom < 1.0 {
				totalZoom = 1.0
			} else if totalZoom > Double(maxZoom) {
				totalZoom = Double(maxZoom)
			}

			do {
				try device.lockForConfiguration()
				device.videoZoomFactor = CGFloat(totalZoom)
				device.unlockForConfiguration()
			} catch {}
			pinch.scale = 1.0
		}
	}

	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		return .portrait
	}

	override var shouldAutorotate: Bool {
		return false
	}

	static var cameraFOVCameraAngle: Double = 0

	private static let ModelList = [(model: String, fov: Double, focal_length: Double, vertical_sensor_size: Double)](
		// http://caramba-apps.com/blog/files/field-of-view-angles-ipad-iphone.html
		arrayLiteral:
		("iPad5,4", 0.0, 3.3, 0.0), // iPad Air 2
		("iPad4,5", 0.0, 0.0, 0.0), // iPad Mini (2nd Generation iPad Mini - Cellular)
		("iPad4,4", 0.0, 0.0, 0.0), // iPad Mini (2nd Generation iPad Mini - Wifi)
		("iPad4,2", 0.0, 0.0, 0.0), // iPad Air 5th Generation iPad (iPad Air) - Cellular
		("iPad4,1", 0.0, 0.0, 0.0), // iPad Air 5th Generation iPad (iPad Air) - Wifi
		("iPad3,6", 0.0, 0.0, 0.0), // iPad 4 (4th Generation)
		("iPad3,5", 0.0, 0.0, 0.0), // iPad 4 (4th Generation)
		("iPad3,4", 0.0, 0.0, 0.0), // iPad 4 (4th Generation)
		("iPad3,3", 0.0, 0.0, 0.0), // iPad 3 (3rd Generation)
		("iPad3,2", 0.0, 0.0, 0.0), // iPad 3 (3rd Generation)
		("iPad3,1", 0.0, 0.0, 0.0), // iPad 3 (3rd Generation)
		("iPad2,7", 0.0, 0.0, 0.0), // iPad Mini (Original)
		("iPad2,6", 0.0, 0.0, 0.0), // iPad Mini (Original)
		("iPad2,5", 0.0, 3.3, 0.0), // iPad Mini (Original)
		("iPad2,4", 43.47, 0.0, 0.0), // iPad 2
		("iPad2,3", 43.47, 0.0, 0.0), // iPad 2
		("iPad2,2", 43.47, 0.0, 0.0), // iPad 2
		("iPad2,1", 43.47, 0.0, 0.0), // iPad 2

		("iPhone7,2", 0.0, 4.15, 4.89), // iPhone 6+
		("iPhone7,1", 0.0, 4.15, 4.89), // iPhone 6
		("iPhone6,2", 0.0, 4.12, 4.89), // iPhone 5s (model A1457, A1518, A1528 (China), A1530 | Global)
		("iPhone6,1", 0.0, 4.12, 4.89), // iPhone 5s model A1433, A1533 | GSM)
		("iPhone5,4", 0.0, 4.10, 4.54), // iPhone 5c (model A1507, A1516, A1526 (China), A1529 | Global)
		("iPhone5,3", 0.0, 4.10, 4.54), // iPhone 5c (model A1456, A1532 | GSM)
		("iPhone5,2", 58.498, 4.10, 4.592), // iPhone 5 (model A1429, everything else)
		("iPhone5,1", 58.498, 4.10, 4.592), // iPhone 5 (model A1428, AT&T/Canada)
		("iPhone4,1", 56.423, 4.28, 4.592), // iPhone 4S
		("iPhone3,1", 61.048, 3.85, 4.54), // iPhone 4
		("iPhone2,1", 49.871, 3.85, 3.58), // iPhone 3GS
		("iPhone1,1", 49.356, 3.85, 3.538), // iPhone 3

		("iPod4,1", 0.0, 0.0, 0.0), // iPod Touch (Fifth Generation)
		("iPod4,1", 0.0, 0.0, 0.0) // iPod Touch (Fourth Generation)
	)

	func calculateCameraFOV() -> Double {
		var systemInfo = utsname()
		uname(&systemInfo)
		for device in HeightViewController.ModelList {
			if device.vertical_sensor_size == 0 {
				continue
			}
			if device.focal_length == 0 {
				continue
			}
			let a = 2 * atan2(device.vertical_sensor_size / 2, device.focal_length) * 180 / .pi
			assert(device.fov == 0 || abs(Float(a - device.fov)) < 0.01)
			let machineMirror = Mirror(reflecting: systemInfo.machine)
			let model = machineMirror.children.reduce("") { identifier, element in
				guard let value = element.value as? Int8, value != 0 else { return identifier }
				return identifier + String(UnicodeScalar(UInt8(value)))
			}
			if strcmp(model, device.model) == 0 {
				HeightViewController.cameraFOVCameraAngle = a
			}
		}

		if HeightViewController.cameraFOVCameraAngle == 0 {
			HeightViewController.cameraFOVCameraAngle = 58.498 // wild guess
		}
		return HeightViewController.cameraFOVCameraAngle
	}

	func distanceToObject(error: inout Double, direction pDirection: inout Double) -> Double {
		let delegate = AppDelegate.shared
		var object = delegate.mapView.editorLayer.selectedPrimary
		if object == nil, delegate.mapView.pushPin == nil {
			error = .nan
			pDirection = .nan
			return .nan
		}
		if object == nil {
			// brand new object, so fake it
			let latlon = delegate.mapView.mapTransform.latLon(forScreenPoint: delegate.mapView.pushPin!.arrowPoint)
			// this gets thrown away at the end of this method so the details aren't important
			let node = OsmNode(withVersion: 0, changeset: 0, user: "", uid: 0, ident: 0, timestamp: "", tags: [:])
			node.setLongitude(latlon.lon, latitude: latlon.lat, undo: nil)
			object = node
		}
		guard let object = object else { return 0.0 }
		let location = delegate.mapView.currentLocation
		let userPt = LatLon(location.coordinate)
		var dist = Double(MAXFLOAT)
		var bearing: Double = 0

		for node in object.nodeSet() {
			let nodePt = node.latLon
			let d = GreatCircleDistance(userPt, nodePt)
			if d < dist {
				dist = d
				var dir = OSMPoint(x: lat2latp(nodePt.lat) - lat2latp(userPt.lat),
				                   y: nodePt.lon - userPt.lon)
				dir = dir.unitVector()
				bearing = atan2(dir.y, dir.x)
			}
		}

		error = location.horizontalAccuracy
		pDirection = bearing

		return dist
	}

	func distanceString(forFloat num: Double) -> String {
		if abs(Float(num)) < 10 {
			return String.localizedStringWithFormat("%.1f", num)
		} else {
			return String.localizedStringWithFormat("%.0f", num)
		}
	}

	func refreshRulerLabels(_ motion: CMDeviceMotion) {
		if isExiting {
			return
		}

		// compute location
		var distError = 0.0
		var direction = 0.0
		let dist = distanceToObject(error: &distError, direction: &direction)
		if dist.isNaN {
			cancel(self)
			return
		}

		// get camera tilt
		var pitch = motion.attitude.pitch
		let yaw = motion.attitude.yaw
		if fabs(yaw - direction) < .pi / 2 {
			pitch = .pi / 2 - pitch
		} else {
			pitch = pitch - .pi / 2
		}

		// update distance label
		let distText = String.localizedStringWithFormat(NSLocalizedString("Distance: %1$@ ± %2$@ meters",
		                                                                  comment: "Distance to an object with an error value"),
		                                                distanceString(forFloat: dist),
		                                                distanceString(forFloat: distError))
		UIView.performWithoutAnimation({ [self] in
			distanceLabel.setTitle(distText, for: .normal)
			distanceLabel.layoutIfNeeded()
		})

		let rc = view.bounds
		let dist2 = Double((rc.size.height / 2) / tan(CGFloat(cameraFOV) / 2))

		if canZoom {
			let height1 = dist * tan(pitch - atan2(Double(rc.size.height / 2 * (1 - InsetPercent)) / totalZoom, dist2))
			let height2 = dist * tan(pitch + atan2(Double(rc.size.height / 2 * (1 - InsetPercent)) / totalZoom, dist2))
			let height = height2 - height1
			let heightError = height * distError / dist
			currentHeight = distanceString(forFloat: height)
			let text = String.localizedStringWithFormat(NSLocalizedString("Height: %1$@ ± %2$@ meters",
			                                                              comment: "Height of an object with an error value"),
			                                            currentHeight,
			                                            distanceString(forFloat: heightError))
			UIView.performWithoutAnimation({ [self] in
				heightLabel.setTitle(text, for: .normal)
				heightLabel.layoutIfNeeded()
			})
		} else {
			let userHeight = tan(cameraFOV / 2 - pitch) * dist

			// get number of labels to display
			let maxHeight = dist * tan(cameraFOV / 2 + pitch) + dist * tan(cameraFOV / 2 - pitch)
			var increment = 0.1
			var scale = 1
			while maxHeight / increment > 10 {
				if scale == 1 {
					scale = 2
					increment *= 2
				} else if scale == 2 {
					scale = 5
					increment *= 2.5
				} else {
					scale = 1
					increment *= 2
				}
			}

			let scrollHeight = Double(scrollPosition) * dist / dist2

			for div in -20..<30 {
				let labelBorderWidth: CGFloat = 5
				let labelHeight = Double(div) * increment * 0.5
				let height = labelHeight + scrollHeight

				let angleRelativeToGround = atan2(height - userHeight, dist)
				let centerAngleOffset = angleRelativeToGround - pitch

				let delta = tan(centerAngleOffset) * dist2
				let pixels = round(Double(rc.size.height / 2) - delta)

				var labelWidth: CGFloat = 0
				if div % 2 == 0 {
					let label: UILabel
					if let lab = rulerViews[div] {
						label = lab
					} else {
						label = UILabel()
						rulerViews[div] = label
					}

					if pixels > Double(rc.size.height) || pixels < 0 {
						label.removeFromSuperview()
					} else {
						label.layer.anchorPoint = CGPoint(x: 0, y: 0.5)
						label.text = String.localizedStringWithFormat(
							NSLocalizedString("%@ meters", comment: "Always plural"),
							distanceString(forFloat: Double(height - scrollHeight)))
						label.font = UIFont.preferredFont(forTextStyle: .headline)
						label.backgroundColor = UIColor(white: 1.0, alpha: 0.5)
						label.textColor = UIColor.black
						label.textAlignment = .center
						label.sizeToFit()
						label.bounds = label.bounds.insetBy(dx: -labelBorderWidth, dy: 0)
						label.center = CGPoint(x: 0, y: CGFloat(pixels))
						labelWidth = label.bounds.size.width
						if label.superview == nil {
							view.addSubview(label)
						}
					}
				}

				let layer: CAShapeLayer
				if let lay = rulerLayers[div] {
					layer = lay
				} else {
					layer = CAShapeLayer()
					rulerLayers[div] = layer
				}
				if pixels > Double(rc.size.height) || pixels < 0 {
					layer.removeFromSuperlayer()
				} else {
					let path = UIBezierPath()
					let isZero = div == 0
					path.move(to: CGPoint(x: labelWidth, y: CGFloat(pixels)))
					path.addLine(to: CGPoint(x: rc.size.width, y: CGFloat(pixels)))
					layer.path = path.cgPath
					layer.strokeColor = isZero ? UIColor.green.cgColor : UIColor.white.cgColor
					layer.lineWidth = isZero ? 2 : 1
					layer.frame = view.bounds
					if div % 2 == 1 {
						layer.lineDashPattern = [NSNumber(value: 5), NSNumber(value: 4)]
					}
					if layer.superlayer == nil {
						view.layer.addSublayer(layer)
					}
				}
			}
		}
	}

	@IBAction func cancel(_ sender: Any?) {
		isExiting = true
		captureSession?.stopRunning()
		coreMotion?.stopDeviceMotionUpdates()

		for v in view.subviews {
			v.removeFromSuperview()
		}
		view.layer.sublayers = nil

		if let navigationController = navigationController {
			navigationController.popViewController(animated: true)
		} else {
			dismiss(animated: true)
		}
	}

	@IBAction func apply(_ sender: Any) {
		if canZoom {
			setHeight(currentHeight)
		} else {
			let alert = UIAlertController(
				title: NSLocalizedString("Set Height Tag", comment: "The height=* tag"),
				message: NSLocalizedString("meters", comment: ""),
				preferredStyle: .alert)
			alert.addTextField(configurationHandler: { textField in
				textField.keyboardType = .numbersAndPunctuation
			})
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
			alert
				.addAction(UIAlertAction(title: NSLocalizedString("Set", comment: "set tag value"),
				                         style: .default, handler: { [self] _ in
				                         	let textField = alert.textFields![0]
				                         	let text = textField.text!
				                         		.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
				                         	setHeight(text)
				                         }))
			present(alert, animated: true)
		}
	}

	func setHeight(_ height: String) {
		if let callback = callback {
			callback(height)
		}
		cancel(nil)
	}
}
