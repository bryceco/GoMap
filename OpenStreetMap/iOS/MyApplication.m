//
//  MyApplication.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 10/11/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import "MyApplication.h"

#if DEBUG
#define ENABLE_TOUCH_CIRCLES 0
#else
#define ENABLE_TOUCH_CIRCLES 0
#endif

#if ENABLE_TOUCH_CIRCLES
static const CGFloat TOUCH_RADIUS = 22;
#endif

@implementation MyApplication
-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_touches = [NSMutableDictionary new];
	}
	return self;
}

-(void)sendEvent:(UIEvent *)event
{
	[super sendEvent:event];

#if ENABLE_TOUCH_CIRCLES
	for ( UITouch * touch in event.allTouches ) {
		CGPoint pos2 = [touch locationInView:nil];
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
			UIWindow * win = [[UIWindow alloc] initWithFrame:CGRectMake(pos.x-TOUCH_RADIUS, pos.y-TOUCH_RADIUS, 2*TOUCH_RADIUS, 2*TOUCH_RADIUS)];
			_touches[@((long)touch)] = @{ @"win" : win, @"start" : @(touch.timestamp) };
			win.windowLevel = UIWindowLevelStatusBar;
			win.hidden = NO;
			win.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:1.0 alpha:1.0];
			win.layer.cornerRadius = TOUCH_RADIUS;
			win.layer.opacity = 0.85;
		} else if ( touch.phase == UITouchPhaseMoved ) {
			NSDictionary * dict = _touches[ @((long)touch) ];
			UIWindow * win = dict[ @"win" ];
			win.frame = CGRectMake(pos.x-TOUCH_RADIUS, pos.y-TOUCH_RADIUS, 2*TOUCH_RADIUS, 2*TOUCH_RADIUS);
		} else if ( touch.phase == UITouchPhaseStationary ) {
			// ignore
		} else { // ended/cancelled
			// remove window after a slight delay so quick taps are still visible
			const double MIN_DISPLAY_INTERVAL = 0.2;
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
#endif
}
@end
