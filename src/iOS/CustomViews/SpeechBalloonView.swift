//
//  SpeechBalloonView.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

class SpeechBalloonView: UIView {
	let path: CGPath
	let arrowWidth: CGFloat = 20
	let arrowHeight: CGFloat = 48

	class func layerClass() -> AnyClass {
		return CAShapeLayer.self
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	init(text: String?) {
		// text layer
		let textLayer = CATextLayer()
		textLayer.contentsScale = UIScreen.main.scale
		let font = UIFont.preferredFont(forTextStyle: .headline)
		textLayer.font = font
		textLayer.fontSize = 18
		textLayer.alignmentMode = .center
		textLayer.string = text
		textLayer.foregroundColor = UIColor.black.cgColor

		let textSize = textLayer.preferredFrameSize()

		var boxSize = textSize
		boxSize.width += 35
		boxSize.height += 30

		// creat path with arrow
		let cornerRadius: CGFloat = 14
		let center = 0.35
		let path = CGMutablePath()
		path.move(to: CGPoint(x: boxSize.width / 2, y: boxSize.height + arrowHeight)) // arrow bottom
		path
			.addLine(to: CGPoint(x: CGFloat(Double(boxSize.width) * center - Double(arrowWidth / 2)),
			                     y: boxSize.height)) // arrow top-left
		path.addArc(
			tangent1End: CGPoint(x: 0, y: boxSize.height),
			tangent2End: CGPoint(x: 0, y: 0),
			radius: cornerRadius) // bottom right corner
		path.addArc(
			tangent1End: CGPoint(x: 0, y: 0),
			tangent2End: CGPoint(x: boxSize.width, y: 0),
			radius: cornerRadius) // top left corner
		path.addArc(
			tangent1End: CGPoint(x: boxSize.width, y: 0),
			tangent2End: CGPoint(x: boxSize.width, y: boxSize.height),
			radius: cornerRadius) // top right corner
		path.addArc(
			tangent1End: CGPoint(x: boxSize.width, y: boxSize.height),
			tangent2End: CGPoint(x: 0, y: boxSize.height),
			radius: cornerRadius) // bottom right corner
		path
			.addLine(to: CGPoint(x: CGFloat(Double(boxSize.width) * center + Double(arrowWidth / 2)),
			                     y: boxSize.height)) // arrow top-right
		path.closeSubpath()
		self.path = path

		textLayer.frame = CGRect(
			x: (boxSize.width - textSize.width) / 2,
			y: (boxSize.height - textSize.height) / 2,
			width: textSize.width,
			height: textSize.height)

		let viewRect = path.boundingBoxOfPath
		super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
		frame = CGRect(x: 0, y: 0, width: viewRect.size.width, height: viewRect.size.height)

		let shapeLayer = layer as! CAShapeLayer
		shapeLayer.path = path

		// shape layer
		shapeLayer.fillColor = UIColor.white.cgColor
		shapeLayer.strokeColor = UIColor.black.cgColor
		shapeLayer.lineWidth = 6

		shapeLayer.addSublayer(textLayer)
	}

	func setPoint(_ point: CGPoint) {
		// set bottom center at point
		var rect = frame
		rect.origin.x = point.x - rect.size.width / 2
		rect.origin.y = point.y - rect.size.height
		frame = rect
	}

	func setTarget(_ view: UIView?) {
		let rc = view?.frame
		let pt = CGPoint(
			x: Double((rc?.origin.x ?? 0.0) + (rc?.size.width ?? 0.0) / 2),
			y: Double((rc?.origin.y ?? 0.0) - (rc?.size.height ?? 0.0) / 2))
		setPoint(pt)
	}

	override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
		if !super.point(inside: point, with: event) {
			return false
		}
		return path.contains(point)
	}
}
