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

@interface CurvedTextLayer : CALayer
{
}

+(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor context:(CGContextRef)ctx;
+(void)drawString:(NSString *)string centeredOnPoint:(CGPoint)point width:(CGFloat)lineWidth font:(UIFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor context:(CGContextRef)ctx;

@end
