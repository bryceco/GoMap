//
//  CrossHairsLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/18/22.
//  Copyright © 2022 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

class CrossHairsLayer: CAShapeLayer {
	init(radius: CGFloat) {
		super.init()
		var path = UIBezierPath()
		let radius: CGFloat = 12
		path.move(to: CGPoint(x: -radius, y: 0))
		path.addLine(to: CGPoint(x: radius, y: 0))
		path.move(to: CGPoint(x: 0, y: -radius))
		path.addLine(to: CGPoint(x: 0, y: radius))
		anchorPoint = CGPoint(x: 0.5, y: 0.5)
		self.path = path.cgPath
		strokeColor = UIColor(red: 1.0, green: 1.0, blue: 0.5, alpha: 1.0).cgColor
		bounds = CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius)
		lineWidth = 2.0

		path = UIBezierPath()
		let shadowWidth: CGFloat = 2.0
		let p1 = UIBezierPath(rect: CGRect(x: -(radius + shadowWidth - 1),
		                                   y: -shadowWidth,
		                                   width: 2 * (radius + shadowWidth - 1),
		                                   height: 2 * shadowWidth))
		let p2 = UIBezierPath(rect: CGRect(x: -shadowWidth,
		                                   y: -(radius + shadowWidth - 1),
		                                   width: 2 * shadowWidth,
		                                   height: 2 * (radius + shadowWidth - 1)))
		path.append(p1)
		path.append(p2)
		shadowColor = UIColor.black.cgColor
		shadowOpacity = 1.0
		shadowPath = path.cgPath
		shadowRadius = 0
		shadowOffset = CGSize(width: 0, height: 0)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
