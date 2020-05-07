//
//  CurvedTextLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/6/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore

@objc class CurvedTextLayer : CALayer {

	@objc public static let shared = CurvedTextLayer()

	let layerCache 			= NSCache<NSString, CATextLayer>()
	let framesetterCache 	= NSCache<NSString, CTFramesetter>()
	let textSizeCache 		= NSCache<NSString, NSValue>()
	var cachedColorIsWhiteOnBlack = true;
	
override init()
{
	super.init()
	layerCache.countLimit		= 100
	framesetterCache.countLimit = 100;
	textSizeCache.countLimit	= 100;

	NotificationCenter.default.addObserver(self, selector: #selector(fontSizeDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
}

deinit {
	NotificationCenter.default.removeObserver(self)
}

required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
}

@objc private func fontSizeDidChange()
{
	layerCache.removeAllObjects()
	textSizeCache.removeAllObjects()
	framesetterCache.removeAllObjects()
}


@objc func layerWithString(_ string: String, whiteOnBlock whiteOnBlack: Bool) -> CALayer?
{
	let MAX_TEXT_WIDTH : CGFloat = 100.0

	// Don't cache these here because they are cached by the objects they are attached to
	let layer = CATextLayer()
	layer.contentsScale = UIScreen.main.scale;

	let font = UIFont.preferredFont(forTextStyle: .subheadline)

	let textColor   = whiteOnBlack ? UIColor.white : UIColor.black
	let shadowColor = whiteOnBlack ? UIColor.black : UIColor.white

	let attrString = NSAttributedString(string: string,
										attributes: [
											NSAttributedString.Key.foregroundColor: textColor.cgColor,
											NSAttributedString.Key.font: font])

	let framesetter = CTFramesetterCreateWithAttributedString(attrString)

	var bounds = CGRect.zero
	bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
															   CFRangeMake(0, 0),
															   nil,
															   CGSize(width: MAX_TEXT_WIDTH, height: CGFloat.greatestFiniteMagnitude),
															   nil)
	bounds = bounds.insetBy( dx: -3, dy: -1 );
	bounds.size.width  = 2 * ceil( bounds.size.width/2 );	// make divisible by 2 so when centered on anchor point at (0.5,0.5) everything still aligns
	bounds.size.height = 2 * ceil( bounds.size.height/2 );
	layer.bounds = bounds;

	layer.string			= attrString;
	layer.truncationMode	= CATextLayerTruncationMode.none;
	layer.isWrapped			= true;
	layer.alignmentMode		= CATextLayerAlignmentMode.left;	// because our origin is -3 this is actually centered

	let shadowPath			= CGPath(rect: bounds, transform: nil)
	layer.shadowPath		= shadowPath;
	layer.shadowColor		= shadowColor.cgColor;
	layer.shadowRadius		= 0.0;
	layer.shadowOffset		= CGSize.zero
	layer.shadowOpacity		= 0.3;

	return layer;
}


private func EliminatePointsOnStraightSegments(points: inout [CGPoint])
{
	if points.count < 3 {
		return
	}
	var dst = 1
	for src in 1 ..< points.count-1 {
		var dir : OSMPoint = OSMPoint( x: Double(points[src+1].x-points[dst-1].x),
									   y: Double(points[src+1].y-points[dst-1].y) )
		dir = UnitVector(dir);
		let dist = DistanceFromLineToPoint( OSMPointFromCGPoint(points[dst-1]), dir, OSMPointFromCGPoint(points[src]) );
		if ( dist < 2.0 ) {
			// essentially a straight line, so remove point
		} else {
			points[ dst ] = points[ src ]
			dst += 1
		}
	}
	points[ dst ] = points.last!
	points.removeSubrange(dst+1..<points.count)
}


private func PositionAndAngleForOffset( points: [CGPoint], offset: CGFloat, baselineOffsetDistance: CGFloat, pPos: inout CGPoint, pAngle: inout CGFloat, pLength: inout CGFloat) -> Bool
{
	var	previous = points[0]
	var newOffset = offset;

	for index in 1 ..< points.count {
		let pt = points[ index ]
		var dx = pt.x - previous.x
		var dy = pt.y - previous.y
		let len = hypot(dx,dy)
		let a = atan2(dy,dx)

		if newOffset < len {
			// found it
			dx /= len;
			dy /= len;
			let baselineOffset2 = CGPoint( x: dy * baselineOffsetDistance, y: -dx * baselineOffsetDistance );

			pPos = CGPoint(x: previous.x + newOffset * dx + baselineOffset2.x, y: previous.y + newOffset * dy + baselineOffset2.y)
			pAngle = a;
			pLength = len - newOffset;
			return true;
		}
		newOffset -= len;
		previous = pt;
	}
	pLength = 0;
	return false;
}

private func IsRTL(_ typesetter: CTTypesetter) -> Bool
{
	let fullLine = CTTypesetterCreateLine(typesetter, CFRangeMake(CFIndex(0), CFIndex(0)))

	let runs = CTLineGetGlyphRuns(fullLine) as? [CTRun]
	if (runs?.count ?? 0) > 0 {
		if let run = runs?[0] {
			let status : CTRunStatus = CTRunGetStatus(run)
			if (status.rawValue & CTRunStatus.rightToLeft.rawValue) != 0 {
				return true
			}
		}
	}
	return false
}

private func framesetter(for attrString: NSAttributedString) -> CTFramesetter
{
	if let framesetter = framesetterCache.object(forKey: attrString.string as NSString) {
		return framesetter
	}
	let framesetter = CTFramesetterCreateWithAttributedString(attrString)
	framesetterCache.setObject(framesetter, forKey: attrString.string as NSString)
	return framesetter
}

private func sizeOfText(_ string: NSAttributedString) -> CGSize
{
	if let size = textSizeCache.object(forKey: string.string as NSString) {
		return size.cgSizeValue
	}

	let framesetter = self.framesetter(for: string)
	let suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(CFIndex(0), CFIndex(0)), nil, CGSize(width: 70, height: CGFloat.greatestFiniteMagnitude), nil)
	let value = NSValue(cgSize: suggestedSize)
	textSizeCache.setObject(value, forKey: string.string as NSString)
	return suggestedSize
}

private func getCachedLayer(for string: String, whiteOnBlack: Bool, shouldRasterize: Bool) -> CATextLayer?
{
	if cachedColorIsWhiteOnBlack != whiteOnBlack {
		layerCache.removeAllObjects()
		cachedColorIsWhiteOnBlack = whiteOnBlack
		return nil
	}
	return layerCache.object(forKey: string as NSString)
}

@objc func layersWithString(_ string: NSString, alongPath path: CGPath, whiteOnBlock whiteOnBlack: Bool, shouldRasterize: Bool) -> [CALayer]?
{
	let uiFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.subheadline)

	let textColor = whiteOnBlack ? UIColor.white : UIColor.black;
	let attrString = NSAttributedString.init(string: string as String,
											 attributes: [ NSAttributedString.Key.font: uiFont,
														   NSAttributedString.Key.foregroundColor: textColor.cgColor])
	let framesetter = self.framesetter(for: attrString)
	let charCount = string.length
	let typesetter = CTFramesetterGetTypesetter(framesetter)

//	NSLog(@"\"%@\"",string);

	// get line segments
	var pathPoints = Array(repeating: CGPoint.zero, count: CGPathPointCount( path ))
	pathPoints.withUnsafeMutableBufferPointer { a in
		_ = CGPathGetPoints( path, a.baseAddress )
    }
	EliminatePointsOnStraightSegments( points: &pathPoints )
	if ( pathPoints.count < 2 ) {
		return nil;
	}

	let isRTL = IsRTL( typesetter )
	if ( isRTL ) {
		pathPoints.reverse()
	}

	// center the text along the path
	var pathLength : CGFloat = 0.0;
	for i in 1 ..< pathPoints.count {
		pathLength += hypot( pathPoints[i].x - pathPoints[i-1].x, pathPoints[i].y - pathPoints[i-1].y )
	}
	let textSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
																CFRangeMake(0,string.length),
																nil,
																CGSize.zero,
																nil)
	if textSize.width+8 >= pathLength {
		return nil;
	}
	let offset = (pathLength - textSize.width) / 2;

	var layers : [CALayer] = []
	let lineHeight = uiFont.lineHeight
	var currentCharacter : CFIndex = 0
	var currentPixelOffset = offset
	while currentCharacter < charCount {

		if ( currentCharacter > 0 && isRTL ) {
			// doesn't fit on one segment so give up
			return  nil
		}

		// get the number of characters that fit in the current path segment and create a text layer for it
		var pos = CGPoint.zero
		var angle : CGFloat = 0
		var length : CGFloat = 0
		if !PositionAndAngleForOffset(points: pathPoints,
									  offset: currentPixelOffset,
									  baselineOffsetDistance: lineHeight,
									  pPos: &pos, pAngle: &angle, pLength: &length)
		{
			return nil;
		}
		let count = CTTypesetterSuggestLineBreak( typesetter, currentCharacter, Double(length) )

		let s = string.substring(with: NSMakeRange(currentCharacter, count))
		let angleString = String(format: "%.4f", angle)
		let cacheKey : String = "\(s):\(angleString)"
		var layer = self.getCachedLayer(for: cacheKey, whiteOnBlack: whiteOnBlack, shouldRasterize: shouldRasterize)

		var pixelLength : CGFloat = 0
		if layer == nil {
			layer = CATextLayer()
			if let layer = layer {
				layer.contentsScale 	= UIScreen.main.scale;
				layer.actions			= [ "position": NSNull() ]
				layer.string			= attrString.attributedSubstring(from: NSMakeRange(currentCharacter,count))
				var bounds = CGRect.zero
				bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
																		   CFRangeMake(currentCharacter,count),
																		   nil,
																		   CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
																		   nil);
				layer.actions = [ "position": NSNull() ]
				pixelLength = bounds.size.width;
				layer.bounds			= bounds;
				if ( isRTL ) {
					pos.x += cos(angle)*pixelLength;
					pos.y += sin(angle)*pixelLength;
					pos.x -= sin(angle)*2*lineHeight;
					pos.y += cos(angle)*2*lineHeight;
					angle -= CGFloat.pi
				}
				layer.setAffineTransform( CGAffineTransform(rotationAngle: angle))
				layer.position			= pos;
				layer.anchorPoint		= CGPoint.zero
				layer.truncationMode	= .none
				layer.isWrapped			= false
				layer.alignmentMode		= .center
				layer.shouldRasterize   = shouldRasterize;
				layer.contentsScale		= UIScreen.main.scale;

				let	shadowPath	= CGPath(rect: bounds, transform: nil)
				layer.shadowColor		= whiteOnBlack ? UIColor.black.cgColor : UIColor.white.cgColor;
				layer.shadowRadius		= 0.0;
				layer.shadowOffset		= CGSize.zero
				layer.shadowOpacity		= 0.3;
				layer.shadowPath		= shadowPath;

				layerCache.setObject(layer, forKey:cacheKey as NSString)
			} else {
				return nil
			}

		} else {
			pixelLength	= layer!.bounds.size.width;
			if ( isRTL ) {
				pos.x += cos(angle)*pixelLength;
				pos.y += sin(angle)*pixelLength;
				pos.x -= sin(angle)*2*lineHeight;
				pos.y += cos(angle)*2*lineHeight;
				angle -= CGFloat.pi
			}
			layer!.position	= pos;
		}

//		NSLog(@"-> \"%@\"",[layer.string string]);

		layers.append( layer! )

		currentCharacter 	+= count
		currentPixelOffset 	+= pixelLength

		if string.character(at: currentCharacter-1) == unichar(" ") {
			currentPixelOffset += 8;	// add room for space which is not included in framesetter size
		}
	}
	return layers
}

} // end class
