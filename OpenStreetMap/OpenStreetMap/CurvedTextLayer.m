//
//  CurvedTextLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreText/CoreText.h>
#import "CurvedTextLayer.h"

#import "PathUtil.h"


@implementation CurvedTextLayer


+(void)drawString:(NSString *)string offset:(CGFloat)offset stroke:(BOOL)stroke color:(NSColor *)color path:(CGPathRef)path context:(CGContextRef)ctx
{
	if ( stroke ) {
		
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );
		CGContextSetLineWidth( ctx, 4.0);
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

		for ( CFIndex runGlyphIndex = 0; runGlyphIndex < runGlyphCount; runGlyphIndex++ ) {

			CGContextSaveGState(ctx);

			CFRange range = CFRangeMake(runGlyphIndex, 1);

			CGPoint glyphPosition;
			CTRunGetPositions( run, range, &glyphPosition );

			CGPoint pos;
			CGFloat angle;
			PathPositionAndAngleForOffset( path, offset+glyphPosition.x, &pos, &angle );

			// We use a different affine transform for each glyph, to position and rotate it
			// based on its calculated position along the path.
			CGContextTranslateCTM( ctx, pos.x, pos.y );
			CGContextRotateCTM( ctx, angle );
			CGContextScaleCTM( ctx, 1.0, -1.0 );

			CGGlyph glyph;
			CTRunGetGlyphs(run, range, &glyph);
			CGPoint position = { 0, 0 };

			// outlined text
			CTFontDrawGlyphs( runFont, &glyph, &position, 1, ctx );
			
			CGContextRestoreGState(ctx);
		}
	}
	CFRelease(line);

	CGContextRestoreGState(ctx);
}


+(void)drawString:(NSString *)string offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor path:(CGPathRef)path context:(CGContextRef)ctx
{
	[self drawString:string offset:offset stroke:YES color:shadowColor path:path context:ctx];
	[self drawString:string offset:offset stroke:NO  color:color		 path:path context:ctx];
}

@end
