//
//  LocationBallView.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import QuartzCore
import UIKit

final class LocationBallView: UIView, MapPositionedView {
	private var headingLayer: CAGradientLayer
	private var ringLayer: CAShapeLayer
	private var circleLayer: CAShapeLayer

	var location: LatLon = .zero

	func updateLocation(_ location: CLLocation) {
		guard
			location.horizontalAccuracy >= 0,
			location.horizontalAccuracy < 1000
		else {
			return
		}
		updateLocationDefault(LatLon(lon: location.coordinate.longitude, lat: location.coordinate.latitude))

		// set location accuracy
		if let viewPort {
			let meters = location.horizontalAccuracy
			var pixels = CGFloat(meters / viewPort.metersPerPixel())
			if pixels == 0.0 {
				pixels = 100.0
			}
			radiusInPixels = pixels
		}
	}

	var viewPort: MapViewPort? {
		didSet {
			oldValue?.mapTransform.onChange.unsubscribe(self)
			guard let viewPort else { return }
			viewPort.mapTransform.onChange.subscribe(self) { [weak self] in
				guard let self else { return }
				self.updateScreenPosition()

				guard !isHidden else { return }
				let screenAngle = viewPort.mapTransform.rotation()
				let mainView = AppDelegate.shared.mainView!
				if mainView.gpsState == .HEADING,
				   abs(heading - -.pi / 2) < 0.001
				{
					// don't pin location ball to North until we've animated our rotation to north
					heading = -.pi / 2
				} else {
					if let heading = LocationProvider.shared.currentHeading {
						let heading = viewPort.headingAdjustedForInterfaceOrientation(heading)
						self.heading = CGFloat(screenAngle + heading - .pi / 2)
					}
				}
			}
		}
	}

	var showHeading = false {
		didSet {
			setNeedsLayout()
		}
	}

	var heading: CGFloat = 0.0 { // radians
		didSet {
			setNeedsLayout()
		}
	}

	var headingAccuracy: CGFloat = 0.0 {
		didSet {
			setNeedsLayout()
		}
	}

	var radiusInPixels: CGFloat = 0.0 {
		didSet(oldValue) {
			if oldValue == radiusInPixels {
				return
			}
			let animation = ringAnimation(withRadius: radiusInPixels)
			ringLayer.add(animation, forKey: "ring")
		}
	}

	override init(frame: CGRect) {
		ringLayer = CAShapeLayer()
		headingLayer = CAGradientLayer()
		circleLayer = CAShapeLayer()

		super.init(frame: frame)

		self.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
		backgroundColor = .clear
		isUserInteractionEnabled = false

		radiusInPixels = 25.0

		let circleColor = UIColor(red: 79 / 255.0, green: 138 / 255.0, blue: 247 / 255.0, alpha: 1.0)

		// create an animated expanding ring that shows GPS accuracy
		ringLayer.fillColor = UIColor.clear.cgColor
		ringLayer.strokeColor = circleColor.cgColor
		ringLayer.lineWidth = 2.0
		ringLayer.frame = bounds
		ringLayer.position = CGPoint(x: 16, y: 16)
		let animation = ringAnimation(withRadius: 100)
		ringLayer.add(animation, forKey: "ring")
		layer.addSublayer(ringLayer)

		// create a mask that will be shaped as a cone for the heading
		let rc = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 80.0)
		let gradientMask = CAShapeLayer()
		gradientMask.fillColor = UIColor.black.cgColor
		gradientMask.frame = rc

		// create a radial gradient for the heading cone
		headingLayer.isHidden = true
		headingLayer.frame = rc.offsetBy(dx: (bounds.size.width - rc.width) / 2,
		                                 dy: (bounds.size.height - rc.height) / 2)
		headingLayer.type = .radial
		headingLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
		headingLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
		headingLayer.colors = [circleColor.cgColor,
		                       circleColor.cgColor,
		                       circleColor.withAlphaComponent(0.7).cgColor,
		                       circleColor.withAlphaComponent(0.4).cgColor,
		                       circleColor.withAlphaComponent(0.2).cgColor]
		headingLayer.mask = gradientMask
		layer.addSublayer(headingLayer)

		// create a circle marking the current location
		circleLayer.path = UIBezierPath(ovalIn: bounds).cgPath
		circleLayer.frame = bounds
		circleLayer.fillColor = circleColor.cgColor
		circleLayer.strokeColor = UIColor.white.cgColor
		circleLayer.lineWidth = 2.0
		layer.addSublayer(circleLayer)

		// add shadow
		layer.shadowColor = UIColor.black.cgColor
		layer.shadowOffset = CGSize(width: 3, height: 3)
		layer.shadowOpacity = 0.6
	}

	convenience init() {
		self.init(frame: .zero)
	}

	func ringAnimation(withRadius radius: CGFloat) -> CABasicAnimation {
		let startRadius: CGFloat = 5
		let finishRadius = radius
		let startPath = CGPath(ellipseIn: CGRect(x: -startRadius, y: -startRadius,
		                                         width: 2 * startRadius, height: 2 * startRadius),
		                       transform: nil)
		let finishPath = CGPath(ellipseIn: CGRect(x: -finishRadius, y: -finishRadius,
		                                          width: 2 * finishRadius, height: 2 * finishRadius),
		                        transform: nil)
		let anim = CABasicAnimation(keyPath: "path")
		anim.duration = 2.0
		anim.fromValue = startPath
		anim.toValue = finishPath
		anim.isRemovedOnCompletion = false
		anim.fillMode = .forwards
		anim.repeatCount = .greatestFiniteMagnitude

		return anim
	}

	override func layoutSubviews() {
		super.layoutSubviews()

		if showHeading, headingAccuracy > 0 {
			// draw heading
			let shapeLayer = headingLayer.mask as! CAShapeLayer
			let radius = shapeLayer.bounds.width / 2
			let path = CGMutablePath()
			let center = shapeLayer.bounds.center()
			path.addArc(
				center: center,
				radius: radius,
				startAngle: heading - headingAccuracy,
				endAngle: heading + headingAccuracy,
				clockwise: false)
			path.addLine(to: center)
			path.closeSubpath()
			shapeLayer.path = path
			headingLayer.isHidden = false
		} else {
			headingLayer.isHidden = true
		}
	}

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
