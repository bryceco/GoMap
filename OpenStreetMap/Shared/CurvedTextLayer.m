//
//  CurvedTextLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

#import "CurvedTextLayer.h"
#import "PathUtil.h"


@implementation CurvedTextLayer

static const CGFloat TEXT_SHADOW_WIDTH = 2.5;


+(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset stroke:(BOOL)stroke color:(NSColor *)color context:(CGContextRef)ctx
{
	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );

	if ( stroke ) {

		CGContextSetLineWidth( ctx, TEXT_SHADOW_WIDTH);
		CGContextSetLineJoin( ctx, kCGLineJoinRound );
		CGContextSetTextDrawingMode( ctx, kCGTextFillStroke );
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetStrokeColorWithColor(ctx, color.CGColor);

	} else {

		CGContextSetTextDrawingMode( ctx, kCGTextFill );
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetStrokeColorWithColor(ctx, NULL);
		CGContextSetTextDrawingMode(ctx, kCGTextFill);
	}

	CTFontRef ctFont = CTFontCreateUIFontForLanguage( kCTFontUIFontSystem, 14.0, NULL );

	CGContextSaveGState(ctx);
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
	CGContextSetTextPosition(ctx, 0, 0);

	// get array of glyph widths
	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string attributes:@{ (NSString *)kCTFontAttributeName : (__bridge id)ctFont }];
	CTLineRef	line		= CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
	CFArrayRef	runArray	= CTLineGetGlyphRuns(line);
	CFIndex		runCount	= CFArrayGetCount(runArray);

	for ( CFIndex runIndex = 0; runIndex < runCount; runIndex++) {
		CTRunRef	run				= (CTRunRef)CFArrayGetValueAtIndex( runArray, runIndex );
		CFIndex		runGlyphCount	= CTRunGetGlyphCount( run );
		CTFontRef	runFont			= CFDictionaryGetValue( CTRunGetAttributes(run), kCTFontAttributeName );
		CGGlyph		glyphs[ runGlyphCount ];
		CGPoint		glyphPositions[ runGlyphCount ];
		CGPoint		positions[ runGlyphCount ];
		CTRunGetGlyphs( run, CFRangeMake(0,runGlyphCount), glyphs);
		CTRunGetPositions( run, CFRangeMake(0,runGlyphCount), glyphPositions );

		for ( CFIndex runGlyphIndex = 0; runGlyphIndex < runGlyphCount; runGlyphIndex++ ) {

			CGContextSaveGState(ctx);

			CGPoint pos;
			CGFloat angle, length;
			PathPositionAndAngleForOffset( path, offset+glyphPositions[runGlyphIndex].x, 3, &pos, &angle, &length );

			NSInteger segmentCount = 0;
			while ( runGlyphIndex+segmentCount < runGlyphCount ) {
				positions[segmentCount].x = glyphPositions[runGlyphIndex+segmentCount].x - glyphPositions[runGlyphIndex].x;
				positions[segmentCount].y = 0;
				++segmentCount;
				if ( glyphPositions[runGlyphIndex+segmentCount].x >= length )
					break;
			}

			// We use a different affine transform for each glyph segment, to position and rotate it
			// based on its calculated position along the path.
			CGContextTranslateCTM( ctx, pos.x, pos.y );
			CGContextRotateCTM( ctx, angle );
			CGContextScaleCTM( ctx, 1.0, -1.0 );

			// draw text
			CTFontDrawGlyphs( runFont, &glyphs[runGlyphIndex], positions, segmentCount, ctx );
			
			CGContextRestoreGState(ctx);

			runGlyphIndex += segmentCount - 1;
		}
	}
	CFRelease(line);
	CFRelease(ctFont);

	CGContextRestoreGState(ctx);
}


+(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor context:(CGContextRef)ctx
{
	[self drawString:string alongPath:path offset:offset stroke:YES color:shadowColor context:ctx];
	[self drawString:string alongPath:path offset:offset stroke:NO  color:color		  context:ctx];
}

+(void)drawString:(NSString *)string centeredOnPoint:(CGPoint)center width:(CGFloat)lineWidth font:(NSFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor context:(CGContextRef)ctx
{
	CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1.0, -1.0)); // view's coordinates are flipped

#if TARGET_OS_IPHONE
	if ( font == nil )
		font = [UIFont systemFontOfSize:10];
	NSAttributedString * s1 = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : (id)color.CGColor,		NSFontAttributeName : font }];
	NSAttributedString * s2 = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : (id)shadowColor.CGColor,	NSFontAttributeName : font }];
#else
	if ( font == nil )
		font = [NSFont systemFontOfSize:10];
	NSAttributedString * s1 = [[NSAttributedString alloc] initWithString:name attributes:@{NSForegroundColorAttributeName : self.textColor}];
#endif

	CGFloat lineHeight = font.lineHeight;
	CGFloat lineDescent = font.descender;

	// compute number of characters in each line of text
	const NSInteger maxLines = 20;
	NSInteger lineCount = 0;
	NSInteger charPerLine[ maxLines ];
	NSInteger charCount = CFAttributedStringGetLength( (__bridge CFAttributedStringRef)s1 );
	CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString( (__bridge CFAttributedStringRef)s1 );
	if ( lineWidth == 0 ) {
		charPerLine[lineCount++] = charCount;
	} else {
		NSInteger start = 0;
		while ( lineCount < maxLines ) {
			CFIndex count = CTTypesetterSuggestLineBreak( typesetter, start, lineWidth );
			charPerLine[ lineCount++ ] = count;
			start += count;
			if ( start >= charCount )
				break;
		}
	}

	// iterate over lines
	NSInteger start = 0;
	for ( NSInteger line = 0; line < lineCount; ++line )  {
		CFIndex count = charPerLine[ line ];
		CTLineRef ct1 = CTTypesetterCreateLine( typesetter, CFRangeMake(start,count) );
		CTLineRef ct2 = CTLineCreateWithAttributedString( (__bridge CFAttributedStringRef)[s2 attributedSubstringFromRange:NSMakeRange(start,count)] );

		// center on point
		CGRect textRect = CTLineGetBoundsWithOptions( ct1, 0 );
		CGPoint point = {
			round( center.x - (textRect.origin.x+textRect.size.width)/2 ),
			round( center.y + lineHeight*(1 + line - lineCount/2.0) + lineDescent )
		};

		// draw shadow
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );
		CGContextSetLineWidth( ctx, TEXT_SHADOW_WIDTH);
		CGContextSetLineJoin( ctx, kCGLineJoinRound );
		CGContextSetStrokeColorWithColor(ctx, shadowColor.CGColor);
		CGContextSetFillColorWithColor(ctx, shadowColor.CGColor);
		CGContextSetTextDrawingMode(ctx, kCGTextFillStroke);
		CGContextSetTextPosition(ctx, point.x, point.y);	// this applies a transform, so do it after flipping
		CTLineDraw(ct2, ctx);

		// draw text
		CGContextSetTextDrawingMode(ctx, kCGTextFill);
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetTextPosition(ctx, point.x, point.y);	// this applies a transform, so do it after flipping
		CTLineDraw(ct1, ctx);

		CFRelease(ct1);
		CFRelease(ct2);

		start += count;
	}

	CFRelease(typesetter);
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
}


+(CGSize)sizeOfText:(NSAttributedString *)string
{
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString( (CFAttributedStringRef)string );
	CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(70, CGFLOAT_MAX), NULL);
	CFRelease(framesetter);
	return suggestedSize;
}

+(CALayer *)layerWithString:(NSString *)string width:(CGFloat)lineWidth font:(UIFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor
{
	CATextLayer * layer = [CATextLayer new];

	if ( font == nil )
		font = [UIFont systemFontOfSize:10];
	NSAttributedString * s = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : (id)color.CGColor, NSFontAttributeName : font }];

	CGRect bounds = { 0 };
	bounds.size = [CurvedTextLayer sizeOfText:s];
	bounds = CGRectInset( bounds, -3, -1 );
	bounds.size.width  = 2 * ceil( bounds.size.width/2 );	// make divisible by 2 so when centered on anchor point at (0.5,0.5) everything still aligns
	bounds.size.height = 2 * ceil( bounds.size.height/2 );
	layer.bounds = bounds;

	layer.string			= s;
	layer.truncationMode	= kCATruncationNone;
	layer.wrapped			= YES;
	layer.alignmentMode		= kCAAlignmentCenter;

	CGPathRef shadowPath	= CGPathCreateWithRect(bounds, NULL);
	layer.shadowPath		= shadowPath;
	layer.shadowColor		= shadowColor.CGColor;
	layer.shadowRadius		= 0.0;
	layer.shadowOffset		= CGSizeMake(0,0);
	layer.shadowOpacity		= 0.5;
	CGPathRelease(shadowPath);

	return layer;
}


+(NSArray *)layersWithString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color
{
	NSMutableArray * layers = [NSMutableArray new];

	CTFontRef ctFont = CTFontCreateUIFontForLanguage( kCTFontUIFontSystem, 14.0, NULL );
	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string attributes:@{ (NSString *)kCTFontAttributeName : (__bridge id)ctFont }];
	CFAttributedStringRef attrStringRef = (__bridge CFAttributedStringRef)attrString;
	NSInteger charCount = CFAttributedStringGetLength( attrStringRef );
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString( attrStringRef );
	CTTypesetterRef typesetter = CTFramesetterGetTypesetter( framesetter );
	double lineHeight = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0,attrString.length), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL).height;
	CFIndex currentCharacter = 0;
	double currentPixelOffset = offset;
	while ( currentCharacter < charCount ) {
		// get the number of characters that fit in the current path segment and create a text layer for it
		CGPoint pos;
		CGFloat angle, length;
		PathPositionAndAngleForOffset( path, currentPixelOffset, lineHeight, &pos, &angle, &length );
		CFIndex count = CTTypesetterSuggestLineBreak( typesetter, currentCharacter, length );

		CATextLayer * layer = [CATextLayer layer];
		layer.string = [attrString attributedSubstringFromRange:NSMakeRange(currentCharacter,count)];
		CGRect bounds = { 0 };
		bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(currentCharacter,count), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
		layer.bounds			= bounds;
		layer.affineTransform	= CGAffineTransformRotate( CGAffineTransformMakeTranslation(pos.x, pos.y), angle );
		layer.anchorPoint		= CGPointMake(0,0);
		layer.foregroundColor	= color.CGColor;
		layer.truncationMode	= kCATruncationNone;
		layer.wrapped			= NO;
		layer.alignmentMode		= kCAAlignmentCenter;

		[layers addObject:layer];

		currentCharacter += count;
		currentPixelOffset += bounds.size.width;
	}

	CFRelease(framesetter);
	CFRelease(ctFont);

	return layers;
}


// - (UIBezierPath*) bezierPathWithString:(NSString*) string font:(UIFont*) font inRect:(CGRect) rect;
// Requires CoreText.framework
// This creates a graphical version of the input screen, line wrapped to the input rect.
// Core Text involves a whole hierarchy of objects, all requiring manual management.
// http://stackoverflow.com/questions/10152574/catextlayer-blurry-text-after-rotation
- (UIBezierPath*) bezierPathWithString:(NSString *)string font:(UIFont *)font inRect:(CGRect)rect
{
	UIBezierPath *combinedGlyphsPath = nil;
	CGMutablePathRef combinedGlyphsPathRef = CGPathCreateMutable();
	if (combinedGlyphsPathRef)
	{
		// It would be easy to wrap the text into a different shape, including arbitrary bezier paths, if needed.
		UIBezierPath *frameShape = [UIBezierPath bezierPathWithRect:rect];

		// If the font name wasn't found while creating the font object, the result is a crash.
		// Avoid this by falling back to the system font.
		CTFontRef fontRef;
		if ([font fontName])
			fontRef = CTFontCreateWithName((__bridge CFStringRef) [font fontName], [font pointSize], NULL);
		else if (font)
			fontRef = CTFontCreateUIFontForLanguage(kCTFontUserFontType, [font pointSize], NULL);
		else
			fontRef = CTFontCreateUIFontForLanguage(kCTFontUserFontType, [UIFont systemFontSize], NULL);

		if (fontRef)
		{
			CGPoint basePoint = CGPointMake(0, CTFontGetAscent(fontRef));
			CFStringRef keys[] = { kCTFontAttributeName };
			CFTypeRef values[] = { fontRef };
			CFDictionaryRef attributesRef = CFDictionaryCreate(NULL, (const void **)&keys, (const void **)&values,
															   sizeof(keys) / sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

			if (attributesRef)
			{
				CFAttributedStringRef attributedStringRef = CFAttributedStringCreate(NULL, (__bridge CFStringRef) string, attributesRef);

				if (attributedStringRef)
				{
					CTFramesetterRef frameSetterRef = CTFramesetterCreateWithAttributedString(attributedStringRef);

					if (frameSetterRef)
					{
						CTFrameRef frameRef = CTFramesetterCreateFrame(frameSetterRef, CFRangeMake(0,0), [frameShape CGPath], NULL);

						if (frameRef)
						{
							CFArrayRef lines = CTFrameGetLines(frameRef);
							CFIndex lineCount = CFArrayGetCount(lines);
							CGPoint lineOrigins[lineCount];
							CTFrameGetLineOrigins(frameRef, CFRangeMake(0, lineCount), lineOrigins);

							for (CFIndex lineIndex = 0; lineIndex<lineCount; lineIndex++)
							{
								CTLineRef lineRef = CFArrayGetValueAtIndex(lines, lineIndex);
								CGPoint lineOrigin = lineOrigins[lineIndex];

								CFArrayRef runs = CTLineGetGlyphRuns(lineRef);

								CFIndex runCount = CFArrayGetCount(runs);
								for (CFIndex runIndex = 0; runIndex<runCount; runIndex++)
								{
									CTRunRef runRef = CFArrayGetValueAtIndex(runs, runIndex);

									CFIndex glyphCount = CTRunGetGlyphCount(runRef);
									CGGlyph glyphs[glyphCount];
									CGSize glyphAdvances[glyphCount];
									CGPoint glyphPositions[glyphCount];

									CFRange runRange = CFRangeMake(0, glyphCount);
									CTRunGetGlyphs(runRef, CFRangeMake(0, glyphCount), glyphs);
									CTRunGetPositions(runRef, runRange, glyphPositions);

									CTFontGetAdvancesForGlyphs(fontRef, kCTFontDefaultOrientation, glyphs, glyphAdvances, glyphCount);

									for (CFIndex glyphIndex = 0; glyphIndex<glyphCount; glyphIndex++)
									{
										CGGlyph glyph = glyphs[glyphIndex];

										// For regular UIBezierPath drawing, we need to invert around the y axis.
										CGAffineTransform glyphTransform = CGAffineTransformMakeTranslation(lineOrigin.x+glyphPositions[glyphIndex].x, rect.size.height-lineOrigin.y-glyphPositions[glyphIndex].y);
										glyphTransform = CGAffineTransformScale(glyphTransform, 1, -1);

										CGPathRef glyphPathRef = CTFontCreatePathForGlyph(fontRef, glyph, &glyphTransform);
										if (glyphPathRef)
										{
											// Finally carry out the appending.
											CGPathAddPath(combinedGlyphsPathRef, NULL, glyphPathRef);

											CFRelease(glyphPathRef);
										}

										basePoint.x += glyphAdvances[glyphIndex].width;
										basePoint.y += glyphAdvances[glyphIndex].height;
									}
								}
								basePoint.x = 0;
								basePoint.y += CTFontGetAscent(fontRef) + CTFontGetDescent(fontRef) + CTFontGetLeading(fontRef);
							}

							CFRelease(frameRef);
						}

						CFRelease(frameSetterRef);
					}
					CFRelease(attributedStringRef);
				}
				CFRelease(attributesRef);
			}
			CFRelease(fontRef);
		}
		// Casting a CGMutablePathRef to a CGPathRef seems to be the only way to convert what was just built into a UIBezierPath.
		combinedGlyphsPath = [UIBezierPath bezierPathWithCGPath:(CGPathRef) combinedGlyphsPathRef];

		CGPathRelease(combinedGlyphsPathRef);
	}
	return combinedGlyphsPath;
}


@end
