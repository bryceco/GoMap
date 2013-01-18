//
//  CurvedTextLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreText/CoreText.h>
#import "CurvedTextLayer.h"


@implementation CurvedTextLayer

static void GetPathElement(void *info, const CGPathElement *element)
{
	static CGPoint prev;
	double * length = (double *)info;
	switch ( element->type ) {
		case kCGPathElementMoveToPoint:
			assert(*length == 0.0);
			prev = element->points[0];
			break;
		case kCGPathElementAddLineToPoint:
			{
				CGPoint pt = element->points[0];
				double dx = pt.x - prev.x;
				double dy = pt.y - prev.y;
				*length += sqrt( dx*dx + dy*dy );
				prev = pt;
			}
			break;
		case kCGPathElementAddQuadCurveToPoint:
		case kCGPathElementAddCurveToPoint:
		case kCGPathElementCloseSubpath:
			assert(NO);
			break;
	}
}

struct Position {
	BOOL	done;
	CGPoint	previous;
	CGFloat	offset;
	CGPoint position;
	CGFloat	angle;
};
static void GetPathPosition(void *info, const CGPathElement *element)
{
	struct Position * pos = (struct Position *)info;
	if ( pos->done )
		return;
	switch ( element->type ) {
		case kCGPathElementMoveToPoint:
			pos->previous = element->points[0];
			break;
		case kCGPathElementAddLineToPoint:
			{
				CGPoint pt = element->points[0];
				double dx = pt.x - pos->previous.x;
				double dy = pt.y - pos->previous.y;
				double len = sqrt( dx*dx + dy*dy );
				double frac = pos->offset / len;
				pos->position.x = pos->previous.x + frac * dx;
				pos->position.y = pos->previous.y + frac * dy;
				pos->angle = atan2(dy,dx);
				if ( pos->offset < len ) {
					// found it
					pos->done = YES;
				} else {
					pos->offset -= len;
					pos->previous = pt;
				}
			}
			break;
		case kCGPathElementAddQuadCurveToPoint:
		case kCGPathElementAddCurveToPoint:
		case kCGPathElementCloseSubpath:
			assert(NO);
			break;
	}
}

static void GetPositionAndAngleForOffset( CGPathRef path, double offset, CGPoint * pos, CGFloat * angle )
{
	struct Position position = { 0 };
	position.offset = offset;
	CGPathApply(path, &position, GetPathPosition);
	*pos = position.position;
	*angle = position.angle;
}

+(void)drawString:(NSString *)string font:(NSFont *)font color:(NSColor *)color shadowColor:(NSColor *)shadowColor path:(CGPathRef)path context:(CGContextRef)ctx
{
	CGFloat red, green, blue, alpha;
	[color getRed:&red green:&green blue:&blue alpha:&alpha];
	CGContextSetTextDrawingMode(ctx, kCGTextFill);
	CGContextSetRGBFillColor(ctx, red, green, blue, alpha);
	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 5.0, shadowColor.CGColor );

	CGContextSelectFont( ctx, "Helvetica", 12.0, kCGEncodingMacRoman );

	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string attributes:nil];

	CGContextSaveGState(ctx);

	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
	CGContextSetTextPosition(ctx, 0, 0);

	// get array of glyph widths
	CTLineRef	line	= CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
	CFArrayRef	runArray = CTLineGetGlyphRuns(line);
	CFIndex		runCount = CFArrayGetCount(runArray);

	double glyphOffset = 0.0;

	CFIndex glyphIndex = 0;
	for (CFIndex runIndex = 0; runIndex < runCount; runIndex++) {
		CTRunRef run			= (CTRunRef)CFArrayGetValueAtIndex(runArray, runIndex);
		CFIndex	 runGlyphCount	= CTRunGetGlyphCount(run);

		for ( CFIndex runGlyphIndex = 0; runGlyphIndex < runGlyphCount; runGlyphIndex++ ) {

			CGContextSaveGState(ctx);

			CGPoint pos;
			CGFloat angle;
			GetPositionAndAngleForOffset( path, glyphOffset, &pos, &angle );

			// We use a different affine transform for each glyph, to position and rotate it
			// based on its calculated position along the path.
			CGContextTranslateCTM( ctx, pos.x, pos.y );
			CGContextRotateCTM( ctx, angle );
			CGContextScaleCTM( ctx, 1.0, -1.0 );

			CGGlyph glyph;
			CFRange range = CFRangeMake(runGlyphIndex, 1);
			CTRunGetGlyphs(run, range, &glyph);
			CGPoint position = { 0, 0 };
			CGContextShowGlyphsAtPositions(ctx, &glyph, &position, 1);

			CGContextRestoreGState(ctx);

			double glyphWidth = CTRunGetTypographicBounds( run, range, NULL, NULL, NULL);
			glyphOffset += glyphWidth;
			++glyphIndex;
		}
	}
	CFRelease(line);

	CGContextRestoreGState(ctx);
}

@end
