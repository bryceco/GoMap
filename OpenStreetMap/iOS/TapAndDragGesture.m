//
//  TapAndDragGesture.m
//  Go Map!!
//
//  Created by Bryce on 10/13/15.
//  Copyright © 2015 Bryce. All rights reserved.
//

#import "TapAndDragGesture.h"

enum { NEED_FIRST_TAP, NEED_SECOND_TAP, NEED_DRAG, IS_DRAGGING };



#undef DEBUG


static const NSTimeInterval DoubleTapTime = 0.5;

@implementation TapAndDragGesture

#if DEBUG
- (void)showState
{
	NSString * state;
	switch (_tapState) {
		case NEED_FIRST_TAP:
			state = @"need first";
			break;
		case NEED_SECOND_TAP:
			state = @"need second";
			break;
		case NEED_DRAG:
			state = @"need drag";
			break;
		case IS_DRAGGING:
			state = @"dragging";
			break;
		default:
			state = nil;
	}
	NSLog(@"state = %@\n", state );
}
#endif


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesBegan:touches withEvent:event];
#if DEBUG
	NSLog(@"began\n");
#endif
	if ( touches.count != 1 ) {
		self.state = _tapState == NEED_DRAG ? UIGestureRecognizerStateCancelled : UIGestureRecognizerStateFailed;
		return;
	}

	if ( _tapState == NEED_SECOND_TAP  &&  self.state == UIGestureRecognizerStatePossible ) {
		UITouch * touch = touches.anyObject;
		CGPoint loc = [touch locationInView:self.view];
		if ( [NSProcessInfo processInfo].systemUptime - _lastTouchTimestamp < DoubleTapTime  &&  fabs(_lastTouchLocation.x - loc.x) < 100 && fabs(_lastTouchLocation.y - loc.y) < 100 ) {
			_tapState = NEED_DRAG;
		} else {
#if DEBUG
			NSLog(@"2nd tap too slow or too far away\n");
			NSLog(@"%f,%f vs %f,%f\n",_lastTouchLocation.x,_lastTouchLocation.y,loc.x,loc.y);
#endif
			_tapState = NEED_FIRST_TAP;
			_lastTouchLocation = [touch locationInView:self.view];
		}
	}
#if DEBUG
	[self showState];
#endif
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
#if DEBUG
	NSLog(@"ended\n");
#endif
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
#if DEBUG
	[self showState];
#endif
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesMoved:touches withEvent:event];

	UITouch * touch = touches.anyObject;
	CGPoint delta = TouchTranslation(touch,self.view);
	if ( delta.x == 0 && delta.y == 0 )
		return;

#if DEBUG
	NSLog(@"moved\n");
#endif
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
#if DEBUG
	[self showState];
#endif
}



- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
	[super touchesCancelled:touches withEvent:event];

	self.state = UIGestureRecognizerStateFailed;
}

- (void)reset
{
#if DEBUG
	NSLog(@"reset\n");
#endif
	[super reset];
	_tapState = NEED_FIRST_TAP;
#if DEBUG
	[self showState];
#endif
}

- (CGPoint)translationInView:(UIView *)view
{
	return _lastTouchTranslation;
}

@end
