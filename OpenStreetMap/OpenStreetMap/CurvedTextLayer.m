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
				double len = hypot(dx,dy);
				dx /= len;
				dy /= len;

				// always set position/angle because if we fall off the end we need it set
				pos->position.x = pos->previous.x + pos->offset * dx;
				pos->position.y = pos->previous.y + pos->offset * dy;
				pos->angle = atan2(dy,dx);

				// shift text off baseline
				pos->position.x +=  dy * 3;
				pos->position.y += -dx * 3;

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

+(void)drawString:(NSString *)string color:(NSColor *)color shadowColor:(NSColor *)shadowColor path:(CGPathRef)path context:(CGContextRef)ctx
{
	const double StartingOffset = 5.0;	// start off slightly offset from end of way

	CGContextSetFillColorWithColor(ctx, color.CGColor);
	CGContextSetStrokeColorWithColor(ctx, NULL);
	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 5.0, shadowColor.CGColor );
	CGContextSetTextDrawingMode(ctx, kCGTextFill);

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

		for ( CFIndex runGlyphIndex = 0; runGlyphIndex < runGlyphCount; runGlyphIndex++ ) {

			CGContextSaveGState(ctx);

			CFRange range = CFRangeMake(runGlyphIndex, 1);

			CGPoint glyphPosition;
			CTRunGetPositions( run, range, &glyphPosition );

			CGPoint pos;
			CGFloat angle;
			GetPositionAndAngleForOffset( path, StartingOffset+glyphPosition.x, &pos, &angle );

			// We use a different affine transform for each glyph, to position and rotate it
			// based on its calculated position along the path.
			CGContextTranslateCTM( ctx, pos.x, pos.y );
			CGContextRotateCTM( ctx, angle );
			CGContextScaleCTM( ctx, 1.0, -1.0 );

			CGGlyph glyph;
			CTRunGetGlyphs(run, range, &glyph);
			CGPoint position = { 0, 0 };

#if 0
			// plain text
			CTFontDrawGlyphs( runFont, &glyph, &position, 1, ctx );	// must use runFont here to get font substitution
#else
			// outlined text
			CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );
			CGContextSetLineWidth( ctx, 2.0);
			CGContextSetLineJoin( ctx, kCGLineJoinRound );

			CGContextSetTextDrawingMode( ctx, kCGTextFillStroke );
			CGContextSetFillColorWithColor(ctx, shadowColor.CGColor);
			CGContextSetStrokeColorWithColor(ctx, shadowColor.CGColor);
			CTFontDrawGlyphs( runFont, &glyph, &position, 1, ctx );

			CGContextSetTextDrawingMode( ctx, kCGTextFill );
			CGContextSetFillColorWithColor(ctx, color.CGColor);
			CTFontDrawGlyphs( runFont, &glyph, &position, 1, ctx );
#endif
			
			CGContextRestoreGState(ctx);
		}
	}
	CFRelease(line);

	CGContextRestoreGState(ctx);
}

@end
