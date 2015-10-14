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
		UITouch * touch = touches.anyObject;
		CGPoint loc = [touch locationInView:self.view];
		if ( [NSProcessInfo processInfo].systemUptime - _lastTouchTimestamp < DoubleTapTime  &&  fabs(_lastTouchLocation.x - loc.x) < 20 && fabs(_lastTouchLocation.y - loc.y) < 20 ) {
			_tapState = NEED_DRAG;
		} else {
			_tapState = NEED_FIRST_TAP;
			_lastTouchLocation = [touch locationInView:self.view];
		}
	}
}

static CGPoint TouchTranslation( UITouch * touch, UIView * view )
{
	CGPoint newPoint  = [touch locationInView:view];
	CGPoint prevPoint = [touch previousLocationInView:view];
	CGPoint delta = { newPoint.x - prevPoint.x, newPoint.y - prevPoint.y };
	return delta;
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
	if ( _tapState == NEED_FIRST_TAP ) {
		_tapState = NEED_SECOND_TAP;
		UITouch * touch = touches.anyObject;
		_lastTouchTimestamp = touch.timestamp;
	}
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesMoved:touches withEvent:event];

	UITouch * touch = touches.anyObject;
	CGPoint delta = TouchTranslation(touch,self.view);
	if ( delta.x == 0 && delta.y == 0 )
		return;

	if ( _tapState != NEED_DRAG && _tapState != IS_DRAGGING ) {
		self.state = UIGestureRecognizerStateFailed;
		return;
	}
	if ( _tapState == NEED_DRAG ) {
		_tapState = IS_DRAGGING;
		self.state = UIGestureRecognizerStateBegan;
	} else {
		self.state = UIGestureRecognizerStateChanged;
	}
	_lastTouchTimestamp = touch.timestamp;
	_lastTouchTranslation = delta;
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
}

- (CGPoint)translationInView:(UIView *)view
{
	return _lastTouchTranslation;
}

@end
