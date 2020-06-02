//
//  MyApplication.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/11/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import "MyApplication.h"

@implementation MyApplication
-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_touches 	= [NSMutableDictionary new];
		_touchImage	= [UIImage imageNamed:@"Finger"];
	}
	return self;
}

static const CGFloat TOUCH_RADIUS = 22;

-(CGRect)rectForTouchPosition:(CGPoint)pos
{
	if ( _touchImage ) {
		CGRect rc = { pos, _touchImage.size };
		rc = CGRectOffset(rc, -_touchImage.size.width/2, -TOUCH_RADIUS);
		rc.origin.x += 15;	// extra so rotated finger is aligned
		rc.origin.y -= 10;	// extra so touches on toolbar or easier to see
		return rc;
	} else {
		return CGRectMake(pos.x-TOUCH_RADIUS, pos.y-TOUCH_RADIUS, 2*TOUCH_RADIUS, 2*TOUCH_RADIUS);
	}
}

-(void)sendEvent:(UIEvent *)event
{
	[super sendEvent:event];

	if ( !_showTouchCircles )
		return;

	for ( UITouch * touch in event.allTouches ) {

		CGPoint pos2 = [touch locationInView:nil];
		// if we double-tap then then second tap will be captured by our own window
		pos2 = [touch.window convertPoint:pos2 toWindow:nil];

		CGPoint pos = pos2;
		CGRect bounds = [[UIScreen mainScreen] bounds];

		switch ( [[UIDevice currentDevice] orientation] ) {
			case UIDeviceOrientationPortraitUpsideDown:
				pos.x = bounds.size.width  - pos2.x - 1;
				pos.y = bounds.size.height - pos2.y - 1;
				break;
			case UIDeviceOrientationLandscapeLeft:
				pos.x = bounds.size.height - pos2.y - 1;
				pos.y = pos2.x;
				break;
			case UIDeviceOrientationLandscapeRight:
				pos.x = pos2.y;
				pos.y = bounds.size.width - pos2.x - 1;
				break;
			default:
				break;
		}

		if ( touch.phase == UITouchPhaseBegan ) {
			UIWindow * win = [[UIWindow alloc] initWithFrame:[self rectForTouchPosition:pos]];
			_touches[@((long)touch)] = @{ @"win" : win, @"start" : @(touch.timestamp) };
			win.windowLevel = UIWindowLevelStatusBar;
			win.hidden = NO;
			if ( _touchImage ) {
				win.layer.contents = (id)_touchImage.CGImage;
				win.layer.affineTransform = CGAffineTransformMakeRotation(-M_PI/4);
			} else {
				win.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:1.0 alpha:1.0];
				win.layer.cornerRadius = TOUCH_RADIUS;
				win.layer.opacity = 0.85;
			}

		} else if ( touch.phase == UITouchPhaseMoved ) {
			NSDictionary * dict = _touches[ @((long)touch) ];
			UIWindow * win = dict[ @"win" ];
			win.layer.affineTransform = CGAffineTransformIdentity;
			win.frame = [self rectForTouchPosition:pos];
			win.layer.affineTransform = CGAffineTransformMakeRotation(-M_PI/4);
		} else if ( touch.phase == UITouchPhaseStationary ) {
			// ignore
		} else { // ended/cancelled
			// remove window after a slight delay so quick taps are still visible
			const double MIN_DISPLAY_INTERVAL = 0.5;
			NSDictionary * dict = _touches[ @((long)touch) ];
			NSTimeInterval delta = touch.timestamp - [dict[@"start"] doubleValue];
			if ( delta < MIN_DISPLAY_INTERVAL ) {
				delta = MIN_DISPLAY_INTERVAL - delta;
				__block UIWindow * win = dict[ @"win" ];
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delta * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					win = nil;
				});
			}
			[_touches removeObjectForKey:@((long)touch)];
		}
	}
}
@end
