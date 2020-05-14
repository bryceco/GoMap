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

	public var 	points : [CGPoint]
	private var _length : CGFloat? = nil
	private var _offset : CGFloat = 0.0
	private var _segment : Int = 0

	init(WithPath path:CGPath)
	{
		// get line segments
		points = Array(repeating: CGPoint.zero, count: CGPathPointCount( path ))
		points.withUnsafeMutableBufferPointer { a in
			_ = CGPathGetPoints( path, a.baseAddress )
		}
	}

	func eliminatePointsOnStraightSegments()
	{
		if points.count < 3 {
			return
		}
		var dst = 1
		for src in 1 ..< points.count-1 {
			var dir : OSMPoint = OSMPoint( x: Double(points[src+1].x - points[dst-1].x),
										   y: Double(points[src+1].y - points[dst-1].y) )
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
		points.removeSubrange(dst+1 ..< points.count)
		_length = nil
	}

	func length() -> CGFloat
	{
		if ( _length == nil ) {
			var len : CGFloat = 0.0;
			for i in 1 ..< points.count {
				len += hypot( points[i].x - points[i-1].x,
							  points[i].y - points[i-1].y )
			}
			_length = len
		}
		return _length!
	}

	func resetOffset()
	{
		_segment = 0
		_offset = 0.0
	}

	func advanceOffsetBy(_ delta2 : CGFloat ) -> Bool
	{
		var delta = delta2
		var previous = points[ _segment ]
		while _segment < points.count-1 {
			let pt = points[ _segment+1 ]
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

	func positionAndAngleForCurrentOffset(withBaselineOffset baseline:CGFloat) -> TextLoc?
	{
		if _segment >= points.count-1 {
			return nil
		}
		let p1 = points[ _segment ]
		let p2 = points[ _segment+1 ]
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
}



struct GlyphList {
	var glyphs : [CGGlyph]
	var advances : [CGSize]
}

class StringGlyphs {

	// static stuff
	public static var uiFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.subheadline)
	private static let cache 	= { () -> NSCache<NSString, StringGlyphs> in
		NotificationCenter.default.addObserver(StringGlyphs.self, selector: #selector(StringGlyphs.fontSizeDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
								let c = NSCache<NSString, StringGlyphs>()
								c.countLimit = 100
								return c
								}()

	@objc class private func fontSizeDidChange()
	{
		StringGlyphs.uiFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.subheadline)
		StringGlyphs.cache.removeAllObjects()
	}

	// objects

	public  let rect : CGRect
	public  let runGlyphs : [GlyphList]
	public	let runFonts : [CTFont]

	private init?(withString string:NSString)
	{
		let attrString = NSAttributedString.init(string:string as String,
												 attributes: [ NSAttributedString.Key.font: StringGlyphs.uiFont ])
		let ctLine = CTLineCreateWithAttributedString( attrString )
		guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { return nil }

		var glyphs = [GlyphList]()
		var fonts = [CTFont]()

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

			let attr = CTRunGetAttributes(run) as Dictionary
			let value = attr["NSFont" as NSString]
			let font = value as! CTFont
			fonts.append(font)

			glyphs.append(GlyphList(glyphs: runGlyphs, advances: runAdvances))
		}

		self.runGlyphs = glyphs
		self.runFonts = fonts
		self.rect = CTLineGetBoundsWithOptions(ctLine, CTLineBoundsOptions.useGlyphPathBounds)
	}

	static public func glyphsForString(string:NSString) -> StringGlyphs?
	{
		if let glyphs = StringGlyphs.cache.object(forKey:string) {
			return glyphs
		} else if let glyphs = StringGlyphs(withString:string) {
			StringGlyphs.cache.setObject(glyphs, forKey:string as NSString)
			return glyphs
		} else {
			return nil
		}
	}
}




@objc class CurvedTextLayer : CALayer {

	// static stuff
	@objc static var whiteOnBlack: Bool = true {
		willSet(newValue) {
			if ( newValue != whiteOnBlack ) {
			}
		}
	}

	// objects

	private let stringGlyphs : StringGlyphs
	private let pathPoints : PathPoints

	// calling init() on a CALayer subclass from Obj-C doesn't work on iOS 9
	private init(withGlyphs stringGlyphs:StringGlyphs, frame:CGRect, pathPoints:PathPoints)
	{
		self.stringGlyphs = stringGlyphs
		self.pathPoints = pathPoints

		super.init()

		self.contentsScale 		= UIScreen.main.scale;
		self.actions			= [ "position": NSNull() ]
		self.anchorPoint		= CGPoint.zero
		self.frame				= frame
		self.setNeedsDisplay()
	}

	@objc static public func layer(WithString string:NSString, alongPath path:CGPath) -> CurvedTextLayer?
	{
		guard let glyphRuns = StringGlyphs.glyphsForString(string:string) else { return nil }
		let pathPoints = PathPoints(WithPath: path)

		if glyphRuns.rect.size.width+8 >= pathPoints.length() {
			return nil	// doesn't fit
		}

		let frame = path.boundingBox.insetBy(dx: -20, dy: -20)

		return CurvedTextLayer.init(withGlyphs:glyphRuns, frame:frame, pathPoints: pathPoints)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc override func draw(in context: CGContext)
	{
		pathPoints.resetOffset()
		guard pathPoints.advanceOffsetBy( (pathPoints.length() - stringGlyphs.rect.width) / 2 ) else { return }

		context.textMatrix = CGAffineTransform.identity
		context.scaleBy(x: 1.0, y: -1.0);

		let textColor = CurvedTextLayer.whiteOnBlack ? UIColor.white : UIColor.black
		let backColor = (!CurvedTextLayer.whiteOnBlack ? UIColor.white : UIColor.black).withAlphaComponent(0.3)

		let baselineOffset = 3 - stringGlyphs.rect.origin.y

		for runIndex in 0 ..< stringGlyphs.runGlyphs.count {

			let runGlyphs = stringGlyphs.runGlyphs[runIndex]
			let runFont = stringGlyphs.runFonts[runIndex]

			for glyphIndex in 0 ..< runGlyphs.glyphs.count {

				guard let loc = pathPoints.positionAndAngleForCurrentOffset(withBaselineOffset: baselineOffset) else { return }
				let p = CGPoint(x: loc.pos.x - self.position.x, y: loc.pos.y - self.position.y )

				context.saveGState()
				context.translateBy(x: p.x, y: -p.y )
				context.rotate(by: -loc.angle)

				context.setFillColor(backColor.cgColor)
				let rc = CGRect(x: 0, y: stringGlyphs.rect.origin.y, width: runGlyphs.advances[glyphIndex].width, height: stringGlyphs.rect.height)
				context.fill(rc)

				context.setFillColor(textColor.cgColor)
				let glyph = runGlyphs.glyphs[glyphIndex]
				CTFontDrawGlyphs(runFont, [glyph], [CGPoint.zero], 1, context)
				context.restoreGState()

				guard pathPoints.advanceOffsetBy( runGlyphs.advances[glyphIndex].width ) else { return }
			}
		}
	}

	// return a non-curved rectangular layer
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
}



class GlyphLayer : CALayer {
	private let run:CTRun
	private let glyphs:[CGGlyph]
	private let positions:[CGPoint]

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

