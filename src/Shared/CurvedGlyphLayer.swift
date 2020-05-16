//
//  CurvedGlyphLayer.swift
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
	private var offset : CGFloat = 0.0
	private var segment : Int = 0

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
		segment = 0
		offset = 0.0
	}

	func advanceOffsetBy(_ delta2 : CGFloat ) -> Bool
	{
		var delta = delta2
		var previous = points[ segment ]
		while segment < points.count-1 {
			let pt = points[ segment+1 ]
			let len = hypot(pt.x - previous.x, pt.y - previous.y)
			if offset+delta < len {
				offset += delta
				return true
			}
			delta -= len - offset
			segment += 1
			offset = 0.0
			previous = pt
		}
		return false
	}

	func positionAndAngleForCurrentOffset(withBaselineOffset baseline:CGFloat) -> TextLoc?
	{
		if segment >= points.count-1 {
			return nil
		}
		let p1 = points[ segment ]
		let p2 = points[ segment+1 ]
		var dx = p2.x - p1.x
		var dy = p2.y - p1.y
		let len = hypot(dx,dy)
		let a = atan2(dy,dx)
		dx /= len;
		dy /= len;
		let baselineOffset2 = CGPoint( x: dy * baseline, y: -dx * baseline )
		return TextLoc(pos: CGPoint(x: p1.x + offset * dx + baselineOffset2.x,
									y: p1.y + offset * dy + baselineOffset2.y),
								angle: a,
								length: len - offset)
	}
}



class GlyphList {
	let glyphs : [CGGlyph]
	let advances : [CGSize]
	init(glyphs:[CGGlyph],advances:[CGSize])
	{
		self.glyphs = glyphs
		self.advances = advances
	}
}

class StringGlyphs {

	// static stuff
	public static var uiFont = UIFont.preferredFont(forTextStyle: .subheadline)

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




@objc class CurvedGlyphLayer : CALayer {

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
#if DEBUG
	private var string : NSString?
#endif

	// calling init() on a CALayer subclass from Obj-C doesn't work on iOS 9
	private init(withGlyphs stringGlyphs:StringGlyphs, frame:CGRect, pathPoints:PathPoints)
	{
		self.stringGlyphs = stringGlyphs
		self.pathPoints = pathPoints
#if DEBUG
		self.string = nil
#endif
		super.init()

		self.contentsScale 		= UIScreen.main.scale;
		self.actions			= [ "position": NSNull() ]
		self.anchorPoint		= CGPoint.zero
		self.frame				= frame
		self.setNeedsDisplay()
	}

	@objc static public func layer(WithString string:NSString, alongPath path:CGPath) -> CurvedGlyphLayer?
	{
		guard let glyphRuns = StringGlyphs.glyphsForString(string:string) else { return nil }
		let pathPoints = PathPoints(WithPath: path)

		if glyphRuns.rect.size.width+8 >= pathPoints.length() {
			return nil	// doesn't fit
		}

		let frame = path.boundingBox.insetBy(dx: -20, dy: -20)

		let layer = CurvedGlyphLayer.init(withGlyphs:glyphRuns, frame:frame, pathPoints: pathPoints)
#if DEBUG
		layer.string = string
#endif
		return layer
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

		let textColor = CurvedGlyphLayer.whiteOnBlack ? UIColor.white : UIColor.black
		let backColor = (!CurvedGlyphLayer.whiteOnBlack ? UIColor.white : UIColor.black).withAlphaComponent(0.3)

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

	@objc func glyphLayers() -> [GlyphLayer]?
	{
#if DEBUG
		if self.string!.isEqual("15th Avenue") {
			print( "\(string!)" )
		}
#endif

		pathPoints.resetOffset()
		guard pathPoints.advanceOffsetBy( (pathPoints.length() - stringGlyphs.rect.width) / 2 ) else { return nil }

		let textColor = CurvedGlyphLayer.whiteOnBlack ? UIColor.white : UIColor.black
		let backColor = (!CurvedGlyphLayer.whiteOnBlack ? UIColor.white : UIColor.black).withAlphaComponent(0.3)

		let baselineOffset = 3 - stringGlyphs.rect.origin.y

		var layers : [GlyphLayer] = []

		for runIndex in 0 ..< stringGlyphs.runGlyphs.count {

			let runGlyphs = stringGlyphs.runGlyphs[runIndex]
			let runFont = stringGlyphs.runFonts[runIndex]

			var glyphIndex = 0
			while glyphIndex < runGlyphs.glyphs.count {
				var layerGlyphs : [CGGlyph] = []
				var layerPositions : [CGPoint] = []
				var position : CGFloat = 0.0
				var start : TextLoc? = nil

				while glyphIndex < runGlyphs.glyphs.count {

					guard let loc = pathPoints.positionAndAngleForCurrentOffset(withBaselineOffset: baselineOffset) else {
						break
					}
					if start == nil {
						start = loc
					} else if loc.angle != start!.angle {
						break
					}

					let glyphWidth = runGlyphs.advances[glyphIndex].width
					layerGlyphs.append(runGlyphs.glyphs[glyphIndex])
					layerPositions.append(CGPoint(x: position, y: 0.0))
					position += glyphWidth

					_ = pathPoints.advanceOffsetBy( glyphWidth )
					glyphIndex += 1
				}
				layerPositions.append(CGPoint(x: position, y: 0.0))

				let glyphLayer = GlyphLayer.layer(withFont: runFont,
												  foreColor: textColor,
												  backColor: backColor,
												  glyphs: layerGlyphs,
												  positions:layerPositions)
				glyphLayer.position = start!.pos
				glyphLayer.anchorPoint = CGPoint(x:0,y:1)
				glyphLayer.setAffineTransform( CGAffineTransform(rotationAngle: start!.angle) )

				layers.append(glyphLayer)

				layerGlyphs.removeAll()
				layerPositions.removeAll()
			}
		}
		return layers
	}

	// return a non-curved rectangular layer
	@objc static func layerWithString(_ string: String, whiteOnBlock whiteOnBlack: Bool) -> CALayer?
	{
		let MAX_TEXT_WIDTH : CGFloat = 100.0

		// Don't cache these here because they are cached by the objects they are attached to
		let layer = CATextLayer()
		layer.contentsScale = UIScreen.main.scale;

		let font = StringGlyphs.uiFont
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

		layer.backgroundColor	= shadowColor.withAlphaComponent(0.3).cgColor;

		return layer;
	}
}



class GlyphLayer : CALayer {

	private static let cache 	= { () -> NSCache<NSData, GlyphLayer> in
		NotificationCenter.default.addObserver(StringGlyphs.self, selector: #selector(GlyphLayer.fontSizeDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
								let c = NSCache<NSData, GlyphLayer>()
								c.countLimit = 200
								return c
								}()

	private let glyphs:[CGGlyph]
	private let positions:[CGPoint]
	private let font:CTFont

	private init(withCopy copy:GlyphLayer) {
		self.glyphs 			= copy.glyphs
		self.positions 			= copy.positions
		self.font 				= copy.font
		super.init()
		self.contentsScale 		= copy.contentsScale
		self.anchorPoint		= copy.anchorPoint
		self.bounds				= copy.bounds
		self.backgroundColor	= copy.backgroundColor
		self.contents 			= copy.contents	// use existing backing store so we don't have to redraw
	}

	private func copy() -> GlyphLayer {
		return GlyphLayer(withCopy: self)
	}

	@objc static func fontSizeDidChange() {
		cache.removeAllObjects()
	}

	@objc override func action(forKey event: String) -> CAAction? {
		// we don't want any animated actions
		return NSNull()
	}

	// calling init() on a CALayer subclass from Obj-C doesn't work on iOS 9
	private init(withFont font:CTFont, foreColor:UIColor, backColor:UIColor, glyphs:[CGGlyph], positions:[CGPoint])
	{
		self.glyphs = glyphs
		self.positions = positions
		self.font = font

		super.init()

		let size = CTFontGetBoundingBox( font ).size
		let descent = CTFontGetDescent( font )
		let bounds				= CGRect(x:0, y:descent, width: positions.last!.x, height: size.height)
		self.contentsScale 		= UIScreen.main.scale
		self.anchorPoint		= CGPoint.zero
		self.bounds				= bounds
		self.backgroundColor	= backColor.cgColor

		self.setNeedsDisplay()
	}

	static public func layer(withFont font:CTFont, foreColor:UIColor, backColor:UIColor, glyphs:[CGGlyph], positions:[CGPoint]) -> GlyphLayer
	{
		let key = glyphs.withUnsafeBytes { a in
			return NSData(bytes: a.baseAddress, length: a.count)
		}
		if let layer = cache.object(forKey: key) {
			return layer.copy()
		} else {
			let layer = GlyphLayer.init(withFont: font,
							   foreColor: foreColor,
							   backColor: backColor,
							   glyphs: glyphs,
							   positions: positions)
			cache.setObject(layer, forKey: key)
			return layer
		}
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func draw(in context: CGContext) {

		context.saveGState()
		context.textMatrix = CGAffineTransform.identity
		context.translateBy(x: 0, y: self.bounds.size.height)
		context.scaleBy(x: 1.0, y: -1.0);
		context.setFillColor(CurvedGlyphLayer.whiteOnBlack ? UIColor.white.cgColor : UIColor.black.cgColor)
		CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
		context.restoreGState()
	}
}

