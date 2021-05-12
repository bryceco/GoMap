//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  PushPinView.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore
import UIKit

//typealias PushPinViewDragCallback = (UIGestureRecognizer.State, CGFloat, CGFloat, UIGestureRecognizer) -> Void

@objcMembers
class PushPinView: UIButton, CAAnimationDelegate {
    var _panCoord = CGPoint.zero
    var _shapeLayer: CAShapeLayer? // shape for balloon
    var _textLayer: CATextLayer? // text in balloon
    var _hittestRect = CGRect.zero
    var _moveButton: CALayer?
    var _buttonList: [UIButton]?
    var _callbackList: [() -> Void]?
    var _lineLayers: [CAShapeLayer]?

    private var _placeholderLayer: CALayer?
    var placeholderLayer: CALayer? {
        get {
            return _placeholderLayer
        } set(placeholderLayer) {
            _placeholderLayer = placeholderLayer
        }
        
    }

    var text: String? {
        get {
            return _textLayer?.string as? String
        }
        set(text) {
            if text == _textLayer?.string as? String {
                return
            }
            _textLayer?.string = text
            setNeedsLayout()
        }
    }

    private var _arrowPoint = CGPoint.zero
    var arrowPoint: CGPoint {
        get {
            return _arrowPoint
        }
        set(arrowPoint) {
            if arrowPoint.x.isNaN || arrowPoint.y.isNaN {
                DLog("bad arrow location")
                return
            }
            _arrowPoint = arrowPoint
            center = CGPoint(x: arrowPoint.x, y: arrowPoint.y + bounds.size.height / 2)
        }
    }
    var dragCallback: PushPinViewDragCallback?

    private var _labelOnBottom = false
    var labelOnBottom: Bool {
        get {
            return _labelOnBottom
        }
        set(labelOnBottom) {
            if labelOnBottom != _labelOnBottom {
                _labelOnBottom = labelOnBottom
                setNeedsLayout()
            }
        }
    }

    init() {
        super.init(frame: CGRect.zero)
        labelOnBottom = true

        _shapeLayer = CAShapeLayer()
        _shapeLayer?.fillColor = UIColor.gray.cgColor
        _shapeLayer?.strokeColor = UIColor.white.cgColor
        _shapeLayer?.shadowColor = UIColor.black.cgColor
        _shapeLayer?.shadowOffset = CGSize(width: 3, height: 3)
        _shapeLayer?.shadowOpacity = 0.6
        if let shapeLayer = _shapeLayer {
            layer.addSublayer(shapeLayer)
        }

        // text layer
        _textLayer = CATextLayer()
        _textLayer?.contentsScale = UIScreen.main.scale

        let font = UIFont.preferredFont(forTextStyle: .headline)
        _textLayer?.font = font
        _textLayer?.fontSize = font.pointSize
        _textLayer?.alignmentMode = .left
        _textLayer?.truncationMode = .end

        _textLayer?.foregroundColor = UIColor.white.cgColor
        if let textLayer = _textLayer {
            _shapeLayer?.addSublayer(textLayer)
        }

        _moveButton = CALayer()
        _moveButton?.frame = CGRect(x: 0, y: 0, width: 25, height: 25)
        _moveButton?.contents = UIImage(named: "move.png")?.cgImage
        if let moveButton = _moveButton {
            _shapeLayer?.addSublayer(moveButton)
        }

        placeholderLayer = CALayer()
        if let placeholderLayer = placeholderLayer {
            _shapeLayer?.addSublayer(placeholderLayer)
        }

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(draggingGesture(_:))))
    }

    deinit {
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // test the label box
        if _hittestRect.contains(point) {
            return self
        }
#if targetEnvironment(macCatalyst)
        // also hit the arrow point
        if abs(Float(point.y)) < 12 && abs(Float(point.x - _hittestRect.origin.x - _hittestRect.size.width / 2)) < 12 {
            return self
        }
#endif
        // and any buttons connected to us
        for button in _buttonList ?? [] {
            let point2 = button.convert(point, from: self)
            let hit = button.hitTest(point2, with: event)
            if let hit = hit {
                return hit
            }
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var textSize = _textLayer?.preferredFrameSize()
        if (textSize?.width ?? 0.0) > 300 {
            textSize?.width = 300
        }

        let buttonCount = Int(max((_buttonList?.count ?? 0), 1))
        let moveButtonGap: CGFloat = 3.0
        let buttonVerticalSpacing: CGFloat = 55
        let textAlleyWidth: CGFloat = 5
        let width = (textSize?.width ?? 0.0) + 2 * textAlleyWidth + moveButtonGap + (_moveButton?.frame.size.width ?? 0.0)
        let height: CGFloat = (textSize?.height ?? 0.0) + 2 * textAlleyWidth
        let boxSize = CGSize(width: width, height: height)
        let arrowHeight = 20 + (CGFloat(buttonCount) * buttonVerticalSpacing) / 2
        let arrowWidth: CGFloat = 20
        let buttonHorzOffset: CGFloat = 44
        let buttonHeight: CGFloat = ((_buttonList?.count ?? 0) != 0 ? _buttonList?[0].frame.size.height : 0) ?? 0.0

        let topGap = buttonHeight / 2 + CGFloat((buttonCount - 1)) * buttonVerticalSpacing / 2

        // creat path with arrow
        let cornerRadius: CGFloat = 4
        let viewPath = CGMutablePath()
        if labelOnBottom {
            _hittestRect = CGRect(x: 0, y: arrowHeight, width: boxSize.width, height: boxSize.height)
            viewPath.move(to: CGPoint(x: boxSize.width / 2, y: 0), transform: .identity) // arrow top
            viewPath.addLine(to: CGPoint(x: boxSize.width / 2 - arrowWidth / 2, y: arrowHeight), transform: .identity) // arrow top-left
            viewPath.addArc(tangent1End: CGPoint(x: 0, y: arrowHeight), tangent2End: CGPoint(x: 0, y: boxSize.height + arrowHeight), radius: cornerRadius, transform: .identity) // bottom right corner
            viewPath.addArc(tangent1End: CGPoint(x: 0, y: boxSize.height + arrowHeight), tangent2End: CGPoint(x: boxSize.width, y: boxSize.height + arrowHeight), radius: cornerRadius, transform: .identity) // top left corner
            viewPath.addArc(tangent1End: CGPoint(x: boxSize.width, y: boxSize.height + arrowHeight), tangent2End: CGPoint(x: boxSize.width, y: arrowHeight), radius: cornerRadius, transform: .identity) // top right corner
            viewPath.addArc(tangent1End: CGPoint(x: boxSize.width, y: arrowHeight), tangent2End: CGPoint(x: 0, y: arrowHeight), radius: cornerRadius, transform: .identity) // bottom right corner
            viewPath.addLine(to: CGPoint(x: boxSize.width / 2 + arrowWidth / 2, y: arrowHeight), transform: .identity) // arrow top-right
            viewPath.closeSubpath()
        } else {
            viewPath.move(to: CGPoint(x: boxSize.width / 2, y: boxSize.height + arrowHeight), transform: .identity) // arrow bottom
            viewPath.addLine(to: CGPoint(x: boxSize.width / 2 - arrowWidth / 2, y: boxSize.height), transform: .identity) // arrow top-left
            viewPath.addArc(tangent1End: CGPoint(x: 0, y: boxSize.height), tangent2End: CGPoint(x: 0, y: 0), radius: cornerRadius, transform: .identity) // bottom right corner
            viewPath.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: boxSize.width, y: 0), radius: cornerRadius, transform: .identity) // top left corner
            viewPath.addArc(tangent1End: CGPoint(x: boxSize.width, y: 0), tangent2End: CGPoint(x: boxSize.width, y: boxSize.height), radius: cornerRadius, transform: .identity) // top right corner
            viewPath.addArc(tangent1End: CGPoint(x: boxSize.width, y: boxSize.height), tangent2End: CGPoint(x: 0, y: boxSize.height), radius: cornerRadius, transform: .identity) // bottom right corner
            viewPath.addLine(to: CGPoint(x: boxSize.width / 2 + arrowWidth / 2, y: boxSize.height), transform: .identity) // arrow top-right
            viewPath.closeSubpath()
        }

        // make hit target a little larger
        _hittestRect = _hittestRect.insetBy(dx: -7, dy: -7)

        let viewRect = viewPath.boundingBoxOfPath
        _shapeLayer?.frame = CGRect(x: 0, y: 0, width: 20, height: 20) // arbitrary since it is a shape
        _shapeLayer?.path = viewPath
        _shapeLayer?.shadowPath = viewPath

        if labelOnBottom {
            _textLayer?.frame = CGRect(
                x: textAlleyWidth,
                y: topGap + arrowHeight + textAlleyWidth,
                width: boxSize.width - textAlleyWidth,
                height: textSize?.height ?? 0.0)
            _moveButton?.frame = CGRect(
                x: boxSize.width - (_moveButton?.frame.size.width ?? 0.0) - 3,
                y: topGap + arrowHeight + (boxSize.height - (_moveButton?.frame.size.height ?? 0.0)) / 2,
                width: _moveButton?.frame.size.width ?? 0.0,
                height: _moveButton?.frame.size.height ?? 0.0)
        } else {
            _textLayer?.frame = CGRect(x: textAlleyWidth, y: textAlleyWidth, width: boxSize.width - textAlleyWidth, height: boxSize.height - textAlleyWidth)
        }

        // place buttons
        var rc = viewRect
        for i in 0..<(_buttonList?.count ?? 0) {
            // place button
            let button = _buttonList?[i]
            var buttonRect: CGRect = .zero
            buttonRect.size = button?.frame.size ?? CGSize.zero
            if labelOnBottom {
                buttonRect.origin = CGPoint(
                    x: viewRect.size.width / 2 + buttonHorzOffset,
                    y: CGFloat(i) * buttonVerticalSpacing)
            } else {
                let x = viewRect.size.width / 2 + buttonHorzOffset
                let y = viewRect.size.height + CGFloat(i - (_buttonList?.count ?? 0) / 2) * buttonVerticalSpacing + 5
                buttonRect.origin = CGPoint( x: x, y: y)
            }
            button?.frame = buttonRect

            // place line to button
            let line = _lineLayers?[i]
            let buttonPath = CGMutablePath()
            var start = CGPoint(x: Double(viewRect.size.width / 2), y: Double(labelOnBottom ? topGap : viewRect.size.height))
            var end = CGPoint(x: Double(buttonRect.origin.x + buttonRect.size.width / 2), y: Double(buttonRect.origin.y + buttonRect.size.height / 2))
            let dx = Double(end.x - start.x)
            let dy = Double(end.y - start.y)
            let dist = hypot(dx, dy)
            start.x += CGFloat(15 * dx / dist)
            start.y += CGFloat(15 * dy / dist)
            end.x -= CGFloat(15 * dx / dist)
            end.y -= CGFloat(15 * dy / dist)
            buttonPath.move(to: CGPoint(x: start.x, y: start.y), transform: .identity)
            buttonPath.addLine(to: CGPoint(x: end.x, y: end.y), transform: .identity)
            line?.path = buttonPath

            // get union of subviews
            rc = rc.union(buttonRect)
        }

        placeholderLayer?.position = CGPoint(x: viewRect.size.width / 2, y: labelOnBottom ? topGap : viewRect.size.height)

        if labelOnBottom {
            frame = CGRect(x: arrowPoint.x - viewRect.size.width / 2, y: arrowPoint.y - topGap, width: rc.size.width, height: rc.size.height)
        } else {
            frame = CGRect(x: arrowPoint.x - viewRect.size.width / 2, y: arrowPoint.y - viewRect.size.height, width: rc.size.width, height: rc.size.height)
        }
    }
    
    @objc func buttonPress(_ sender: UIButton) {
        var index: Int? = nil
        index = _buttonList?.firstIndex(of: sender) ?? NSNotFound
        assert(index != NSNotFound)
        let callback: (() -> Void)? = _callbackList?[index ?? 0]
        callback?()
    }

    func add(_ button: UIButton?, callback: @escaping () -> Void) {
        assert(button != nil && callback != nil)
        let line = CAShapeLayer()
        if _buttonList == nil {
            _buttonList = [button].compactMap { $0 }
            _callbackList = [callback]
            _lineLayers = [line]
        } else {
            if let button = button {
                _buttonList?.append(button)
            }
            _callbackList?.append(callback)
            _lineLayers?.append(line)
        }
        line.lineWidth = 2.0
        line.strokeColor = UIColor.white.cgColor
        line.shadowColor = UIColor.black.cgColor
        line.shadowRadius = 5
        _shapeLayer?.addSublayer(line)

        if let button = button {
            addSubview(button)
        }
        button?.addTarget(self, action: #selector(buttonPress(_:)), for: .touchUpInside)

        setNeedsLayout()
    }

    func animateMove(from startPos: CGPoint) {
        layoutIfNeeded()

        let posA = startPos
        let posC = layer.position
        let posB = CGPoint(x: Double(posC.x), y: Double(posA.y))

        let path = CGMutablePath()
        path.move(to: CGPoint(x: posA.x, y: posA.y), transform: .identity)
        path.addQuadCurve(to: CGPoint(x: posC.x, y: posC.y), control: CGPoint(x: posB.x, y: posB.y), transform: .identity)

        var theAnimation: CAKeyframeAnimation?
        theAnimation = CAKeyframeAnimation(keyPath: "position")
        theAnimation?.path = path
        theAnimation?.timingFunction = CAMediaTimingFunction(name: .easeOut)
        theAnimation?.repeatCount = 0
        theAnimation?.isRemovedOnCompletion = true
        theAnimation?.fillMode = .both
        theAnimation?.duration = 0.5

        // let us get notified when animation completes
        theAnimation?.delegate = self

        layer.position = posC
        if let theAnimation = theAnimation {
            layer.add(theAnimation, forKey: "animatePosition")
        }
    }

    @objc func draggingGesture(_ gesture: UIPanGestureRecognizer) {
        let newCoord = gesture.location(in: gesture.view)
        var dX: CGFloat = 0
        var dY: CGFloat = 0

        if gesture.state == .began {
            _panCoord = newCoord
        } else {
            dX = newCoord.x - _panCoord.x
            dY = newCoord.y - _panCoord.y
            arrowPoint = CGPoint(x: arrowPoint.x + dX, y: arrowPoint.y + dY)

            let newCenter = CGPoint(x: Double(center.x + dX), y: Double(center.y + dY))
            gesture.view?.center = newCenter
        }

        if let dragCallback = dragCallback {
            dragCallback(gesture.state, dX, dY, gesture)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
