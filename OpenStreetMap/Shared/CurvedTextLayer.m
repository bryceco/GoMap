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

-(instancetype)init
{
	self = [super init];
	if ( self ) {
#if USE_CURVEDLAYER_CACHE
		_layerCache			= [NSCache new];
		_framesetterCache	= [NSCache new];
		_framesetterCache.delegate = self;
#endif
	}
	return self;
}

+(instancetype)shared
{
	static CurvedTextLayer * g_shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		g_shared = [CurvedTextLayer new];
	});
	return g_shared;
}


-(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset stroke:(BOOL)stroke color:(NSColor *)color context:(CGContextRef)ctx
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


-(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor context:(CGContextRef)ctx
{
	[self drawString:string alongPath:path offset:offset stroke:YES color:shadowColor context:ctx];
	[self drawString:string alongPath:path offset:offset stroke:NO  color:color		  context:ctx];
}

-(void)drawString:(NSString *)string centeredOnPoint:(CGPoint)center width:(CGFloat)lineWidth font:(NSFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor context:(CGContextRef)ctx
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

-(CTFramesetterRef)getFramesetterForString:(NSAttributedString *)attrString
{
	CTFramesetterRef framesetter = (__bridge CTFramesetterRef)[_framesetterCache objectForKey:attrString.string];
	if ( framesetter == NULL ) {
		framesetter = CTFramesetterCreateWithAttributedString( (__bridge CFAttributedStringRef)attrString );
		[_framesetterCache setObject:(__bridge id)framesetter forKey:attrString.string];
		CFRelease( framesetter );
	}
	return framesetter;
}

-(CGSize)sizeOfText:(NSAttributedString *)string
{
	CTFramesetterRef framesetter = [self getFramesetterForString:string];
	CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(70, CGFLOAT_MAX), NULL);
	return suggestedSize;
}

-(id)getCachedLayerForString:(NSString *)string color:(UIColor *)color
{
	if ( ![color isEqual:_cachedColor] ) {
		[_layerCache removeAllObjects];
		_cachedColor = color;
		return nil;
	}
	return [_layerCache objectForKey:string];
}

-(CALayer *)layerWithString:(NSString *)string width:(CGFloat)lineWidth font:(UIFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor
{
	CATextLayer * layer = [self getCachedLayerForString:string color:color];

	if ( layer == nil ) {

		layer = [CATextLayer new];

		if ( font == nil )
			font = [UIFont systemFontOfSize:10];
		NSAttributedString * s = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : (id)color.CGColor, NSFontAttributeName : font }];

		CGRect bounds = { 0 };
		bounds.size = [self sizeOfText:s];
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
		layer.shadowOpacity		= 0.3;
		CGPathRelease(shadowPath);

		[_layerCache setObject:layer forKey:string];
	}

	return layer;
}


static NSInteger EliminatePointsOnStraightSegments( NSInteger pointCount, CGPoint points[] )
{
	if ( pointCount < 3 )
		return pointCount;

	NSInteger dst = 1;
	for ( NSInteger	src = 1; src < pointCount-1; ++src ) {
		OSMPoint dir = {	points[src+1].x-points[dst-1].x,
							points[src+1].y-points[dst-1].y };
		dir = UnitVector(dir);
		double dist = DistanceFromLineToPoint( OSMPointFromCGPoint(points[dst-1]), dir, OSMPointFromCGPoint(points[src]) );
		if ( dist < 2.0 ) {
			// essentially a straight line, so remove point
		} else {
			points[ dst ] = points[ src ];
			++dst;
		}
	}
	points[ dst ] = points[ pointCount-1 ];
	return dst+1;
}

static NSInteger LongestStraightSegment( NSInteger pathPointCount, const CGPoint pathPoints[] )
{
	CGFloat longest = 0;
	NSInteger longestIndex = 0;
	for ( int i = 1; i < pathPointCount; ++i ) {
		CGPoint p1 = pathPoints[i-1];
		CGPoint p2 = pathPoints[i];
		CGPoint delta = { p1.x - p2.x, p1.y - p2.y };
		CGFloat len = hypot( delta.x, delta.y );
		if ( len > longest ) {
			longest = len;
			longestIndex = i-1;
		}
	}
	return longestIndex;
}


static BOOL PositionAndAngleForOffset( NSInteger pointCount, const CGPoint points[], double offset, double baselineOffsetDistance, CGPoint * pPos, CGFloat * pAngle, CGFloat * pLength )
{
	CGPoint	previous = points[0];

	for ( NSInteger	index = 1; index < pointCount; ++index ) {
		CGPoint pt = points[ index ];
		CGFloat dx = pt.x - previous.x;
		CGFloat dy = pt.y - previous.y;
		CGFloat len = hypot(dx,dy);
		CGFloat a = atan2f(dy,dx);

		if ( offset < len ) {
			// found it
			dx /= len;
			dy /= len;
			CGPoint baselineOffset = { dy * baselineOffsetDistance, -dx * baselineOffsetDistance };
			pPos->x = previous.x + offset * dx + baselineOffset.x;
			pPos->y = previous.y + offset * dy + baselineOffset.y;
			*pAngle = a;
			*pLength = len - offset;
			return YES;
		}
		offset -= len;
		previous = pt;
	}
	*pLength = 0;
	return NO;
}

-(NSArray *)layersWithString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(UIColor *)shadowColor
{
	static CTFontRef ctFont = NULL;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		ctFont = CTFontCreateUIFontForLanguage( kCTFontUIFontSystem, 14.0, NULL );
	});

	NSMutableArray * layers = [NSMutableArray new];

	// get line segments
	NSInteger pathPointCount = CGPathPointCount( path );
	CGPoint pathPoints[ pathPointCount ];
	CGPathGetPoints( path, pathPoints );
	pathPointCount = EliminatePointsOnStraightSegments( pathPointCount, pathPoints );
	if ( pathPointCount < 2 )
		return nil;

	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string
																		 attributes:@{
																					  (NSString *)kCTFontAttributeName : (__bridge id)ctFont,
																					  (NSString *)kCTForegroundColorAttributeName : (id)color.CGColor }];
	CTFramesetterRef framesetter = [self getFramesetterForString:attrString];
	NSInteger charCount = string.length;
	CTTypesetterRef typesetter = CTFramesetterGetTypesetter( framesetter );

	double lineHeight = 16.0; // CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0,attrString.length), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL).height;
	CFIndex currentCharacter = 0;
	double currentPixelOffset = offset;
	while ( currentCharacter < charCount ) {

		// get the number of characters that fit in the current path segment and create a text layer for it
		CGPoint pos = { 0, 0 };
		CGFloat angle = 0, length = 0;
		PositionAndAngleForOffset( pathPointCount, pathPoints, currentPixelOffset, lineHeight, &pos, &angle, &length );
		CFIndex count = CTTypesetterSuggestLineBreak( typesetter, currentCharacter, length );
#if USE_CURVEDLAYER_CACHE
		NSString * cacheKey = [NSString stringWithFormat:@"%@:%f",[string substringWithRange:NSMakeRange(currentCharacter, count)],angle];
		CATextLayer * layer = [self getCachedLayerForString:cacheKey color:color];
#else
		CATextLayer * layer = nil;
#endif
		CGFloat pixelLength;
		if ( layer == nil ) {
			layer = [CATextLayer layer];
			layer.actions			= @{ @"position" : [NSNull null] };
			NSAttributedString * attribSubstring = [attrString attributedSubstringFromRange:NSMakeRange(currentCharacter,count)];
			layer.string			= attribSubstring;
			CGRect bounds = { 0 };
			bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(currentCharacter,count), NULL, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX), NULL);
			pixelLength = bounds.size.width;
			layer.bounds			= bounds;
			layer.affineTransform	= CGAffineTransformMakeRotation( angle );
			layer.position			= pos;
			layer.anchorPoint		= CGPointMake(0,0);
			layer.truncationMode	= kCATruncationNone;
			layer.wrapped			= NO;
			layer.alignmentMode		= kCAAlignmentCenter;

			layer.shouldRasterize	= YES;
			layer.contentsScale		= [[UIScreen mainScreen] scale];

			CGPathRef	shadowPath	= CGPathCreateWithRect(bounds, NULL);
			layer.shadowColor		= shadowColor.CGColor;
			layer.shadowRadius		= 0.0;
			layer.shadowOffset		= CGSizeMake(0, 0);
			layer.shadowOpacity		= 0.3;
			layer.shadowPath		= shadowPath;
			CGPathRelease(shadowPath);

#if USE_CURVEDLAYER_CACHE
			[_layerCache setObject:layer forKey:cacheKey];
#endif
		} else {
			layer.position			= pos;
			pixelLength				= layer.bounds.size.width;
		}

		[layers addObject:layer];

		currentCharacter += count;
		currentPixelOffset += pixelLength;

		if ( [string characterAtIndex:currentCharacter-1] == ' ' )
			currentPixelOffset += 8;	// add room for space which is not included in framesetter size
	}
#if !USE_CURVEDLAYER_CACHE
	CFRelease(framesetter);
#endif
	return layers;
}

@end
