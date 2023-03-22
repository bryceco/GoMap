//
//  RulerLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import UIKit

func roundToEvenValue(_ value: Double) -> Double {
	var scale: Double = 1

	while true {
		if value < scale * 10 {
			if floor(value / scale) < 2 {
				return 1 * scale
			}
			if floor(value / scale) < 5 {
				return 2 * scale
			}
			return 5 * scale
		}
		scale *= 10
	}
}

class RulerView: UIView {
	private var shapeLayer: CAShapeLayer
	private var metricTextLayer: CATextLayer
	private var britishTextLayer: CATextLayer
	var mapView: MapView? {
		didSet {
			mapView?.mapTransform.observe(by: self, callback: { self.updateText() })
		}
	}

	required init?(coder: NSCoder) {
		shapeLayer = CAShapeLayer()
		metricTextLayer = CATextLayer()
		britishTextLayer = CATextLayer()

		super.init(coder: coder)
		backgroundColor = nil

		shapeLayer.lineWidth = 2
		shapeLayer.strokeColor = UIColor.black.cgColor
		shapeLayer.fillColor = nil

		let font = UIFont.preferredFont(forTextStyle: .caption2)
		metricTextLayer.font = font
		britishTextLayer.font = font
		metricTextLayer.fontSize = 12 // font.pointSize;
		britishTextLayer.fontSize = 12 // font.pointSize;
		metricTextLayer.foregroundColor = UIColor.black.cgColor
		britishTextLayer.foregroundColor = UIColor.black.cgColor
		metricTextLayer.alignmentMode = .center
		britishTextLayer.alignmentMode = .center
		metricTextLayer.contentsScale = UIScreen.main.scale
		britishTextLayer.contentsScale = UIScreen.main.scale

		layer.shadowColor = UIColor.white.cgColor
		layer.shadowRadius = 0.0
		layer.shadowOpacity = 0.4
		layer.shadowOffset = CGSize(width: 0, height: 0)
		layer.shadowPath = CGPath(rect: bounds.insetBy(dx: -2, dy: -2), transform: nil)

		shapeLayer.shadowOpacity = 0.0
		metricTextLayer.shadowOpacity = 0.0
		britishTextLayer.shadowOpacity = 0.0

		layer.addSublayer(shapeLayer)
		layer.addSublayer(metricTextLayer)
		layer.addSublayer(britishTextLayer)
	}

	override var frame: CGRect {
		get {
			return super.frame
		}
		set(frame) {
			super.frame = frame
			shapeLayer.frame = bounds
			setNeedsLayout()
		}
	}

	override func layoutSubviews() {
		var rc = bounds
		if rc.size.width <= 1 || rc.size.height <= 1 {
			return
		}

		let path = CGMutablePath()
		path.move(to: CGPoint(x: rc.minX, y: rc.midY))
		path.addLine(to: CGPoint(x: rc.maxX, y: rc.midY))
		path.move(to: CGPoint(x: rc.minX, y: rc.minY))
		path.addLine(to: CGPoint(x: rc.minX, y: rc.maxY))
		path.move(to: CGPoint(x: rc.maxX, y: rc.minY))
		path.addLine(to: CGPoint(x: rc.maxX, y: rc.maxY))
		shapeLayer.path = path

		rc.size.height = rc.height / 2
		britishTextLayer.frame = rc

		rc.origin.y = rc.origin.y + rc.height
		metricTextLayer.frame = rc
	}

	private func updateText() {
		guard let metersPerPixel = mapView?.metersPerPixel() else {
			return
		}

		var widthMetric = Measurement(value: bounds.width * metersPerPixel, unit: UnitLength.meters)
		if widthMetric.value >= 1000 {
			widthMetric = widthMetric.converted(to: .kilometers)
		} else if widthMetric.value < 1.0 {
			widthMetric = widthMetric.converted(to: .centimeters)
		}

		var widthBritish = widthMetric.converted(to: .feet)
		if widthBritish.value >= 5280 {
			widthBritish = widthBritish.converted(to: .miles)
		} else if widthBritish.value < 1.0 {
			widthBritish = widthBritish.converted(to: .inches)
		}

		let formatter = MeasurementFormatter()
		formatter.unitOptions = [.providedUnit]
		formatter.numberFormatter = NumberFormatter()
		formatter.numberFormatter.maximumSignificantDigits = 3
		metricTextLayer.string = formatter.string(from: widthMetric)
		britishTextLayer.string = formatter.string(from: widthBritish)
	}

	override func setNeedsLayout() {
		super.setNeedsLayout()
	}
}
