//
//  CurvedTextLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "iosapi.h"

@class NSTextStorage;
@class NSLayoutManager;
@class NSTextContainer;

#define USE_CURVEDLAYER_CACHE 1

@interface CurvedTextLayer : NSObject <NSCacheDelegate>
{
#if USE_CURVEDLAYER_CACHE
	NSCache	*	_layerCache;
	NSCache	*	_framesetterCache;
	NSCache	*	_textSizeCache;
	BOOL		_cachedColorIsWhiteOnBlack;
#endif
}

+(instancetype)shared;

-(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor context:(CGContextRef)ctx;
-(void)drawString:(NSString *)string centeredOnPoint:(CGPoint)point width:(CGFloat)lineWidth font:(UIFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor context:(CGContextRef)ctx;

-(CALayer *)layerWithString:(NSString *)string whiteOnBlock:(BOOL)whiteOnBlack;
-(NSArray *)layersWithString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset whiteOnBlock:(BOOL)whiteOnBlack;

@end
