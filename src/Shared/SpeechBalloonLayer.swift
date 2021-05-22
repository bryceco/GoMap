//
//  SpeechBalloonLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore

let arrowWidth: CGFloat = 16
let arrowHeight: CGFloat = 16

class SpeechBalloonLayer: CAShapeLayer {
    var textLayer: CATextLayer?
    
    private var _text: String?
    var text: String? {
        get {
            return _text
        }
        set(text) {
            _text = text
            redraw()
        }
    }
    
    override init() {
        super.init()
        fillColor = UIColor.blue.cgColor
        strokeColor = UIColor.black.cgColor
#if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .caption1)
#else
        let font = NSFont.labelFont(ofSize: 12)
#endif
        textLayer = CATextLayer()
        textLayer?.contentsScale = UIScreen.main.scale
        textLayer?.font = font
        textLayer?.fontSize = 12
        textLayer?.alignmentMode = .center
        if let textLayer = textLayer {
            addSublayer(textLayer)
        }
    }
    
    func redraw() {
        textLayer?.string = text
        var size = textLayer?.preferredFrameSize()
        let cornerRadius: CGFloat = 4
        
        size?.width += 10
        
        let rcSuper = superlayer?.bounds
        let flipVertical = position.y - (rcSuper?.origin.y ?? 0.0) < 4 * (size?.height ?? 0.0)
        let flipHorizontal = (rcSuper?.origin.x ?? 0.0) + (rcSuper?.size.width ?? 0.0) - position.x < (size?.width ?? 0.0) + 10
        
        var transform = CGAffineTransform.identity
        if flipVertical {
            transform.d = -1
        }
        if flipHorizontal {
            transform.a = -1
        }
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cornerRadius, y: 0), transform: transform) // top left
        path.addArc(tangent1End: CGPoint(x: size?.width ?? 0.0, y: 0), tangent2End: CGPoint(x: size?.width ?? 0.0, y: size?.height ?? 0.0), radius: cornerRadius, transform: transform) // top right
        path.addArc(tangent1End: CGPoint(x: size?.width ?? 0.0, y: size?.height ?? 0.0), tangent2End: CGPoint(x: 0, y: size?.height ?? 0.0), radius: cornerRadius, transform: transform) // bottom right
        path.addLine(to: CGPoint(x: 2 * arrowWidth, y: size?.height ?? 0.0), transform: transform) // arrow top-right
        path.addLine(to: CGPoint(x: arrowWidth / 2, y: (size?.height ?? 0.0) + arrowHeight), transform: transform) // arrow bottom
        path.addLine(to: CGPoint(x: arrowWidth, y: size?.height ?? 0.0), transform: transform) // arrow top-left
        path.addArc(tangent1End: CGPoint(x: 0, y: size?.height ?? 0.0), tangent2End: CGPoint(x: 0, y: 0), radius: cornerRadius, transform: transform) // bottom left
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: size?.width ?? 0.0, y: 0), radius: cornerRadius, transform: transform)
        
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
            rc.origin.y -= size?.height ?? 0.0
        }
        if flipHorizontal {
            rc.origin.x -= size?.width ?? 0.0
        }
        textLayer?.frame = rc
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
