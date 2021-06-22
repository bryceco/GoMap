//
//  CurvedGlyphLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/6/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import CoreText
import Foundation
import QuartzCore
import UIKit

private struct TextLoc {
	var pos: CGPoint
	var angle: CGFloat
	var length: CGFloat
}

private final class PathPoints {
	public let points: [CGPoint]
	public let length: CGFloat
	private var offset: CGFloat = 0.0
	private var segment: Int = 0

	init(WithPath path: CGPath) {
		points = path.getPoints()
		var len: CGFloat = 0.0
		if points.count >= 2 {
			for i in 1..<points.count {
				len += hypot(points[i].x - points[i - 1].x,
				             points[i].y - points[i - 1].y)
			}
		}
		length = len
	}

	func resetOffset() {
		segment = 0
		offset = 0.0
	}

	func advanceOffsetBy(_ delta2: CGFloat) -> Bool {
		var delta = delta2
		while segment < points.count - 1 {
			let len = hypot(points[segment + 1].x - points[segment].x,
			                points[segment + 1].y - points[segment].y)
			if offset + delta < len {
				offset += delta
				return true
			}
			delta -= len - offset
			segment += 1
			offset = 0.0
		}
		return false
	}

	func positionAndAngleForCurrentOffset(withBaselineOffset baseline: CGFloat) -> TextLoc? {
		if segment >= points.count - 1 {
			return nil
		}
		let p1 = points[segment]
		let p2 = points[segment + 1]
		var dx = p2.x - p1.x
		var dy = p2.y - p1.y
		let len = hypot(dx, dy)
		let a = atan2(dy, dx)
		dx /= len
		dy /= len
		let baselineOffset2 = CGPoint(x: dy * baseline, y: -dx * baseline)
		return TextLoc(pos: CGPoint(x: p1.x + offset * dx + baselineOffset2.x,
		                            y: p1.y + offset * dy + baselineOffset2.y),
		               angle: a,
		               length: len - offset)
	}
}

private final class StringGlyphs {
	// static stuff
	public static var uiFont = UIFont.preferredFont(forTextStyle: .subheadline)

	private static let cache = { () -> NSCache<NSString, StringGlyphs> in
		let c = NSCache<NSString, StringGlyphs>()
		c.countLimit = 100
		NotificationCenter.default.addObserver(
			forName: UIContentSizeCategory.didChangeNotification,
			object: nil,
			queue: nil,
			using: { _ in
				StringGlyphs.uiFont = UIFont.preferredFont(forTextStyle: UIFont.TextStyle.subheadline)
				c.removeAllObjects()
			})
		return c
	}()

	// objects

	public let runs: [CTRun]
	public let rect: CGRect

	private init?(withString string: NSString) {
		let attrString = NSAttributedString(string: string as String,
		                                    attributes: [NSAttributedString.Key.font: StringGlyphs.uiFont])
		let ctLine = CTLineCreateWithAttributedString(attrString)
		guard let runs = (CTLineGetGlyphRuns(ctLine) as? [CTRun]) else {
			return nil
		}
		self.runs = runs
		rect = CTLineGetBoundsWithOptions(ctLine, CTLineBoundsOptions.useGlyphPathBounds)
	}

	public static func glyphsForRun(_ run: CTRun) -> [CGGlyph] {
		let count = CTRunGetGlyphCount(run)
		let glyphs = [CGGlyph](unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetGlyphs(run, CFRangeMake(0, count), buffer.baseAddress!)
			initializedCount = count
		}
		return glyphs
	}

	public static func advancesForRun(_ run: CTRun) -> [CGSize] {
		let count = CTRunGetGlyphCount(run)
		let advances = [CGSize](unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetAdvances(run, CFRangeMake(0, count), buffer.baseAddress!)
			initializedCount = count
		}
		return advances
	}

	public static func stringIndicesForRun(_ run: CTRun) -> [CFIndex] {
		let count = CTRunGetGlyphCount(run)
		let advances = [CFIndex](unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetStringIndices(run, CFRangeMake(0, count), buffer.baseAddress!)
			initializedCount = count
		}
		return advances
	}

	public static func fontForRun(_ run: CTRun) -> CTFont {
		let attr = CTRunGetAttributes(run) as Dictionary
		let value = attr["NSFont" as NSString]
		let font = value as! CTFont
		return font
	}

	public static func stringGlyphsForString(string: NSString) -> StringGlyphs? {
		if let glyphs = StringGlyphs.cache.object(forKey: string) {
			return glyphs
		} else if let glyphs = StringGlyphs(withString: string) {
			StringGlyphs.cache.setObject(glyphs, forKey: string as NSString)
			return glyphs
		} else {
			return nil
		}
	}
}

final class CurvedGlyphLayer {
	// static stuff
	public static var foreColor = UIColor.white
	public static var backColor = UIColor.black
	static var whiteOnBlack: Bool = true {
		willSet(newValue) {
			if newValue != whiteOnBlack {
				GlyphLayer.clearCache()
				CurvedGlyphLayer.foreColor = newValue ? UIColor.white : UIColor.black
				CurvedGlyphLayer.backColor = (newValue ? UIColor.black : UIColor.white).withAlphaComponent(0.3)
			}
		}
	}

	// objects

	private let stringGlyphs: StringGlyphs
	private let pathPoints: PathPoints

	// calling init() on a CALayer subclass from Obj-C doesn't work on iOS 9
	private init(withGlyphs stringGlyphs: StringGlyphs, frame _: CGRect, pathPoints: PathPoints) {
		self.stringGlyphs = stringGlyphs
		self.pathPoints = pathPoints
	}

	public static func layer(WithString string: NSString, alongPath path: CGPath) -> CurvedGlyphLayer? {
		guard let glyphRuns = StringGlyphs.stringGlyphsForString(string: string) else { return nil }
		let pathPoints = PathPoints(WithPath: path)

		if glyphRuns.rect.size.width + 8 >= pathPoints.length {
			return nil // doesn't fit
		}

		let frame = path.boundingBox.insetBy(dx: -20, dy: -20)
		let layer = CurvedGlyphLayer(withGlyphs: glyphRuns, frame: frame, pathPoints: pathPoints)
		return layer
	}

	func glyphLayers() -> [GlyphLayer]? {
		pathPoints.resetOffset()
		guard pathPoints.advanceOffsetBy((pathPoints.length - stringGlyphs.rect.width) / 2) else { return nil }

		let baselineOffset: CGFloat = 3

		var layers: [GlyphLayer] = []

		for run in stringGlyphs.runs {
			let runFont = StringGlyphs
				.fontForRun(run) // every run potentially has a different font, due to font substitution
			let glyphs = StringGlyphs.glyphsForRun(run)
			let advances = StringGlyphs.advancesForRun(run)
			let size = CTFontGetBoundingBox(runFont).size

			var glyphIndex = 0
			while glyphIndex < glyphs.count {
				var layerGlyphs: [CGGlyph] = []
				var layerPositions: [CGPoint] = []
				var position: CGFloat = 0.0
				var start: TextLoc?

				while glyphIndex < glyphs.count {
					guard let loc = pathPoints.positionAndAngleForCurrentOffset(withBaselineOffset: baselineOffset)
					else {
						return nil
					}
					if start == nil {
						start = loc
					} else {
						var a = loc.angle - start!.angle
						if a < -CGFloat.pi {
							a += 2 * CGFloat.pi
						} else if a > CGFloat.pi {
							a -= 2 * CGFloat.pi
						}
						if abs(a) * (180.0 / CGFloat.pi) > 1.0 {
							// hit an angle so stop the run
							if a < 0 {
								// If this is an acute angle then we need to advance a little extra so the next run doesn't overlap with this run
								let h = baselineOffset / 2 + size.height
								if -a < CGFloat.pi / 2 {
									let d = h * sin(-a)
									_ = pathPoints.advanceOffsetBy(d)
								} else {
									let a2 = CGFloat.pi - -a
									let d1 = h / sin(a2)
									let d2 = h / tan(a2)
									let d3 = min(d1 + d2, 3 * h)
									_ = pathPoints.advanceOffsetBy(d3)
								}
							}
							break
						}
					}

					let glyphWidth = advances[glyphIndex].width
					layerGlyphs.append(glyphs[glyphIndex])
					layerPositions.append(CGPoint(x: position, y: 0.0))
					position += glyphWidth

					_ = pathPoints.advanceOffsetBy(glyphWidth)
					glyphIndex += 1
				}
				layerPositions.append(CGPoint(x: position, y: 0.0))

				guard let glyphLayer = GlyphLayer.layer(withFont: runFont,
				                                        glyphs: layerGlyphs,
				                                        positions: layerPositions)
				else {
					return nil
				}
				glyphLayer.position = start!.pos
				glyphLayer.anchorPoint = CGPoint(x: 0, y: 1)
				glyphLayer.setAffineTransform(CGAffineTransform(rotationAngle: start!.angle))

				layers.append(glyphLayer)

				layerGlyphs.removeAll()
				layerPositions.removeAll()
			}
		}
		return layers
	}

	// return a non-curved rectangular layer
	static func layerWithString(_ string: String) -> CATextLayerWithProperties {
		let MAX_TEXT_WIDTH: CGFloat = 100.0

		// Don't cache these here because they are cached by the objects they are attached to
		let layer = CATextLayerWithProperties()
		layer.contentsScale = UIScreen.main.scale

		let font = StringGlyphs.uiFont

		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineSpacing = font.lineHeight - font.ascender + font
			.descender +
			6 // FIXME: 6 is a fudge factor so wrapped Chinese displays correctly, but English is now too large

		let attrString = NSAttributedString(string: string,
		                                    attributes: [
		                                    	NSAttributedString.Key.foregroundColor: CurvedGlyphLayer.foreColor
		                                    		.cgColor,
		                                    	NSAttributedString.Key.font: font,
		                                    	NSAttributedString.Key.paragraphStyle: paragraphStyle
		                                    ])

		let framesetter = CTFramesetterCreateWithAttributedString(attrString)

		var bounds = CGRect.zero
		var maxWidth = MAX_TEXT_WIDTH
		while true {
			bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
			                                                           CFRangeMake(0, attrString.length),
			                                                           nil,
			                                                           CGSize(width: maxWidth, height: 1000.0),
			                                                           nil)
			if bounds.height < maxWidth {
				break
			}
			maxWidth *= 2
		}
		bounds = bounds.insetBy(dx: -3, dy: -1)
		bounds.size
			.width = 2 *
			ceil(bounds.size
				.width / 2) // make divisible by 2 so when centered on anchor point at (0.5,0.5) everything still aligns
		bounds.size.height = 2 * ceil(bounds.size.height / 2)
		layer.bounds = bounds

		layer.string = attrString
		layer.truncationMode = CATextLayerTruncationMode.none
		layer.isWrapped = true
		layer.alignmentMode = CATextLayerAlignmentMode.left // because our origin is -3 this is actually centered

		layer.backgroundColor = backColor.cgColor

		return layer
	}
}

final class GlyphLayer: CALayerWithProperties {
	private static let cache = { () -> NSCache<NSData, GlyphLayer> in
		let c = NSCache<NSData, GlyphLayer>()
		c.countLimit = 200
		NotificationCenter.default.addObserver(
			forName: UIContentSizeCategory.didChangeNotification,
			object: nil,
			queue: nil,
			using: { _ in
				GlyphLayer.clearCache()
			})
		return c
	}()

	private let glyphs: [CGGlyph]
	private let positions: [CGPoint]
	private let font: CTFont
	// Calling super.init() on a CALayer subclass that contains a var doesn't work on iOS 9
	// Declaring it NSManaged avoids this bug
	@NSManaged var inUse: Bool

	private func copy() -> GlyphLayer {
		return GlyphLayer(withCopy: self)
	}

	override func removeFromSuperlayer() {
		inUse = false
		super.removeFromSuperlayer()
	}

	override func action(forKey _: String) -> CAAction? {
		// we don't want any animated actions
		return NSNull()
	}

	static func clearCache() {
		cache.removeAllObjects()
	}

	private init(withFont font: CTFont, glyphs: [CGGlyph], positions: [CGPoint]) {
		self.glyphs = glyphs
		self.positions = positions
		self.font = font
		super.init()
		inUse = true
		let size = CTFontGetBoundingBox(font).size
		let descent = CTFontGetDescent(font)
		bounds = CGRect(x: 0, y: descent, width: positions.last!.x, height: size.height)
		contentsScale = UIScreen.main.scale
		anchorPoint = CGPoint.zero
		backgroundColor = CurvedGlyphLayer.backColor.cgColor
		setNeedsDisplay()
	}

	private init(withCopy copy: GlyphLayer) {
		glyphs = copy.glyphs
		positions = copy.positions
		font = copy.font
		super.init()
		inUse = true
		contentsScale = copy.contentsScale
		anchorPoint = copy.anchorPoint
		bounds = copy.bounds
		backgroundColor = copy.backgroundColor
#if false
		// BUG: apparently the contents can be invalidated without us being notified, resulting in missing glyphs
		contents = copy.contents // use existing backing store so we don't have to redraw
#else
		setNeedsDisplay() // FIXME: need to either fix this problem or cache better
#endif
	}

	public static func layer(withFont font: CTFont, glyphs: [CGGlyph], positions: [CGPoint]) -> GlyphLayer? {
		let key = glyphs.withUnsafeBytes { a in
			NSData(bytes: a.baseAddress, length: a.count)
		}
		if let layer = cache.object(forKey: key) {
			if layer.inUse {
				return layer.copy()
			}
			layer.inUse = true
			return layer
		} else {
			let layer = GlyphLayer(withFont: font, glyphs: glyphs, positions: positions)
			cache.setObject(layer, forKey: key)
			return layer
		}
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func draw(in context: CGContext) {
		context.saveGState()
		context.textMatrix = CGAffineTransform.identity
		context.translateBy(x: 0, y: bounds.size.height)
		context.scaleBy(x: 1.0, y: -1.0)
		context.setFillColor(CurvedGlyphLayer.foreColor.cgColor)
		CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
		context.restoreGState()
	}
}
