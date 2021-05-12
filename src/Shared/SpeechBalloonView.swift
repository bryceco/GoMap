//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  SpeechBalloonView.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#if os(iOS)
    import Foundation
#else
    import Cocoa
#endif


class SpeechBalloonView: NSView {
    var path: CGMutablePath?
    let arrowWidth: CGFloat = 20
    let arrowHeight: CGFloat = 48
    var _displayLink: CADisplayLink?


    class func layerClass() -> AnyClass {
        return CAShapeLayer.self
    }

    init(text: String?) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        #if os(iOS)
        wantsLayer = true
        #endif
        let shapeLayer = layer as? CAShapeLayer

        // shape layer
        shapeLayer?.fillColor = NSColor.white.cgColor
        shapeLayer?.strokeColor = NSColor.black.cgColor
        shapeLayer?.lineWidth = 6

        // text layer
        let textLayer = CATextLayer()
        textLayer.contentsScale = UIScreen.main.scale
        #if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .headline)
        #else
        let font = NSFont.labelFont(ofSize: 12)
        #endif
        textLayer.font = font as? CGFont
        textLayer.fontSize = 18
        textLayer.alignmentMode = .center
        textLayer.string = text
        textLayer.foregroundColor = NSColor.black.cgColor
        shapeLayer?.addSublayer(textLayer)

        let textSize = textLayer.preferredFrameSize()

        var boxSize = textSize
        boxSize.width += 35
        boxSize.height += 30

        // creat path with arrow
        let cornerRadius: CGFloat = 14
        path = CGMutablePath()
        let center = 0.35
        path?.move(to: CGPoint(x: boxSize.width / 2, y: boxSize.height + arrowHeight), transform: .identity) // arrow bottom
        path?.addLine(to: CGPoint(x: CGFloat(Double(boxSize.width) * center - Double(arrowWidth / 2)), y: boxSize.height), transform: .identity) // arrow top-left
        path?.addArc(tangent1End: CGPoint(x: 0, y: boxSize.height), tangent2End: CGPoint(x: 0, y: 0), radius: cornerRadius, transform: .identity) // bottom right corner
        path?.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: boxSize.width, y: 0), radius: cornerRadius, transform: .identity) // top left corner
        path?.addArc(tangent1End: CGPoint(x: boxSize.width, y: 0), tangent2End: CGPoint(x: boxSize.width, y: boxSize.height), radius: cornerRadius, transform: .identity) // top right corner
        path?.addArc(tangent1End: CGPoint(x: boxSize.width, y: boxSize.height), tangent2End: CGPoint(x: 0, y: boxSize.height), radius: cornerRadius, transform: .identity) // bottom right corner
        path?.addLine(to: CGPoint(x: CGFloat(Double(boxSize.width) * center + Double(arrowWidth / 2)), y: boxSize.height), transform: .identity) // arrow top-right
        path?.closeSubpath()
        let viewRect = path?.boundingBoxOfPath
        shapeLayer?.path = path

        textLayer.frame = CGRect(x: (boxSize.width - textSize.width) / 2, y: (boxSize.height - textSize.height) / 2, width: textSize.width, height: textSize.height)

        frame = CGRect(x: 0, y: 0, width: viewRect?.size.width ?? 0.0, height: viewRect?.size.height ?? 0.0)
    }

    func setPoint(_ point: CGPoint) {
        // set bottom center at point
        let rect = frame
        rect.origin.x = point.x - rect.size.width / 2
        rect.origin.y = point.y - rect.size.height
        frame = rect as? NSRect ?? NSRect.zero
    }

    func setTarget(_ view: UIView?) {
        let rc = view?.frame
        let pt = CGPoint(x: Double((rc?.origin.x ?? 0.0) + (rc?.size.width ?? 0.0) / 2), y: Double((rc?.origin.y ?? 0.0) - (rc?.size.height ?? 0.0) / 2))
        setPoint(pt)
    }

    func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        #if os(iOS)
        if !super.point(inside: point, with: event) {
            return false
        }
        #endif
        if !path?.containsPoint(point, using: .winding, transform: .identity) {
            return false
        }
        return true
    }

    deinit {
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
