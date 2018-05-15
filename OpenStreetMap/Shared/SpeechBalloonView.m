//
//  SpeechBalloonView.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "SpeechBalloonLayer.h"
#import "SpeechBalloonView.h"

static const CGFloat arrowWidth = 20;
static const CGFloat arrowHeight = 48;

@implementation SpeechBalloonView

+ (Class)layerClass
{
	return [CAShapeLayer class];
}

- (id)initWithText:(NSString *)text
{
	self = [super initWithFrame:CGRectMake(0,0,0,0)];
	if ( self ) {

#if !TARGET_OS_IPHONE
		self.wantsLayer = YES;
#endif
		CAShapeLayer * shapeLayer = (id)self.layer;

		// shape layer
		shapeLayer.fillColor = NSColor.whiteColor.CGColor;
		shapeLayer.strokeColor = NSColor.blackColor.CGColor;
		shapeLayer.lineWidth = 6;

		// text layer
		CATextLayer * textLayer = [CATextLayer layer];
#if TARGET_OS_IPHONE
		UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
		textLayer.font = (__bridge CGFontRef)font;
#else
		NSFont * font = [[NSFontManager sharedFontManager] convertFont:[NSFont labelFontOfSize:12] toHaveTrait:NSBoldFontMask];
		textLayer.font = (__bridge CFTypeRef)font;
#endif
		textLayer.fontSize = 18;
		textLayer.alignmentMode = kCAAlignmentCenter;
		textLayer.string = text;
		textLayer.foregroundColor = NSColor.blackColor.CGColor;
		[shapeLayer addSublayer:textLayer];

		CGSize textSize = textLayer.preferredFrameSize;
		
		CGSize boxSize = textSize;
		boxSize.width += 35;
		boxSize.height += 30;
		
		// creat path with arrow
		const CGFloat cornerRadius = 14;
		_path = CGPathCreateMutable();
		double center = 0.35;
		CGPathMoveToPoint(_path, NULL, boxSize.width/2, boxSize.height+arrowHeight);	// arrow bottom
		CGPathAddLineToPoint(_path, NULL, boxSize.width*center-arrowWidth/2, boxSize.height);	// arrow top-left
		CGPathAddArcToPoint(_path, NULL, 0, boxSize.height, 0, 0, cornerRadius);	// bottom right corner
		CGPathAddArcToPoint(_path, NULL, 0, 0, boxSize.width, 0, cornerRadius);	// top left corner
		CGPathAddArcToPoint(_path, NULL, boxSize.width, 0, boxSize.width, boxSize.height, cornerRadius); // top right corner
		CGPathAddArcToPoint(_path, NULL, boxSize.width, boxSize.height, 0, boxSize.height, cornerRadius);	// bottom right corner
		CGPathAddLineToPoint(_path, NULL, boxSize.width*center+arrowWidth/2, boxSize.height );	// arrow top-right
		CGPathCloseSubpath(_path);
		CGRect viewRect = CGPathGetPathBoundingBox( _path );
		shapeLayer.path = _path;

		textLayer.frame = CGRectMake( (boxSize.width-textSize.width)/2, (boxSize.height-textSize.height)/2, textSize.width, textSize.height );

		self.frame = CGRectMake(0, 0, viewRect.size.width, viewRect.size.height);
	}
	return self;
}

- (void) setPoint:(CGPoint)point
{
	// set bottom center at point
	CGRect rect = self.frame;
	rect.origin.x = point.x - rect.size.width / 2;
	rect.origin.y = point.y - rect.size.height;
	self.frame = rect;
}

- (void)setTargetView:(UIView *)view
{
	CGRect rc = [view frame];
	CGPoint pt = { rc.origin.x + rc.size.width/2, rc.origin.y - rc.size.height/2 };
	[self setPoint:pt];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(NSEvent *)event
{
	if ( ![super pointInside:point withEvent:event] )
		return NO;
	if ( ! CGPathContainsPoint( _path, NULL, point, NO) )
		return NO;
	return YES;
}


- (void)dealloc
{
	CGPathRelease( _path );
}

@end
