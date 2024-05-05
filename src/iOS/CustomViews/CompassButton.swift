//
//  CompassButton.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/1/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import UIKit

class CompassButton: UIButton {
	func commonInit() {
		contentMode = .center
		setImage(nil, for: .normal)
		backgroundColor = UIColor.white
		compass(withRadius: bounds.size.width / 2)
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	func compass(withRadius radius: CGFloat) {
		let needleWidth = round(radius / 5)
		layer.bounds = CGRect(x: 0, y: 0, width: 2 * radius, height: 2 * radius)
		layer.cornerRadius = radius
		do {
			let north = CAShapeLayer()
			let path = UIBezierPath()
			path.move(to: CGPoint(x: -needleWidth, y: 0))
			path.addLine(to: CGPoint(x: needleWidth, y: 0))
			path.addLine(to: CGPoint(x: 0, y: -round(radius * 0.9)))
			path.close()
			north.path = path.cgPath
			north.fillColor = UIColor.systemRed.cgColor
			north.position = CGPoint(x: radius, y: radius)
			layer.addSublayer(north)
		}
		do {
			let south = CAShapeLayer()
			let path = UIBezierPath()
			path.move(to: CGPoint(x: -needleWidth, y: 0))
			path.addLine(to: CGPoint(x: needleWidth, y: 0))
			path.addLine(to: CGPoint(x: 0, y: round(radius * 0.9)))
			path.close()
			south.path = path.cgPath
			south.fillColor = UIColor.lightGray.cgColor
			south.position = CGPoint(x: radius, y: radius)
			layer.addSublayer(south)
		}
		do {
			let pivot = CALayer()
			pivot.bounds = CGRect(
				x: radius - needleWidth / 2,
				y: radius - needleWidth / 2,
				width: needleWidth,
				height: needleWidth)
			pivot.backgroundColor = UIColor.white.cgColor
			pivot.borderColor = UIColor.black.cgColor
			pivot.cornerRadius = needleWidth / 2
			pivot.position = CGPoint(x: radius, y: radius)
			layer.addSublayer(pivot)
		}
	}

	func rotate(angle: CGFloat) {
		transform = CGAffineTransform(rotationAngle: angle)
	}
}
