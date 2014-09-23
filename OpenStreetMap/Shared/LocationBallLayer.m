//
//  LocationBallLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 12/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "LocationBallLayer.h"

@implementation LocationBallLayer

@synthesize showHeading = _showHeading;
@synthesize heading = _heading;
@synthesize headingAccuracy	= _headingAccuracy;
@synthesize radiusInPixels = _radiusInPixels;

- (id)init
{
	self = [super init];
	if ( self ) {
		self.frame = CGRectMake(0, 0, 16, 16);

		_radiusInPixels = 25.0;

		self.actions = @{
						 @"onOrderIn"	: [NSNull null],
						 @"onOrderOut"	: [NSNull null],
						 @"sublayers"	: [NSNull null],
						 @"contents"	: [NSNull null],
						 @"bounds"		: [NSNull null],
						 @"position"	: [NSNull null],
						 @"transform"	: [NSNull null],
						 };

		_ringLayer = [CAShapeLayer layer];
#if TARGET_OS_IPHONE
		_ringLayer.fillColor		= UIColor.clearColor.CGColor;
		_ringLayer.strokeColor	= [UIColor colorWithRed:0.5 green:0.5 blue:1.0 alpha:1.0].CGColor;
#else
		_ringLayer.fillColor		= [NSColor colorWithCalibratedRed:0.8 green:0.8 blue:1.0 alpha:0.4].CGColor;
		_ringLayer.strokeColor	= [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:1.0 alpha:1.0].CGColor;
#endif
		_ringLayer.lineWidth		= 2.0;
		_ringLayer.frame			= self.bounds;
		_ringLayer.position		= CGPointMake(16,16);

		CABasicAnimation * animation = [self ringAnimationWithRadius:100];

		[_ringLayer addAnimation:animation forKey:@"ring"];
		[self addSublayer:_ringLayer];

		CALayer * imageLayer = [CALayer layer];
		NSImage * image = [NSImage imageNamed:@"BlueBall"];
	#if TARGET_OS_IPHONE
		imageLayer.contents = (id)image.CGImage;
	#else
		imageLayer.contents = image;
	#endif
		imageLayer.frame = self.frame;
		[self addSublayer:imageLayer];
	}
	return self;
}

-(CABasicAnimation *)ringAnimationWithRadius:(CGFloat)radius
{
	CGFloat startRadius		= 5;
	CGFloat finishRadius	= radius;
	CGMutablePathRef startPath = CGPathCreateMutable();
	CGPathAddEllipseInRect( startPath, NULL, CGRectMake(-startRadius, -startRadius, 2*startRadius, 2*startRadius));

	CGMutablePathRef finishPath = CGPathCreateMutable();
	CGPathAddEllipseInRect( finishPath, NULL, CGRectMake(-finishRadius, -finishRadius, 2*finishRadius, 2*finishRadius));
	CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"path"];
	anim.duration		= 2.0;
	anim.fromValue		= (__bridge id)startPath;
	anim.toValue		= (__bridge id)finishPath;
	anim.removedOnCompletion = NO;
	anim.fillMode		= kCAFillModeForwards;
	anim.repeatCount	= HUGE_VALF;

	CGPathRelease(startPath);
	CGPathRelease(finishPath);

	return anim;
}


-(void)layoutSublayers
{
	if ( _showHeading && _headingAccuracy > 0 ) {
		if ( _headingLayer == nil ) {
			_headingLayer = [CAShapeLayer layer];
#if TARGET_OS_IPHONE
			_headingLayer.fillColor		= [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:0.4].CGColor;
			_headingLayer.strokeColor	= [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1.0].CGColor;
#else
			_headingLayer.fillColor		= [NSColor colorWithCalibratedRed:0.5 green:1.0 blue:0.5 alpha:0.4].CGColor;
			_headingLayer.strokeColor	= [NSColor colorWithCalibratedRed:0.0 green:1.0 blue:0.0 alpha:1.0].CGColor;
#endif
			_headingLayer.zPosition		= -1;
			CGRect rc = self.bounds;
			rc.origin.x += rc.size.width / 2;
			rc.origin.y += rc.size.height / 2;
			_headingLayer.frame = rc;
			[self addSublayer:_headingLayer];
		}

		// draw heading
		CGFloat radius = 40.0;
		CGMutablePathRef path = CGPathCreateMutable();
		CGPathAddArc(path, NULL, 0.0, 0.0, radius, _heading - _headingAccuracy, _heading + _headingAccuracy, NO);
		CGPathAddLineToPoint(path, NULL, 0, 0);
		CGPathCloseSubpath(path);
		_headingLayer.path = path;
		CGPathRelease(path);

	} else {
		if ( _headingLayer ) {
			[_headingLayer removeFromSuperlayer];
			_headingLayer = nil;
		}
	}
}

-(CGFloat)heading
{
	return _heading;
}
-(void)setHeading:(CGFloat)heading
{
#if TARGET_OS_IPHONE
	if ( _heading != heading ) {
		switch ( [[UIApplication sharedApplication] statusBarOrientation] ) {
			case UIDeviceOrientationPortraitUpsideDown:
				heading += M_PI;
				break;
			case UIDeviceOrientationLandscapeLeft:
				heading += M_PI/2;
				break;
			case UIDeviceOrientationLandscapeRight:
				heading -= M_PI/2;
				break;
			case UIDeviceOrientationPortrait:
			default:
				break;
		}

		_heading = heading;
		[self setNeedsLayout];
	}
#endif
}

-(BOOL)showHeading
{
	return _showHeading;
}
-(void)setShowHeading:(BOOL)showHeading
{
	if ( showHeading != _showHeading ) {
		_showHeading = showHeading;
		[self setNeedsLayout];
	}
}
-(CGFloat)headingAccuracy
{
	return _headingAccuracy;
}
-(void)setHeadingAccuracy:(CGFloat)headingAccuracy
{
	if ( _headingAccuracy != headingAccuracy ) {
		_headingAccuracy = headingAccuracy;
		[self setNeedsLayout];
	}
}

-(void)setRadiusInPixels:(CGFloat)radiusInPixels
{
	if ( _radiusInPixels != radiusInPixels ) {
		_radiusInPixels = radiusInPixels;
		CABasicAnimation * animation = [self ringAnimationWithRadius:_radiusInPixels];
		[_ringLayer addAnimation:animation forKey:@"ring"];
	}
}

@end
