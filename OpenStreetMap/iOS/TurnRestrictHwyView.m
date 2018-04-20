//
//  TurnRestrictHwyView.m
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

#import "TurnRestrictHwyView.h"
#import "OsmObjects.h"
#import "VectorMath.h"


@implementation TurnRestrictHwyView


-(BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
	double dist = DistanceFromPointToLineSegment( OSMPointFromCGPoint(point), OSMPointFromCGPoint(_centerPoint), OSMPointFromCGPoint(_endPoint) );
	return dist < 10.0;	// touch within 10 pixels
}

-(NSString *)Id
{
	return _connectedNode.ident.stringValue;
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if ( _lineSelectionCallback )  {
		_lineSelectionCallback( self );
	}
}

-(CGPoint)midPointFrom:(CGPoint)p1 to:(CGPoint)p2
{
	CGPoint p = { (p1.x+p2.x)/2, (p1.y+p2.y)/2 };
	return p;
}

-(void)createArrowButton
{
	CGPoint location = [self midPointFrom:_centerPoint to:_endPoint];

	_arrowButton = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 30, 30)];
	[_arrowButton setImage:[UIImage imageNamed:@"arrowAllow"] forState:UIControlStateNormal];
	[_arrowButton setImage:[UIImage imageNamed:@"arrowRestrict"] forState:UIControlStateSelected];

	_arrowButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
	_arrowButton.center = location;
	CGFloat angle = [TurnRestrictHwyView getAngle:location b:self.center];
	_arrowButton.transform = CGAffineTransformMakeRotation(angle);
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
	CGPoint location	= [self midPointFrom:_centerPoint to:_endPoint];
	CGPoint locationA1 	= [self midPointFrom:_centerPoint to:location];
	CGPoint locationA2 	= [self midPointFrom:location to:_endPoint];

	[self createOneWayArrowAtPosition:location	 isDirection:forwardOneWay];
	[self createOneWayArrowAtPosition:locationA1 isDirection:forwardOneWay];
	[self createOneWayArrowAtPosition:locationA2 isDirection:forwardOneWay];
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

	CGFloat angle = isForward ? [TurnRestrictHwyView getAngle:location b:self.center] : [TurnRestrictHwyView getAngle:self.center b:location];
	arrow.affineTransform = CGAffineTransformMakeRotation(angle);
	arrow.position = location;

	arrow.fillColor = UIColor.blackColor.CGColor;
	[self.layer addSublayer:arrow];

	[self bringSubviewToFront:_arrowButton];
}


-(void)restrictionButtonPressed:(UIButton *)sender
{
	sender.selected = !sender.selected;

	if ( _lineButtonPressCallback )  {
		_lineButtonPressCallback(self);
	}
}

//MARK: Get angle of line connecting two points
+ (float) getAngle:(CGPoint)a b:(CGPoint)b
{
	CGFloat dx = b.x - a.x;
	CGFloat dy = b.y - a.y;
	CGFloat radians = atan2(-dx,dy);        // in radians
	return radians;
}

//MARK: Point Pair To Bearing Degree
+ (CGFloat) pointPairToBearingDegrees:(CGPoint)startingPoint secondPoint:(CGPoint)endingPoint
{
	CGPoint originPoint = CGPointMake(endingPoint.x - startingPoint.x, endingPoint.y - startingPoint.y); // get origin point to origin by subtracting end from start
	double bearingRadians = atan2(originPoint.y, originPoint.x); // get bearing in radians
	double bearingDegrees = bearingRadians * (180.0 / M_PI); // convert to degrees
	return bearingDegrees;
}
@end
