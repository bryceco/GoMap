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


struct TextLoc {
	var pos: CGPoint
	var angle: CGFloat
	var length: CGFloat
}

class PathPoints {

	var _points : [CGPoint]
	var _length : CGFloat? = nil

	init(WithPath path:CGPath)
	{
		// get line segments
		_points = Array(repeating: CGPoint.zero, count: CGPathPointCount( path ))
		_points.withUnsafeMutableBufferPointer { a in
			_ = CGPathGetPoints( path, a.baseAddress )
		}
	}

	func eliminatePointsOnStraightSegments()
	{
		if _points.count < 3 {
			return
		}
		var dst = 1
		for src in 1 ..< _points.count-1 {
			var dir : OSMPoint = OSMPoint( x: Double(_points[src+1].x - _points[dst-1].x),
										   y: Double(_points[src+1].y - _points[dst-1].y) )
			dir = UnitVector(dir);
			let dist = DistanceFromLineToPoint( OSMPointFromCGPoint(_points[dst-1]), dir, OSMPointFromCGPoint(_points[src]) );
			if ( dist < 2.0 ) {
				// essentially a straight line, so remove point
			} else {
				_points[ dst ] = _points[ src ]
				dst += 1
			}
		}
		_points[ dst ] = _points.last!
		_points.removeSubrange(dst+1 ..< _points.count)
		_length = nil
	}

	func reverse()
	{
		_points.reverse()
	}

	func length() -> CGFloat
	{
		if ( _length == nil ) {
			var len : CGFloat = 0.0;
			for i in 1 ..< _points.count {
				len += hypot( _points[i].x - _points[i-1].x,
							  _points[i].y - _points[i-1].y )
			}
			_length = len
		}
		return _length!
	}

	func points() -> [CGPoint]
	{
		return _points
	}

	func resetOffset()
	{
		_segment = 0
		_offset = 0.0
	}

	func advanceOffsetBy(_ delta2 : CGFloat ) -> Bool
	{
		var delta = delta2
		var previous = _points[ _segment ]
		while _segment < _points.count-1 {
			let pt = _points[ _segment+1 ]
			let len = hypot(pt.x - previous.x, pt.y - previous.y)
			if _offset+delta < len {
				_offset += delta
				return true
			}
			delta -= len - _offset
			_segment += 1
			_offset = 0.0
			previous = pt
		}
		return false
	}

	func positionAndAngleForOffset(baseline:CGFloat) -> TextLoc?
	{
		if _segment >= _points.count-1 {
			return nil
		}
		let p1 = _points[ _segment ]
		let p2 = _points[ _segment+1 ]
		var dx = p2.x - p1.x
		var dy = p2.y - p1.y
		let len = hypot(dx,dy)
		let a = atan2(dy,dx)
		dx /= len;
		dy /= len;
		let baselineOffset2 = CGPoint( x: dy * baseline, y: -dx * baseline )
		return TextLoc(pos: CGPoint(x: p1.x + _offset * dx + baselineOffset2.x,
									y: p1.y + _offset * dy + baselineOffset2.y),
								angle: a,
								length: len - _offset)
	}

	var _offset : CGFloat = 0.0
	var _segment : Int = 0
	func setOffset( offset:CGFloat )
	{
		_offset = offset

	}
}

class GlyphLayer : CALayer {
	let run:CTRun
	let glyphs:[CGGlyph]
	let positions:[CGPoint]

	init(WithRun run:CTRun, glyphs:[CGGlyph], advances:[CGSize], range:NSRange)
	{
		self.run = run
		let slice = range.location ..< range.location+range.length
		self.glyphs = Array(glyphs[slice])
		let size = advances[slice].reduce(CGSize.zero) { (a, b) -> CGSize in
			return CGSize( width: a.width + b.width, height: max(a.height,b.height) )
		}
		var sum:CGFloat = 0.0
		positions = advances[slice].map({ (a) -> CGPoint in
			let result = sum
			sum += a.width
			return CGPoint(x: result, y: 0.0)
		})

		super.init()
		self.bounds = CGRect(origin: CGPoint.zero, size: size)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func draw(in context: CGContext) {
		context.saveGState()
		context.textMatrix = CGAffineTransform.identity
		context.scaleBy(x: 1.0, y: -1.0);
		context.showGlyphs(glyphs, at: positions)
		context.restoreGState()
	}
}



@objc class MyTextLayer : CATextLayer
{
	override func draw(in ctx: CGContext) {
		super.draw(in: ctx)
	}
}

@objc class CurvedTextLayer : CALayer {

static let uiFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.subheadline)
static let cgFont = CGFont(uiFont.fontName as CFString)!
static let layerCache 	= { () -> NSCache<NSString, CATextLayer> in
							NotificationCenter.default.addObserver(self, selector: #selector(CurvedTextLayer.fontSizeDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
							let c = NSCache<NSString, CATextLayer>()
							c.countLimit = 100
							return c
							}()

@objc static var whiteOnBlack: Bool = true {
	 willSet(newValue) {
		if ( newValue != whiteOnBlack ) {
			CurvedTextLayer.layerCache.removeAllObjects()
		}
	}
}

@objc static var shouldRasterize = false

let pathPoints : PathPoints
let attrString : NSAttributedString
let ctLine : CTLine
let textSize : CGRect
let runs : [CTRun]



private init(WithAttrString attrString:NSAttributedString, frame:CGRect, ctLine:CTLine, textSize:CGRect, runs:[CTRun], pathPoints:PathPoints)
{
	self.attrString = attrString
	self.ctLine = ctLine
	self.textSize = textSize
	self.runs = runs
	self.pathPoints = pathPoints

	super.init()

	self.contentsScale 		= UIScreen.main.scale;
	self.actions			= [ "position": NSNull() ]
	self.anchorPoint		= CGPoint.zero
	self.shouldRasterize   	= shouldRasterize
	self.frame				= frame
	self.setNeedsDisplay()
}

@objc static public func layer(WithString string:NSString, alongPath path:CGPath) -> CurvedTextLayer?
{
	// get text size
	let textColor = CurvedTextLayer.whiteOnBlack ? UIColor.white : UIColor.black
	let attrString = NSAttributedString.init(string: string as String,
											 attributes: [ NSAttributedString.Key.font: CurvedTextLayer.uiFont,
														   NSAttributedString.Key.foregroundColor: textColor.cgColor ])
	let ctLine = CTLineCreateWithAttributedString( attrString )
	let textSize = CTLineGetBoundsWithOptions( ctLine, CTLineBoundsOptions.useGlyphPathBounds )

	// get path length
	let pathPoints = PathPoints(WithPath: path)

	if textSize.width+8 >= pathPoints.length() {
		return nil	// doesn't fit
	}

	guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { return nil }
	guard let firstRun = runs.first else { return nil }
	let isRTL = (CTRunGetStatus(firstRun).rawValue & CTRunStatus.rightToLeft.rawValue) != 0
	if isRTL {
		pathPoints.reverse()
	}
	let frame = path.boundingBox.insetBy(dx: -20, dy: -20)

	return CurvedTextLayer.init(WithAttrString: attrString, frame:frame, ctLine: ctLine, textSize: textSize, runs: runs, pathPoints: pathPoints)
}

required init?(coder: NSCoder) {
	fatalError("init(coder:) has not been implemented")
}

@objc class private func fontSizeDidChange()
{
	CurvedTextLayer.layerCache.removeAllObjects()
}


func drawInContext(_ context: CGContext) -> Bool
{
	let textColor = CurvedTextLayer.whiteOnBlack ? UIColor.white : UIColor.black
	context.setFont(CurvedTextLayer.cgFont)
	context.setFontSize(CurvedTextLayer.uiFont.pointSize)
	context.setFillColor(textColor.cgColor)

	guard pathPoints.advanceOffsetBy( (pathPoints.length() - textSize.width) / 2 ) else { return false }

	for run : CTRun in runs {

		// get glyphs for run
		let glyphCount = CTRunGetGlyphCount(run)
		var runGlyphs = Array(repeating: CGGlyph.zero, count: glyphCount)
		runGlyphs.withUnsafeMutableBufferPointer { buffer in
			CTRunGetGlyphs(run, CFRangeMake(0,glyphCount), buffer.baseAddress!)
		}

		// get advances for run
		var runAdvances = Array(repeating: CGSize.zero, count: glyphCount)
		runAdvances.withUnsafeMutableBufferPointer { buffer in
			CTRunGetAdvances(run, CFRangeMake(0,glyphCount), buffer.baseAddress!)
		}

		for glyphIndex in 0 ..< glyphCount {

			context.saveGState()

			guard let loc = pathPoints.positionAndAngleForOffset(baseline: 3) else { return false }
			context.textMatrix = CGAffineTransform.identity
			context.scaleBy(x: 1.0, y: -1.0);

			let p = CGPoint(x: loc.pos.x - self.position.x, y: loc.pos.y - self.position.y )
			context.translateBy(x: p.x, y: -p.y )
			context.rotate(by: -loc.angle)

			context.showGlyphs([runGlyphs[glyphIndex]], at: [CGPoint.zero])

			guard pathPoints.advanceOffsetBy( runAdvances[glyphIndex].width ) else { return false }

			context.restoreGState()
		}
	}
	return true
}

@objc override func draw(in context: CGContext)
{
	_ = drawInContext( context )
}

@objc static func layerWithString(_ string: String, whiteOnBlock whiteOnBlack: Bool) -> CALayer?
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

} // end class
