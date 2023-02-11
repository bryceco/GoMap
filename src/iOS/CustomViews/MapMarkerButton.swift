//
//  MapMarkerButton.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/6/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

@IBDesignable
final class MapMarkerButton: MapView.MapViewButton {
	let radius: CGFloat // radius of ciruclar part
	let height: CGFloat // distance from center of circle to bottom vertex
	let isCurvy: Bool

	init(radius: CGFloat = 12.0, height: CGFloat = 24.0, isCurvy: Bool = true, icon: UIImage) {
		arrowPoint = CGPoint.zero
		self.radius = radius
		self.height = height
		self.isCurvy = isCurvy
		super.init(frame: CGRect.zero)

		// build the path for it, starting at the bottom vertex
		let arcAngle = asin(radius / height)
		let path = UIBezierPath()
		if isCurvy {
			// The botton portion is more pointy
			let radius2 = (height * height / radius - radius) / 2
			path.addArc(withCenter: CGPoint(x: radius - radius2, y: height + radius),
			            radius: radius2,
			            startAngle: 0.0,
			            endAngle: -arcAngle,
			            clockwise: false)
			path.addArc(withCenter: CGPoint(x: radius, y: radius),
			            radius: radius,
			            startAngle: Double.pi - arcAngle,
			            endAngle: arcAngle,
			            clockwise: true)
			path.addArc(withCenter: CGPoint(x: radius + radius2, y: height + radius),
			            radius: radius2,
			            startAngle: Double.pi + arcAngle,
			            endAngle: Double.pi,
			            clockwise: false)
			path.close()
		} else {
			// The bottom portion is a simple triangle
			path.move(to: CGPoint(x: radius, y: height + radius))
			path.addArc(withCenter: CGPoint(x: radius, y: radius),
			            radius: radius,
			            startAngle: Double.pi - arcAngle,
			            endAngle: arcAngle,
			            clockwise: true)
			path.close()
		}

		let shapeLayer = CAShapeLayer()
		shapeLayer.fillColor = UIColor.blue.cgColor
		shapeLayer.strokeColor = UIColor.blue.cgColor
		shapeLayer.borderWidth = 2.0
		shapeLayer.path = path.cgPath

		let iconLayer = CALayer()
		iconLayer.contents = icon.cgImage
		shapeLayer.addSublayer(iconLayer)
		iconLayer.frame = CGRect(x: 1, y: 1, width: 2 * radius - 2, height: 2 * radius - 2)

		layer.addSublayer(shapeLayer)
	}

	convenience init(withIcon icon: UIImage) {
		self.init(icon: icon)
	}

	var arrowPoint: CGPoint {
		didSet {
			frame = CGRect(x: arrowPoint.x - radius,
			               y: arrowPoint.y - (height + radius),
			               width: 2 * radius,
			               height: height + radius)
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
