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


private struct TextLoc {
	var pos: CGPoint
	var angle: CGFloat
	var length: CGFloat
}

private class PathPoints {

	public let 	points : [CGPoint]
	public let length : CGFloat
	private var offset : CGFloat = 0.0
	private var segment : Int = 0

	init(WithPath path:CGPath)
	{
		let count = CGPathPointCount( path )
		self.points = Array<CGPoint>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
			initializedCount = CGPathGetPoints( path, buffer.baseAddress )
		}
		var len : CGFloat = 0.0;
		for i in 1 ..< points.count {
			len += hypot( points[i].x - points[i-1].x,
						  points[i].y - points[i-1].y )
		}
		self.length = len
	}

	func resetOffset()
	{
		segment = 0
		offset = 0.0
	}

	func advanceOffsetBy(_ delta2 : CGFloat ) -> Bool
	{
		var delta = delta2
		while segment < points.count-1 {
			let len = hypot( points[segment+1].x - points[segment].x,
							 points[segment+1].y - points[segment].y )
			if offset+delta < len {
				offset += delta
				return true
			}
			delta -= len - offset
			segment += 1
			offset = 0.0
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



private class StringGlyphs {

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

	public let runs : [CTRun]
	public let rect : CGRect

	private init?(withString string:NSString)
	{
		let attrString = NSAttributedString.init(string:string as String,
												 attributes: [ NSAttributedString.Key.font: StringGlyphs.uiFont ])
		let ctLine = CTLineCreateWithAttributedString( attrString )
		guard let runs = (CTLineGetGlyphRuns(ctLine) as? [CTRun]) else {
			return nil
		}
		self.runs = runs
		self.rect = CTLineGetBoundsWithOptions( ctLine, CTLineBoundsOptions.useGlyphPathBounds )
	}

	public static func glyphsForRun( _ run : CTRun ) -> [CGGlyph]
	{
		let count = CTRunGetGlyphCount(run)
		let glyphs = Array<CGGlyph>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetGlyphs(run, CFRangeMake(0,count), buffer.baseAddress!)
			initializedCount = count
		}
		return glyphs
	}

	public static func advancesForRun( _ run : CTRun ) -> [CGSize]
	{
		let count = CTRunGetGlyphCount(run)
		let advances = Array<CGSize>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetAdvances(run, CFRangeMake(0,count), buffer.baseAddress!)
			initializedCount = count
		}
		return advances
	}

	public static func stringIndicesForRun( _ run : CTRun ) -> [CFIndex]
	{
		let count = CTRunGetGlyphCount(run)
		let advances = Array<CFIndex>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetStringIndices( run, CFRangeMake(0,count), buffer.baseAddress! )
			initializedCount = count
		}
		return advances
	}

	public static func fontForRun( _ run : CTRun ) -> CTFont
	{
		let attr = CTRunGetAttributes(run) as Dictionary
		let value = attr["NSFont" as NSString]
		let font = value as! CTFont
		return font
	}

	public static func stringGlyphsForString(string:NSString) -> StringGlyphs?
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


@objc class CurvedGlyphLayer : NSObject {

	// static stuff
	public static var foreColor = UIColor.white
	public static var backColor = UIColor.black
	@objc static var whiteOnBlack: Bool = true {
		willSet(newValue) {
			if ( newValue != whiteOnBlack ) {
				GlyphLayer.fontSizeDidChange()
				CurvedGlyphLayer.foreColor = newValue ? UIColor.white : UIColor.black
				CurvedGlyphLayer.backColor = (newValue ? UIColor.black : UIColor.white).withAlphaComponent(0.3)
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
	}

	@objc static public func layer(WithString string:NSString, alongPath path:CGPath) -> CurvedGlyphLayer?
	{
		guard let glyphRuns = StringGlyphs.stringGlyphsForString(string:string) else { return nil }
		let pathPoints = PathPoints(WithPath: path)

		if glyphRuns.rect.size.width+8 >= pathPoints.length {
			return nil	// doesn't fit
		}

		let frame = path.boundingBox.insetBy(dx: -20, dy: -20)
		let layer = CurvedGlyphLayer.init(withGlyphs:glyphRuns, frame:frame, pathPoints: pathPoints)
		return layer
	}

	@objc func glyphLayers() -> [GlyphLayer]?
	{
		pathPoints.resetOffset()
		guard pathPoints.advanceOffsetBy( (pathPoints.length - stringGlyphs.rect.width) / 2 ) else { return nil }

		let baselineOffset = 3 - stringGlyphs.rect.origin.y

		var layers : [GlyphLayer] = []

		for run in stringGlyphs.runs {

			let count 		= CTRunGetGlyphCount(run)
			let glyphs 		= StringGlyphs.glyphsForRun( run )
			let advances 	= StringGlyphs.advancesForRun( run )
			let runFont 	= StringGlyphs.fontForRun( run )

			var glyphIndex = 0
			while glyphIndex < count {
				var layerGlyphs : [CGGlyph] = []
				var layerPositions : [CGPoint] = []
				var position : CGFloat = 0.0
				var start : TextLoc? = nil

				while glyphIndex < count {

					guard let loc = pathPoints.positionAndAngleForCurrentOffset(withBaselineOffset: baselineOffset) else {
						break
					}
					if start == nil {
						start = loc
					} else if abs(loc.angle-start!.angle) > 5.0 * CGFloat.pi/180.0 {
						break
					}

					let glyphWidth = advances[glyphIndex].width
					layerGlyphs.append(glyphs[glyphIndex])
					layerPositions.append(CGPoint(x: position, y: 0.0))
					position += glyphWidth

					_ = pathPoints.advanceOffsetBy( glyphWidth )
					glyphIndex += 1
				}
				layerPositions.append(CGPoint(x: position, y: 0.0))

				guard let glyphLayer = GlyphLayer.layer(withFont: runFont,
												  glyphs: layerGlyphs,
												  positions:layerPositions) else {
													return nil
				}
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
	@objc static func layerWithString(_ string: String) -> CALayer?
	{
		let MAX_TEXT_WIDTH : CGFloat = 100.0

		// Don't cache these here because they are cached by the objects they are attached to
		let layer = CATextLayer()
		layer.contentsScale = UIScreen.main.scale;

		let font = StringGlyphs.uiFont

		let attrString = NSAttributedString(string: string,
											attributes: [
												NSAttributedString.Key.foregroundColor: CurvedGlyphLayer.foreColor.cgColor,
												NSAttributedString.Key.font: font])
		let framesetter = CTFramesetterCreateWithAttributedString(attrString)

		var bounds = CGRect.zero
		var maxWidth = MAX_TEXT_WIDTH
		while true {
			bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
																	   CFRangeMake(0, 0),
																	   nil,
																	   CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
																	   nil)
			if bounds.height < maxWidth {
				break
			}
			maxWidth *= 2
		}
		bounds = bounds.insetBy( dx: -3, dy: -1 );
		bounds.size.width  = 2 * ceil( bounds.size.width/2 );	// make divisible by 2 so when centered on anchor point at (0.5,0.5) everything still aligns
		bounds.size.height = 2 * ceil( bounds.size.height/2 );
		layer.bounds = bounds;

		layer.string			= attrString;
		layer.truncationMode	= CATextLayerTruncationMode.none;
		layer.isWrapped			= true;
		layer.alignmentMode		= CATextLayerAlignmentMode.left;	// because our origin is -3 this is actually centered

		layer.backgroundColor	= backColor.cgColor;

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
	private var inUse:Bool

	private init(withCopy copy:GlyphLayer) {
		self.glyphs 			= copy.glyphs
		self.positions 			= copy.positions
		self.font 				= copy.font
		self.inUse				= true
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

	override func removeFromSuperlayer() {
		inUse = false
		super.removeFromSuperlayer()
	}

	@objc static func fontSizeDidChange() {
		cache.removeAllObjects()
	}

	@objc override func action(forKey event: String) -> CAAction? {
		// we don't want any animated actions
		return NSNull()
	}

	// calling init() on a CALayer subclass from Obj-C doesn't work on iOS 9
	private init(withFont font:CTFont, glyphs:[CGGlyph], positions:[CGPoint])
	{
		self.glyphs 			= glyphs
		self.positions 			= positions
		self.font 				= font
		self.inUse 				= true
		super.init()
		let size = CTFontGetBoundingBox( font ).size
		let descent = CTFontGetDescent( font )
		let bounds				= CGRect(x:0, y:descent, width: positions.last!.x, height: size.height)
		self.contentsScale 		= UIScreen.main.scale
		self.anchorPoint		= CGPoint.zero
		self.bounds				= bounds
		self.backgroundColor	= CurvedGlyphLayer.backColor.cgColor

		self.setNeedsDisplay()
	}

	deinit
	{
		print("deinit")
	}

	static public func layer(withFont font:CTFont, glyphs:[CGGlyph], positions:[CGPoint]) -> GlyphLayer?
	{
		let key = glyphs.withUnsafeBytes { a in
			return NSData(bytes: a.baseAddress, length: a.count)
		}
		if let layer = cache.object(forKey: key) {
			if layer.inUse {
				return layer.copy()
			}
			layer.inUse = true
			return layer
		} else {
			let layer = GlyphLayer.init(withFont: font,
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
		context.setFillColor(CurvedGlyphLayer.foreColor.cgColor)
		CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
		context.restoreGState()
	}
}

