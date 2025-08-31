//
//  DPadView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/30/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import UIKit

private enum Direction { case up, down, left, right }

private class ArrowButton: UIButton {
	let direction: Direction

	init(frame: CGRect, direction: Direction) {
		self.direction = direction
		super.init(frame: frame)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

protocol DPadDelegate {
	func dPadPress(_ shift: CGPoint)
}

class DPadView: UIView {
	var delegate: DPadDelegate?

	private func arrowButton(frame: CGRect, dir: Direction) -> ArrowButton {
		let button = ArrowButton(frame: frame, direction: dir)

		// draw triangle
		let arrowSideInset = 0.33
		let arrowPtInset = 0.2
		let arrowPath = UIBezierPath()
		arrowPath.move(to: CGPoint(x: (1 - arrowPtInset) * frame.width,
		                           y: (0.5 - arrowSideInset) * frame.height))
		arrowPath.addLine(to: CGPoint(x: arrowPtInset * frame.width,
		                              y: 0.5 * frame.height))
		arrowPath.addLine(to: CGPoint(x: (1 - arrowPtInset) * frame.width,
		                              y: (0.5 + arrowSideInset) * frame.height))
		arrowPath.close()
		let arrowLayer = CAShapeLayer()
		arrowLayer.path = arrowPath.cgPath
		arrowLayer.fillColor = UIColor.white.cgColor
		if #available(iOS 13.0, *) {
			arrowLayer.strokeColor = UIColor.link.cgColor
		} else {
			arrowLayer.strokeColor = UIColor.systemBlue.cgColor
		}
		button.layer.addSublayer(arrowLayer)

		switch dir {
		case .left:
			break
		case .right:
			arrowLayer.transform = CATransform3DMakeRotation(Double.pi, 0.0, 0.0, 1.0)
			arrowLayer.transform = CATransform3DTranslate(arrowLayer.transform, -frame.width, -frame.height, 0.0)
		case .up:
			arrowLayer.transform = CATransform3DMakeRotation(Double.pi / 2, 0.0, 0.0, 1.0)
			arrowLayer.transform = CATransform3DTranslate(arrowLayer.transform, 0.0, -frame.height, 0.0)
		case .down:
			arrowLayer.transform = CATransform3DMakeRotation(-Double.pi / 2, 0.0, 0.0, 1.0)
			arrowLayer.transform = CATransform3DTranslate(arrowLayer.transform, -frame.width, 0.0, 0.0)
		}
		return button
	}

	func commonInit() {
		backgroundColor = nil

		// draw "+" outline
		let plusInset = 1 / 3.0
		let plusPath = UIBezierPath()
		plusPath.move(to: CGPoint(x: plusInset * frame.width, y: 0.0))
		plusPath.addLine(to: CGPoint(x: frame.width * (1 - plusInset), y: 0.0))
		plusPath.addLine(to: CGPoint(x: frame.width * (1 - plusInset), y: frame.height * plusInset))
		plusPath.addLine(to: CGPoint(x: frame.width, y: frame.height * plusInset))
		plusPath.addLine(to: CGPoint(x: frame.width, y: frame.height * (1 - plusInset)))
		plusPath.addLine(to: CGPoint(x: frame.width * (1 - plusInset), y: frame.height * (1 - plusInset)))
		plusPath.addLine(to: CGPoint(x: frame.width * (1 - plusInset), y: frame.height))
		plusPath.addLine(to: CGPoint(x: frame.width * plusInset, y: frame.height))
		plusPath.addLine(to: CGPoint(x: frame.width * plusInset, y: frame.height * (1 - plusInset)))
		plusPath.addLine(to: CGPoint(x: 0, y: frame.height * (1 - plusInset)))
		plusPath.addLine(to: CGPoint(x: 0, y: frame.height * plusInset))
		plusPath.addLine(to: CGPoint(x: frame.width * plusInset, y: frame.height * plusInset))
		plusPath.close()
		let plusLayer = CAShapeLayer()
		plusLayer.path = plusPath.cgPath
		plusLayer.fillColor = UIColor.lightGray.cgColor
		MainViewController.applyButtonShadow(layer: plusLayer)
		plusLayer.shadowPath = plusPath.cgPath
		plusLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
		plusLayer.lineWidth = 1
		layer.addSublayer(plusLayer)

		// draw triangle buttons
		let buttonSize = CGSize(width: (1 - 2 * plusInset) * frame.width,
		                        height: (1 - 2 * plusInset) * frame.height)
		let leftButton = arrowButton(frame: CGRect(x: 0.0,
		                                           y: bounds.midY - plusInset * bounds.height / 2,
		                                           width: buttonSize.width,
		                                           height: buttonSize.height),
		                             dir: .left)
		let rightButton = arrowButton(frame: CGRect(x: bounds.maxX - buttonSize.width,
		                                            y: bounds.midY - plusInset * bounds.height / 2,
		                                            width: buttonSize.width,
		                                            height: buttonSize.height),
		                              dir: .right)
		let upButton = arrowButton(frame: CGRect(x: bounds.midX - plusInset * bounds.width / 2,
		                                         y: 0.0,
		                                         width: buttonSize.width,
		                                         height: buttonSize.height),
		                           dir: .up)
		let downButton = arrowButton(frame: CGRect(x: bounds.midX - plusInset * bounds.width / 2,
		                                           y: bounds.maxY - buttonSize.height,
		                                           width: buttonSize.width,
		                                           height: buttonSize.height),
		                             dir: .down)
		for button in [leftButton, rightButton, upButton, downButton] {
			button.addTarget(self, action: #selector(buttonPress(_:)), for: .touchUpInside)
			addSubview(button)
		}
	}

	@objc func buttonPress(_ sender: Any) {
		guard let button = sender as? ArrowButton else { return }
		let move: CGPoint
		switch button.direction {
		case .left:
			move = CGPoint(x: -1, y: 0)
		case .right:
			move = CGPoint(x: 1, y: 0)
		case .up:
			move = CGPoint(x: 0, y: 1)
		case .down:
			move = CGPoint(x: 0, y: -1)
		}
		delegate?.dPadPress(move)
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}
}
