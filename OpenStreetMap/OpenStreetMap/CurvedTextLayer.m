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


+(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor context:(CGContextRef)ctx
{
	[self drawString:string alongPath:path offset:offset stroke:YES color:shadowColor context:ctx];
	[self drawString:string alongPath:path offset:offset stroke:NO  color:color		  context:ctx];
}

+(void)drawString:(NSString *)string centeredOnPoint:(CGPoint)point font:(NSFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor context:(CGContextRef)ctx
{
#if TARGET_OS_IPHONE
	if ( font == nil )
		font = [UIFont systemFontOfSize:10];
	NSAttributedString * s1 = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : color,		NSFontAttributeName : font }];
	NSAttributedString * s2 = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : shadowColor,	NSFontAttributeName : font }];
#else
	if ( font == nil )
		font = [NSFont systemFontOfSize:10];
	NSAttributedString * s1 = [[NSAttributedString alloc] initWithString:name attributes:@{NSForegroundColorAttributeName : self.textColor}];
#endif

	CTLineRef ct1 = CTLineCreateWithAttributedString( (__bridge CFAttributedStringRef)s1 );
	CTLineRef ct2 = CTLineCreateWithAttributedString( (__bridge CFAttributedStringRef)s2 );

	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );
	CGRect textRect = CTLineGetBoundsWithOptions( ct1, 0 );
	point.x = round( point.x - (textRect.origin.x+textRect.size.width)/2 );
	point.y = round( point.y + (textRect.origin.y+textRect.size.height)/2 );

	CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1.0, -1.0)); // view's coordinates are flipped

	CGContextSetLineWidth( ctx, TEXT_SHADOW_WIDTH);
	CGContextSetLineJoin( ctx, kCGLineJoinRound );
	CGContextSetStrokeColorWithColor(ctx, shadowColor.CGColor);
	CGContextSetFillColorWithColor(ctx, shadowColor.CGColor);
	CGContextSetTextDrawingMode(ctx, kCGTextFillStroke);
	CGContextSetTextPosition(ctx, point.x, point.y);	// this applies a transform, so do it after flipping
	CTLineDraw(ct2, ctx);

	CGContextSetTextDrawingMode(ctx, kCGTextFill);
	CGContextSetFillColorWithColor(ctx, color.CGColor);
	CGContextSetTextPosition(ctx, point.x, point.y);	// this applies a transform, so do it after flipping
	CTLineDraw(ct1, ctx);

	CFRelease(ct1);
	CFRelease(ct2);
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
}

@end
