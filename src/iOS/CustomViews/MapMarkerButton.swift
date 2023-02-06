//
//  MapMarkerButton.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/6/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

@IBDesignable
final class MapMarkerButton: UIButton {

	let radius = 12.0	// radius of ciruclar part
	let height = 24.0	// distance from center of circle to bottom vertex

	init() {
		arrowPoint = CGPoint.zero

		super.init(frame: CGRect.zero)

		// build the path for it, starting at the bottom vertex
		let arcAngle = asin(radius / height)

		let path = UIBezierPath()
		path.move(to: CGPoint(x: radius, y: height+radius))
		path.addArc(withCenter: CGPoint(x:radius,y:radius),
					radius: radius,
					startAngle: Double.pi-arcAngle, endAngle: arcAngle, clockwise: true)
		path.close()

		let shapeLayer = CAShapeLayer()
		shapeLayer.fillColor = UIColor.blue.cgColor
		shapeLayer.strokeColor = UIColor.white.cgColor
		shapeLayer.borderWidth = 2.0
		shapeLayer.path = path.cgPath

		self.layer.addSublayer(shapeLayer)
		frame = CGRect(x: arrowPoint.x-radius, y: arrowPoint.y, width: 2*radius, height: height+radius)
	}

	var arrowPoint: CGPoint {
		didSet {
			self.frame = CGRect(x: arrowPoint.x-radius,
								y: arrowPoint.y-(height+radius),
								width: 2*radius,
								height: height+radius)
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
