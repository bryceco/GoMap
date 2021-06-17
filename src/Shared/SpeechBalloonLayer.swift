//
//  SpeechBalloonLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

private let arrowWidth: CGFloat = 16
private let arrowHeight: CGFloat = 16

class SpeechBalloonLayer: CAShapeLayer {
    let textLayer: CATextLayer
    
    var text: String = "" {
		didSet(text) {
			redraw()
        }
    }
    
    override init() {
		textLayer = CATextLayer()
        super.init()
        fillColor = UIColor.blue.cgColor
        strokeColor = UIColor.black.cgColor
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .caption1)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.font = font
        textLayer.fontSize = 12
        textLayer.alignmentMode = .center
		addSublayer(textLayer)
    }
    
    func redraw() {
        textLayer.string = text
        var size = textLayer.preferredFrameSize()
        let cornerRadius: CGFloat = 4
        
        size.width += 10
        
        let rcSuper = superlayer!.bounds
        let flipVertical = position.y - rcSuper.origin.y < 4 * size.height
        let flipHorizontal = rcSuper.origin.x + rcSuper.size.width - position.x < size.width + 10
        
        var transform = CGAffineTransform.identity
        if flipVertical {
            transform.d = -1
        }
        if flipHorizontal {
            transform.a = -1
        }
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cornerRadius, y: 0), transform: transform) // top left
        path.addArc(tangent1End: CGPoint(x: size.width, y: 0), tangent2End: CGPoint(x: size.width, y: size.height), radius: cornerRadius, transform: transform) // top right
        path.addArc(tangent1End: CGPoint(x: size.width, y: size.height), tangent2End: CGPoint(x: 0, y: size.height), radius: cornerRadius, transform: transform) // bottom right
		path.addLine(to: CGPoint(x: 2 * arrowWidth, y: size.height), transform: transform) // arrow top-right
        path.addLine(to: CGPoint(x: arrowWidth / 2, y: size.height + arrowHeight), transform: transform) // arrow bottom
        path.addLine(to: CGPoint(x: arrowWidth, y: size.height), transform: transform) // arrow top-left
        path.addArc(tangent1End: CGPoint(x: 0, y: size.height), tangent2End: CGPoint(x: 0, y: 0), radius: cornerRadius, transform: transform) // bottom left
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: size.width, y: 0), radius: cornerRadius, transform: transform)
        
        self.path = path
        
        var rc = path.boundingBox
        
        rc.origin = bounds.origin
        var offset = CGSize(width: 4, height: 12)
        if flipVertical {
            offset.height -= 3 * rc.size.height
        }
        if flipHorizontal {
            offset.width = -offset.width
        }
        anchorPoint = CGPoint(x: -offset.width / rc.size.width, y: 1 + offset.height / rc.size.height)
        bounds = rc
        
        if flipVertical {
            rc.origin.y -= size.height
        }
        if flipHorizontal {
            rc.origin.x -= size.width
        }
        textLayer.frame = rc
    }
    
    required init?(coder aDecoder: NSCoder) {
		fatalError()
	}
}
