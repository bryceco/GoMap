//
//  CurvedGlyphLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/6/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import CoreText
import UIKit

private struct TextLoc {
	var pos: CGPoint
	var angle: CGFloat
	var length: CGFloat
}

private final class PathPoints {
	let points: [CGPoint]
	let length: CGFloat
	private var offset: CGFloat = 0.0
	private var segment = 0

	init(path: CGPath) {
		points = path.getPoints()
		var len: CGFloat = 0
		for i in 1..<points.count {
			let p1 = points[i - 1]
			let p2 = points[i]
			len += hypot(p2.x - p1.x, p2.y - p1.y)
		}
		length = len
	}

	func resetOffset() {
		segment = 0
		offset = 0.0
	}

	func advanceOffsetBy(_ delta: CGFloat) -> Bool {
		var delta = delta
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
	static var uiFont = UIFont.preferredFont(forTextStyle: .subheadline)

	private static let cache: NSCache<NSString, StringGlyphs> = {
		let c = NSCache<NSString, StringGlyphs>()
		c.countLimit = 100
		NotificationCenter.default.addObserver(
			forName: UIContentSizeCategory.didChangeNotification,
			object: nil,
			queue: .main,
			using: { _ in
				resetCache()
			})
		return c
	}()

	private static func resetCache() {
		uiFont = UIFont.preferredFont(forTextStyle: .subheadline)
		cache.removeAllObjects()
	}

	let runs: [CTRun]
	let rect: CGRect

	private init?(string: NSString) {
		let attrString = NSAttributedString(string: string as String,
		                                    attributes: [.font: StringGlyphs.uiFont])
		let ctLine = CTLineCreateWithAttributedString(attrString)
		guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else {
			return nil
		}
		self.runs = runs
		rect = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
	}

	static func glyphsForRun(_ run: CTRun) -> [CGGlyph] {
		let count = CTRunGetGlyphCount(run)
		return [CGGlyph](unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetGlyphs(run, CFRange(location: 0, length: count), buffer.baseAddress!)
			initializedCount = count
		}
	}

	static func advancesForRun(_ run: CTRun) -> [CGSize] {
		let count = CTRunGetGlyphCount(run)
		return [CGSize](unsafeUninitializedCapacity: count) { buffer, initializedCount in
			CTRunGetAdvances(run, CFRange(location: 0, length: count), buffer.baseAddress!)
			initializedCount = count
		}
	}

	static func fontForRun(_ run: CTRun) -> CTFont {
		(CTRunGetAttributes(run) as Dictionary)[kCTFontAttributeName] as! CTFont
	}

	static func forString(_ string: NSString) -> StringGlyphs? {
		if let glyphs = cache.object(forKey: string) {
			return glyphs
		}
		guard let glyphs = StringGlyphs(string: string) else {
			return nil
		}
		cache.setObject(glyphs, forKey: string)
		return glyphs
	}
}

final class CurvedGlyphLayer {
	static var foreColor = UIColor.white
	static var backColor = UIColor.black.withAlphaComponent(0.3)

	static var whiteOnBlack = true {
		didSet {
			if oldValue != whiteOnBlack {
				GlyphLayer.clearCache()
				foreColor = whiteOnBlack ? .white : .black
				backColor = (whiteOnBlack ? UIColor.black : .white).withAlphaComponent(0.3)
			}
		}
	}

	private let stringGlyphs: StringGlyphs
	private let pathPoints: PathPoints

	private init(glyphs: StringGlyphs, pathPoints: PathPoints) {
		stringGlyphs = glyphs
		self.pathPoints = pathPoints
	}

	static func layer(withString string: String, alongPath path: CGPath) -> CurvedGlyphLayer? {
		guard let glyphRuns = StringGlyphs.forString(string as NSString) else { return nil }
		let pathPoints = PathPoints(path: path)

		if glyphRuns.rect.size.width + 8 >= pathPoints.length {
			return nil // doesn't fit
		}

		return CurvedGlyphLayer(glyphs: glyphRuns, pathPoints: pathPoints)
	}

	func glyphLayers() -> [GlyphLayer]? {
		pathPoints.resetOffset()
		guard pathPoints.advanceOffsetBy((pathPoints.length - stringGlyphs.rect.width) / 2) else { return nil }

		let baselineOffset: CGFloat = 3

		var layers: [GlyphLayer] = []

		for run in stringGlyphs.runs {
			// every run potentially has a different font, due to font substitution
			let runFont = StringGlyphs.fontForRun(run)
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
								// If this is an acute angle then we need to advance a little extra
								// so the next run doesn't overlap with this run
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
		paragraphStyle.lineSpacing = font.leading

		let attrString = NSAttributedString(
			string: string,
			attributes: [
				.foregroundColor: CurvedGlyphLayer.foreColor.cgColor,
				.font: font,
				.paragraphStyle: paragraphStyle
			])

		let framesetter = CTFramesetterCreateWithAttributedString(attrString)

		var bounds = CGRect.zero
		var maxWidth = MAX_TEXT_WIDTH
		while true {
			bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
			                                                           CFRange(location: 0, length: attrString.length),
			                                                           nil,
			                                                           CGSize(width: maxWidth, height: 1000.0),
			                                                           nil)
			if bounds.height < maxWidth {
				break
			}
			maxWidth *= 2
		}
		bounds = bounds.insetBy(dx: -3, dy: -1)
		// make divisible by 2 so when centered on anchor point at (0.5,0.5) everything still aligns
		bounds.size.width = 2 * ceil(bounds.size.width / 2)
		bounds.size.height = 2 * ceil(bounds.size.height / 2)
		layer.bounds = bounds

		layer.string = attrString
		layer.truncationMode = .none
		layer.isWrapped = true
		layer.alignmentMode = .left // because our origin is -3 this is actually centered

		layer.backgroundColor = backColor.cgColor

		return layer
	}
}

final class GlyphLayer: CALayerWithProperties {
	// Glyph runs rasterized once and shared by every layer that displays the same run.
	// Caching the image rather than the layer is safe: a CGImage is immutable and has
	// no superlayer, so any number of layers can show it at once.
	private static let imageCache: NSCache<NSData, CGImage> = {
		let c = NSCache<NSData, CGImage>()
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

	static func clearCache() {
		imageCache.removeAllObjects()
	}

	override func action(forKey _: String) -> CAAction? {
		// we don't want any animated actions
		return NSNull()
	}

	private static func cacheKey(font: CTFont, glyphs: [CGGlyph]) -> NSData {
		// Glyph IDs are only meaningful within a font, so the font is part of the key.
		let key = NSMutableData()
		var size = CTFontGetSize(font)
		withUnsafeBytes(of: &size) { key.append($0.baseAddress!, length: $0.count) }
		key.append(Data((CTFontCopyPostScriptName(font) as String).utf8))
		glyphs.withUnsafeBytes { key.append($0.baseAddress!, length: $0.count) }
		return key
	}

	private static func image(font: CTFont, glyphs: [CGGlyph], positions: [CGPoint], bounds: CGRect) -> CGImage? {
		guard bounds.width > 0, bounds.height > 0 else {
			return nil
		}
		let format = UIGraphicsImageRendererFormat.default()
		format.scale = UIScreen.main.scale
		format.opaque = false
		let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
		return renderer.image { ctx in
			let context = ctx.cgContext
			// Draw in the layer's bounds coordinate space, as draw(in:) would
			context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
			context.textMatrix = .identity
			context.translateBy(x: 0, y: bounds.size.height)
			context.scaleBy(x: 1.0, y: -1.0)
			context.setFillColor(CurvedGlyphLayer.foreColor.cgColor)
			CTFontDrawGlyphs(font, glyphs, positions, glyphs.count, context)
		}.cgImage
	}

	private init(font: CTFont, glyphs: [CGGlyph], positions: [CGPoint]) {
		super.init()
		let size = CTFontGetBoundingBox(font).size
		let descent = CTFontGetDescent(font)
		bounds = CGRect(x: 0, y: descent, width: positions.last!.x, height: size.height)
		contentsScale = UIScreen.main.scale
		anchorPoint = .zero
		backgroundColor = CurvedGlyphLayer.backColor.cgColor

		let key = Self.cacheKey(font: font, glyphs: glyphs)
		if let image = Self.imageCache.object(forKey: key) {
			contents = image
		} else if let image = Self.image(font: font, glyphs: glyphs, positions: positions, bounds: bounds) {
			Self.imageCache.setObject(image, forKey: key)
			contents = image
		}
	}

	static func layer(withFont font: CTFont, glyphs: [CGGlyph], positions: [CGPoint]) -> GlyphLayer? {
		return GlyphLayer(font: font, glyphs: glyphs, positions: positions)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
