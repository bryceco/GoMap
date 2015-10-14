//
//  TapAndDragGesture.m
//  Go Map!!
//
//  Created by Bryce on 10/13/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import "TapAndDragGesture.h"

enum { NEED_FIRST_TAP, NEED_SECOND_TAP, NEED_DRAG, IS_DRAGGING };


static const NSTimeInterval DoubleTapTime = 0.5;

@implementation TapAndDragGesture


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesBegan:touches withEvent:event];

	if ( touches.count != 1 ) {
		self.state = _tapState == NEED_DRAG ? UIGestureRecognizerStateCancelled : UIGestureRecognizerStateFailed;
		return;
	}

	if ( _tapState == NEED_SECOND_TAP  &&  self.state == UIGestureRecognizerStatePossible ) {
		if ( [NSProcessInfo processInfo].systemUptime - _lastTouch.timestamp < DoubleTapTime ) {
			_tapState = NEED_DRAG;
		} else {
			_tapState = NEED_FIRST_TAP;
		}
	}
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesEnded:touches withEvent:event];

	if ( self.state != UIGestureRecognizerStatePossible && self.state != UIGestureRecognizerStateChanged )
		return;

	if ( _tapState == NEED_DRAG ) {
		self.state = UIGestureRecognizerStateFailed;
		return;
	}
	if ( _tapState == IS_DRAGGING ) {
		self.state = UIGestureRecognizerStateEnded;
		return;
	}
	NSLog(@"%f - %f\n", [NSProcessInfo processInfo].systemUptime, _lastTouch.timestamp );
	if ( _tapState == NEED_FIRST_TAP ) {
		_tapState = NEED_SECOND_TAP;
		_lastTouch = touches.anyObject;
	}
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesMoved:touches withEvent:event];

	UITouch * touch = touches.anyObject;
	CGPoint newPoint  = [touch locationInView:self.view];
	CGPoint prevPoint = [touch previousLocationInView:self.view];
	CGPoint delta = { newPoint.x - prevPoint.x, newPoint.y - prevPoint.y };
	if ( delta.x == 0 && delta.y == 0 )
		return;

	if ( _tapState != NEED_DRAG && _tapState != IS_DRAGGING ) {
		self.state = UIGestureRecognizerStateFailed;
		return;
	}
	if ( _tapState == NEED_DRAG ) {
		_tapState = IS_DRAGGING;
		_lastTouch = touches.anyObject;
		self.state = UIGestureRecognizerStateBegan;
	} else {
		_lastTouch = touches.anyObject;
		self.state = UIGestureRecognizerStateChanged;
	}
}



- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesCancelled:touches withEvent:event];

	self.state = UIGestureRecognizerStateFailed;
}

- (void)reset
{
	[super reset];
	_tapState = NEED_FIRST_TAP;
	_lastTouch = nil;
	NSLog(@"reset\n");
}

- (CGPoint)translationInView:(UIView *)view
{
	CGPoint newPoint  = [_lastTouch locationInView:view];
	CGPoint prevPoint = [_lastTouch previousLocationInView:view];
	CGPoint delta = { newPoint.x - prevPoint.x, newPoint.y - prevPoint.y };
	return delta;
}

@end
