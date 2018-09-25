//
//  CurvedTextLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

#import "iosapi.h"
#import "CurvedTextLayer.h"
#import "PathUtil.h"


@implementation CurvedTextLayer

-(instancetype)init
{
	self = [super init];
	if ( self ) {
#if USE_CURVEDLAYER_CACHE
		_layerCache					= [NSCache new];
		_layerCache.countLimit		= 100;

		_framesetterCache			= [NSCache new];
		_framesetterCache.delegate	= self;
		_framesetterCache.countLimit = 100;

		_textSizeCache				= [NSCache new];
		_textSizeCache.countLimit	= 100;
#endif

#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fontSizeDidChange:) name:UIContentSizeCategoryDidChangeNotification object:nil];
#endif
	}
	return self;
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)fontSizeDidChange:(NSNotification *)notification
{
	[_layerCache removeAllObjects];
	[_textSizeCache removeAllObjects];
	[_framesetterCache removeAllObjects];
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

-(CALayer *)layerWithString:(NSString *)string whiteOnBlock:(BOOL)whiteOnBlack
{
	CGFloat MAX_TEXT_WIDTH	= 100.0;

	// Don't cache these here because they are cached by the objects they are attached to
	CATextLayer * layer = [CATextLayer new];

#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
	UIColor * textColor   = whiteOnBlack ? UIColor.whiteColor : UIColor.blackColor;
	UIColor * shadowColor = whiteOnBlack ? UIColor.blackColor : UIColor.whiteColor;
	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string
																	  attributes:@{ NSForegroundColorAttributeName : (id)textColor.CGColor,
																					NSFontAttributeName : font }];

	CGRect bounds = { 0 };
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString( (__bridge CFAttributedStringRef)attrString );
	bounds.size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(MAX_TEXT_WIDTH, CGFLOAT_MAX), NULL);
	CFRelease( framesetter );
	bounds = CGRectInset( bounds, -3, -1 );
	bounds.size.width  = 2 * ceil( bounds.size.width/2 );	// make divisible by 2 so when centered on anchor point at (0.5,0.5) everything still aligns
	bounds.size.height = 2 * ceil( bounds.size.height/2 );
	layer.bounds = bounds;

	layer.string			= attrString;
	layer.truncationMode	= kCATruncationNone;
	layer.wrapped			= YES;
	layer.alignmentMode		= kCAAlignmentLeft;	// because our origin is -3 this is actually centered

	CGPathRef shadowPath	= CGPathCreateWithRect(bounds, NULL);
	layer.shadowPath		= shadowPath;
	layer.shadowColor		= shadowColor.CGColor;
	layer.shadowRadius		= 0.0;
	layer.shadowOffset		= CGSizeMake(0,0);
	layer.shadowOpacity		= 0.3;
	CGPathRelease(shadowPath);

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

#if 0
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
#endif

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


static BOOL IsRTL( CTTypesetterRef typesetter )
{
	BOOL isRTL = NO;
	CTLineRef fullLine = CTTypesetterCreateLine( typesetter, CFRangeMake(0,0) );
	NSArray * runs = (NSArray *)CTLineGetGlyphRuns( fullLine );
	if ( runs.count > 0 ) {
		CTRunRef run = CFBridgingRetain( runs[0] );
		CTRunStatus status = CTRunGetStatus(run);
		if ( status & kCTRunStatusRightToLeft ) {
			isRTL = YES;
		}
		CFRelease( run );
	}
	CFRelease( fullLine );
	return isRTL;
}

-(CTFramesetterRef)framesetterForString:(NSAttributedString *)attrString CF_RETURNS_RETAINED
{
	CTFramesetterRef framesetter = (__bridge CTFramesetterRef)[_framesetterCache objectForKey:attrString.string];
	if ( framesetter == NULL ) {
		framesetter = CTFramesetterCreateWithAttributedString( (__bridge CFAttributedStringRef)attrString );
		[_framesetterCache setObject:(__bridge id)framesetter forKey:attrString.string];
		return framesetter;
	}
	return CFRetain( framesetter );
}

-(CGSize)sizeOfText:(NSAttributedString *)string
{
	NSValue * size = [_textSizeCache objectForKey:string];
	if ( size ) {
#if TARGET_OS_IPHONE
		return size.CGSizeValue;
#else
		return size.sizeValue;
#endif
	}

	CTFramesetterRef framesetter = [self framesetterForString:string];
	CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(70, CGFLOAT_MAX), NULL);
	CFRelease( framesetter );
#if TARGET_OS_IPHONE
	NSValue * value = [NSValue valueWithCGSize:suggestedSize];
#else
	NSValue * value = [NSValue valueWithSize:suggestedSize];
#endif
	[_textSizeCache setObject:value forKey:string];
	return suggestedSize;
}

-(id)getCachedLayerForString:(NSString *)string whiteOnBlack:(BOOL)whiteOnBlack
{
	if ( _cachedColorIsWhiteOnBlack != whiteOnBlack ) {
		[_layerCache removeAllObjects];
		_cachedColorIsWhiteOnBlack = whiteOnBlack;
		return nil;
	}
	return [_layerCache objectForKey:string];
}

-(NSArray *)layersWithString:(NSString *)string alongPath:(CGPathRef)path whiteOnBlock:(BOOL)whiteOnBlack
{
#if TARGET_OS_IPHONE
	UIFont	* uiFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
#else
	NSFont * uiFont = [NSFont labelFontOfSize:12];
#endif

	UIColor * textColor = whiteOnBlack ? UIColor.whiteColor : UIColor.blackColor;
	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string
																		 attributes:@{
																					  (NSString *)kCTFontAttributeName : uiFont,
																					  (NSString *)kCTForegroundColorAttributeName : (id)textColor.CGColor }];
	CTFramesetterRef framesetter = [self framesetterForString:attrString];
	NSInteger charCount = string.length;
	CTTypesetterRef typesetter = CTFramesetterGetTypesetter( framesetter );

//	NSLog(@"\"%@\"",string);

	// get line segments
	NSInteger pathPointCount = CGPathPointCount( path );
	CGPoint pathPoints[ pathPointCount ];
	CGPathGetPoints( path, pathPoints );
	pathPointCount = EliminatePointsOnStraightSegments( pathPointCount, pathPoints );
	if ( pathPointCount < 2 ) {
		CFRelease( framesetter );
		return nil;
	}

	BOOL isRTL = IsRTL( typesetter );
	if ( isRTL ) {
		// reverse points
		for ( NSInteger i = 0; i < pathPointCount/2; ++i ) {
			CGPoint p = pathPoints[i];
			pathPoints[i] = pathPoints[pathPointCount-1-i];
			pathPoints[pathPointCount-1-i] = p;
		}
	}

	// center the text along the path
	CGFloat pathLength = 0.0;
	for ( NSInteger i = 1; i < pathPointCount; ++i ) {
		pathLength += hypot( pathPoints[i].x - pathPoints[i-1].x, pathPoints[i].y - pathPoints[i-1].y );
	}
	CGSize textSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRangeMake(0,string.length), nil, CGSizeMake(0,0), NULL);
	if ( textSize.width+8 >= pathLength ) {
		CFRelease( framesetter );
		return nil;
	}
	CGFloat offset = (pathLength - textSize.width) / 2;

	NSMutableArray * layers = [NSMutableArray new];

#if TARGET_OS_IPHONE
	double lineHeight = uiFont.lineHeight;
#else
	double lineHeight = uiFont.ascender + uiFont.descender + 2.0;
#endif
	CFIndex currentCharacter = 0;
	double currentPixelOffset = offset;
	while ( currentCharacter < charCount ) {

		if ( currentCharacter > 0 && isRTL ) {
			// doesn't fit on one segment so give up
			layers = nil;
			goto abort;
		}

		// get the number of characters that fit in the current path segment and create a text layer for it
		CGPoint pos = { 0, 0 };
		CGFloat angle = 0, length = 0;
		PositionAndAngleForOffset( pathPointCount, pathPoints, currentPixelOffset, lineHeight, &pos, &angle, &length );
		CFIndex count = CTTypesetterSuggestLineBreak( typesetter, currentCharacter, length );

#if USE_CURVEDLAYER_CACHE
		NSString * cacheKey = [NSString stringWithFormat:@"%@:%f",[string substringWithRange:NSMakeRange(currentCharacter, count)],angle];
		CATextLayer * layer = [self getCachedLayerForString:cacheKey whiteOnBlack:whiteOnBlack];
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
			if ( isRTL ) {
				pos.x += cos(angle)*pixelLength;
				pos.y += sin(angle)*pixelLength;
				pos.x -= sin(angle)*2*lineHeight;
				pos.y += cos(angle)*2*lineHeight;
				angle -= M_PI;
			}
			layer.affineTransform	= CGAffineTransformMakeRotation( angle );
			layer.position			= pos;
			layer.anchorPoint		= CGPointMake(0,0);
			layer.truncationMode	= kCATruncationNone;
			layer.wrapped			= NO;
			layer.alignmentMode		= kCAAlignmentCenter;

			layer.shouldRasterize	= YES;
#if TARGET_OS_IPHONE
			layer.contentsScale		= [[UIScreen mainScreen] scale];
#endif
			CGPathRef	shadowPath	= CGPathCreateWithRect(bounds, NULL);
			layer.shadowColor		= whiteOnBlack ? UIColor.blackColor.CGColor : UIColor.whiteColor.CGColor;
			layer.shadowRadius		= 0.0;
			layer.shadowOffset		= CGSizeMake(0, 0);
			layer.shadowOpacity		= 0.3;
			layer.shadowPath		= shadowPath;
			CGPathRelease(shadowPath);

#if USE_CURVEDLAYER_CACHE
			[_layerCache setObject:layer forKey:cacheKey];
#endif
		} else {
			pixelLength	= layer.bounds.size.width;
			if ( isRTL ) {
				pos.x += cos(angle)*pixelLength;
				pos.y += sin(angle)*pixelLength;
				pos.x -= sin(angle)*2*lineHeight;
				pos.y += cos(angle)*2*lineHeight;
				angle -= M_PI;
			}
			layer.position	= pos;
		}

//		NSLog(@"-> \"%@\"",[layer.string string]);

		[layers addObject:layer];

		currentCharacter += count;
		currentPixelOffset += pixelLength;

		if ( [string characterAtIndex:currentCharacter-1] == ' ' )
			currentPixelOffset += 8;	// add room for space which is not included in framesetter size
	}
abort:
	CFRelease(framesetter);
	return layers;
}

@end
