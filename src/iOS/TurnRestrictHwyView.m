//
//  TurnRestrictHwyView.m
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

#import "TurnRestrictHwyView.h"
#import "VectorMath.h"

static CGPoint MidPointOf(CGPoint p1, CGPoint p2)
{
	CGPoint p = { (p1.x+p2.x)/2, (p1.y+p2.y)/2 };
	return p;
}


@implementation TurnRestrictHwyView


-(BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
	double dist = DistanceFromPointToLineSegment( OSMPointFromCGPoint(point), OSMPointFromCGPoint(_centerPoint), OSMPointFromCGPoint(_endPoint) );
	return dist < 10.0;	// touch within 10 pixels
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if ( _highwaySelectedCallback )  {
		_highwaySelectedCallback( self );
	}
}

-(void)rotateButtonForDirection
{
	if ( self.restriction == TURN_RESTRICT_NONE ) {
		CGFloat angle = [TurnRestrictHwyView headingFromPoint:_centerPoint toPoint:_endPoint];
		_arrowButton.transform = CGAffineTransformMakeRotation(M_PI+angle);
	} else {
		_arrowButton.transform = CGAffineTransformIdentity;
	}
}

-(void)createTurnRestrictionButton
{
	CGFloat dist = 0.5;
	CGPoint location = { _centerPoint.x + (_endPoint.x - _centerPoint.x)*dist, _centerPoint.y + (_endPoint.y - _centerPoint.y)*dist };

	_arrowButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 30, 30)];
	[_arrowButton setImage:[UIImage imageNamed:@"arrowAllow"] forState:UIControlStateNormal];

	_arrowButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
	_arrowButton.center = location;
	_arrowButton.layer.borderWidth = 1.0;
	_arrowButton.layer.cornerRadius = 2.0;
	_arrowButton.layer.borderColor = UIColor.blackColor.CGColor;

	[_arrowButton addTarget:self action:@selector(restrictionButtonPressed:) forControlEvents:UIControlEventTouchUpInside];

	[self addSubview:_arrowButton];
}

-(void)createOneWayArrowsForHighway
{
	if (_wayObj.isOneWay == ONEWAY_NONE)
		return;

	NSUInteger centerIndex = [_wayObj.nodes indexOfObject:_centerNode];
	NSUInteger otherIndex = [_wayObj.nodes indexOfObject:_connectedNode];
	BOOL forwardOneWay = (_wayObj.isOneWay == ONEWAY_FORWARD) == (otherIndex > centerIndex);

	// create 3 arrows on highway
	CGPoint location1	= MidPointOf(_centerPoint,_endPoint);
	CGPoint location2 	= MidPointOf(location1, _centerPoint);
	CGPoint location3 	= MidPointOf(location1, _endPoint);

	[self createOneWayArrowAtPosition:location1 isDirection:forwardOneWay];
	[self createOneWayArrowAtPosition:location2	isDirection:forwardOneWay];
	[self createOneWayArrowAtPosition:location3 isDirection:forwardOneWay];
}

-(void)createOneWayArrowAtPosition:(CGPoint)location isDirection:(BOOL)isForward
{
	//Height of the arrow
	CGFloat arrowHeight = 12;
	CGFloat arrowHeightHalf = arrowHeight/2;

	CGPoint p1 = CGPointMake(arrowHeightHalf, arrowHeightHalf);
	CGPoint p2 = CGPointMake(-arrowHeightHalf, arrowHeightHalf);
	CGPoint p3 = CGPointMake(0, -arrowHeightHalf);

	UIBezierPath * path = [UIBezierPath bezierPath];
	[path moveToPoint:p1];
	[path addLineToPoint:p3];
	[path addLineToPoint:p2];
	[path addLineToPoint:CGPointMake(0, 0)];
	[path closePath];
	
	CAShapeLayer * arrow = [CAShapeLayer new];
	arrow.path = path.CGPath; // arrowPath;
	arrow.lineWidth = 1.0;
	arrow.anchorPoint = CGPointMake(0.5, 0.5);

	CGFloat angle = isForward ? [TurnRestrictHwyView headingFromPoint:location toPoint:self.center] : [TurnRestrictHwyView headingFromPoint:self.center toPoint:location];
	arrow.affineTransform = CGAffineTransformMakeRotation(angle);
	arrow.position = location;

	arrow.fillColor = UIColor.blackColor.CGColor;
	[self.layer addSublayer:arrow];

	[self bringSubviewToFront:_arrowButton];
}

-(BOOL)isOneWayExitingCenter
{
	OsmWay * way = self.wayObj;
	if ( way.isOneWay ) {
		NSUInteger centerIndex = [way.nodes indexOfObject:_centerNode];
		NSUInteger otherIndex = [way.nodes indexOfObject:_connectedNode];
		if ( (otherIndex > centerIndex) == (way.isOneWay == ONEWAY_FORWARD) ) {
			return YES;
		}
	}
	return NO;
}

-(BOOL)isOneWayEnteringCenter
{
	OsmWay * way = self.wayObj;
	if ( way.isOneWay ) {
		NSUInteger centerIndex = [way.nodes indexOfObject:_centerNode];
		NSUInteger otherIndex = [way.nodes indexOfObject:_connectedNode];
		if ( (otherIndex < centerIndex) == (way.isOneWay == ONEWAY_FORWARD) ) {
			return YES;
		}
	}
	return NO;
}

-(void)restrictionButtonPressed:(UIButton *)sender
{
	if ( _restrictionChangedCallback )  {
		_restrictionChangedCallback(self);
	}
}

-(double)turnAngleDegreesFromPoint:(CGPoint)fromPoint
{
	double fromAngle = atan2( _centerPoint.y - fromPoint.y, _centerPoint.x - fromPoint.x);
	double toAngle   = atan2( _endPoint.y - _centerPoint.y, _endPoint.x - _centerPoint.x);
	double angle     = (toAngle - fromAngle) * 180 / M_PI;
	if ( angle > 180 )		angle -= 360;
	if ( angle <= -180 )	angle += 360;
	return angle;
}

// MARK: Get angle of line connecting two points
+ (float) headingFromPoint:(CGPoint)a toPoint:(CGPoint)b
{
	CGFloat dx = b.x - a.x;
	CGFloat dy = b.y - a.y;
	CGFloat radians = atan2(-dx,dy);        // in radians
	return radians;
}

//MARK: Point Pair To Bearing Degree
+ (CGFloat) bearingDegreesFromPoint:(CGPoint)startingPoint toPoint:(CGPoint)endingPoint
{
	double bearingRadians = atan2(endingPoint.y - startingPoint.y, endingPoint.x - startingPoint.x); // bearing in radians
	double bearingDegrees = bearingRadians * (180.0 / M_PI); // convert to degrees
	return bearingDegrees;
}
@end
