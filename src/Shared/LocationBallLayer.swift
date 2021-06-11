//
//  LocationBallLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore

class LocationBallLayer: CALayer {
    var _headingLayer: CAShapeLayer?
    var _ringLayer: CAShapeLayer
    
    var showHeading = false {
		didSet {
			setNeedsLayout()
		}
    }
    
	var heading: CGFloat = 0.0 {	 // radians
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
		willSet(newValue) {
			if newValue == radiusInPixels {
				return
			}
			let animation = ringAnimation(withRadius: newValue)
			_ringLayer.add(animation, forKey: "ring")
        }
    }
    
    override init() {
		_ringLayer = CAShapeLayer()

		super.init()
        frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        
        radiusInPixels = 25.0
        
        actions = [
            "onOrderIn": NSNull(),
            "onOrderOut": NSNull(),
            "sublayers": NSNull(),
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull()
        ]
        
#if os(iOS)
        _ringLayer.fillColor = UIColor.clear.cgColor
        _ringLayer.strokeColor = UIColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 1.0).cgColor
#else
        ringLayer.fillColor = NSColor(calibratedRed: 0.8, green: 0.8, blue: 1.0, alpha: 0.4).cgColor
        ringLayer.strokeColor = NSColor(calibratedRed: 0.5, green: 0.5, blue: 1.0, alpha: 1.0).cgColor
#endif
        _ringLayer.lineWidth = 2.0
        _ringLayer.frame = bounds
        _ringLayer.position = CGPoint(x: 16, y: 16)
        
        let animation = ringAnimation(withRadius: 100)
		_ringLayer.add(animation, forKey: "ring")

		addSublayer(_ringLayer)

        let imageLayer = CALayer()
        let image = UIImage(named: "BlueBall")!
#if os(iOS)
        imageLayer.contents = image.cgImage
#else
        imageLayer.contents = image
#endif
        imageLayer.frame = bounds
        addSublayer(imageLayer)
    }
    
    func ringAnimation(withRadius radius: CGFloat) -> CABasicAnimation {
        let startRadius: CGFloat = 5
        let finishRadius = radius
        let startPath = CGMutablePath()
        startPath.addEllipse(in: CGRect(x: -startRadius, y: -startRadius, width: 2 * startRadius, height: 2 * startRadius), transform: .identity)
        
        let finishPath = CGMutablePath()
        finishPath.addEllipse(in: CGRect(x: -finishRadius, y: -finishRadius, width: 2 * finishRadius, height: 2 * finishRadius), transform: .identity)
        let anim = CABasicAnimation(keyPath: "path")
        anim.duration = 2.0
        anim.fromValue = startPath
        anim.toValue = finishPath
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        anim.repeatCount = .greatestFiniteMagnitude
        
        return anim
    }
    
    override func layoutSublayers() {
        if showHeading && headingAccuracy > 0 {
            if _headingLayer == nil {
                _headingLayer = CAShapeLayer()
#if os(iOS)
                _headingLayer?.fillColor = UIColor(red: 0.5, green: 1.0, blue: 0.5, alpha: 0.4).cgColor
                _headingLayer?.strokeColor = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0).cgColor
#else
                headingLayer?.fillColor = NSColor(calibratedRed: 0.5, green: 1.0, blue: 0.5, alpha: 0.4).cgColor
                headingLayer?.strokeColor = NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.0, alpha: 1.0).cgColor
#endif
                _headingLayer?.zPosition = -1
                var rc = bounds
                rc.origin.x += rc.size.width / 2
                rc.origin.y += rc.size.height / 2
                _headingLayer?.frame = rc
                if let headingLayer = _headingLayer {
                    addSublayer(headingLayer)
                }
            }
            
            // draw heading
            let radius: CGFloat = 40.0
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: 0.0, y: 0.0), radius: radius, startAngle: heading - headingAccuracy, endAngle: heading + headingAccuracy, clockwise: false, transform: .identity)
            path.addLine(to: CGPoint(x: 0, y: 0), transform: .identity)
            path.closeSubpath()
            _headingLayer?.path = path
        } else {
            if _headingLayer != nil {
                _headingLayer?.removeFromSuperlayer()
                _headingLayer = nil
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
