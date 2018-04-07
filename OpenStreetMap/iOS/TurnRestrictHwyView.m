//
//  TurnRestrictHwyView.m
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

#import "TurnRestrictHwyView.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "OsmMapData+Orthogonalize.h"
#import "OsmMapData+Straighten.h"
#import "OsmObjects.h"

@implementation TurnRestrictHwyView


-(BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
	UIColor *pixelColor = [self colorOfPoint:point withLayer:self.layer];
	if(CGColorGetAlpha(pixelColor.CGColor))
	{
		return YES;
	}
	return NO;
}

- (UIColor *)colorOfPoint:(CGPoint)point withLayer:(CALayer*)layer
{
	unsigned char pixel[4] = {0};

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace, kCGBitmapAlphaInfoMask & kCGImageAlphaPremultipliedLast);

	CGContextTranslateCTM(context, -point.x, -point.y);

	[layer renderInContext:context];

	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);

	//NSLog(@"pixel: %d %d %d %d", pixel[0], pixel[1], pixel[2], pixel[3]);

	UIColor *color = [UIColor colorWithRed:pixel[0]/255.0 green:pixel[1]/255.0 blue:pixel[2]/255.0 alpha:pixel[3]/255.0];

	return color;


}
- (void)drawRect:(CGRect)rect {
    // Drawing code
//    _isSeleted = false;
    [self createCenterPoint];
}

//MARK: Create Center Point
-(void)createCenterPoint
{
    //Center green circle with size 16px and green color
    UIView *centerView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, 16, 16)];
    centerView.backgroundColor = [UIColor greenColor];
    centerView.layer.cornerRadius = centerView.frame.size.height/2;
    centerView.center = self.center;
    [self addSubview:centerView];
}

//MARK:
//-(void)setIsSeleted:(BOOL)isSeleted
//{
//    _isSeleted = isSeleted;
//    if (_isSeleted)
//    {
//        _sLayer.strokeColor = [[UIColor redColor] CGColor];
//    }
//    else
//    {
//        _sLayer.strokeColor = [[UIColor blackColor] CGColor];
//    }
//}

//MARK: Touch Actions
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
//    self.isSeleted = !_isSeleted;
    
    if (_lineSelectionCallback != nil)
    {
        _lineSelectionCallback(self);
    }
}

//Gettng mid point between two points
-(CGPoint)midPointFrom:(CGPoint)p1 p2:(CGPoint)p2
{
    CGFloat x = MIN(p1.x, p2.x) + ABS(p1.x - p2.x)/2;
    CGFloat y = MIN(p1.y, p2.y) + ABS(p1.y - p2.y)/2;

    return CGPointMake(x, y);
}

//MARK: Create Arrow restriction Button
-(void)createArrowButton
{
    //CGPoint u =  [self intersectionOfLineFrom:newSelectedPoint to:newCenter withLineFrom:CGPointMake(170, 0) to:CGPointMake(170, 210)];
    
    CGPoint location = [self midPointFrom:_centerPoint p2:_endPoint];
    
    _layerButton = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 30, 30)];
    [_layerButton setImage:[UIImage imageNamed:@"arrowAllow"] forState:UIControlStateNormal];
    [_layerButton setImage:[UIImage imageNamed:@"arrowRestrict"] forState:UIControlStateSelected];
    
    _layerButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    _layerButton.center = location;
    [_layerButton addTarget:self action:@selector(layerButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_layerButton];
    
    CGFloat angle = [TurnRestrictHwyView getAngle:location b:self.center];
    
    [UIView animateWithDuration:0.5 animations:^{
        _layerButton.transform = CGAffineTransformMakeRotation(angle);
    }];
}

//MARK: Create One ways Arrows
-(void)createArrows
{
    if (_wayObj.isOneWay == ONEWAY_NONE)
    {
        return;
    }
    bool forwardOneWay = false;

    NSUInteger cIndex = [_wayObj.nodes indexOfObject:_connectedNode];
    NSUInteger adIndex = [_wayObj.nodes indexOfObject:_centerNode];
    
    if ((_wayObj.isOneWay == ONEWAY_FORWARD) && (cIndex > adIndex))
    {
        forwardOneWay = true;
    }
//    if (_wayObj.isOneWay == ONEWAY_FORWARD)
//    {
//        
//    }
    
    CGPoint location = [self midPointFrom:_centerPoint p2:_endPoint];
    
    CGPoint locationA1 = [self midPointFrom:_centerPoint p2:location];
    CGPoint locationA2 = [self midPointFrom:location p2:_endPoint];
    
//    NSLog(@"*** - %@,%@",_connectedNode.ident, _centerNode.ident);

    [self createOneWayArrowButtonWith:location isDirection:forwardOneWay];
    [self createOneWayArrowButtonWith:locationA1 isDirection:forwardOneWay];
    [self createOneWayArrowButtonWith:locationA2 isDirection:forwardOneWay];
}

//MARK: Draw One ways Arrow
-(void)createOneWayArrowButtonWith:(CGPoint)location isDirection:(BOOL)isForward
{
//    UIButton *arrowButton = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 10, 10)];
//    [arrowButton setImage:[UIImage imageNamed:@"arrowAllow"] forState:UIControlStateNormal];
//    [arrowButton setImage:[UIImage imageNamed:@"arrowRestrict"] forState:UIControlStateSelected];
//    [arrowButton setUserInteractionEnabled:false];
//    arrowButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
//
//    arrowButton.center = location;
//    [self addSubview:arrowButton];
//    [self bringSubviewToFront:_layerButton];
//

//    [UIView animateWithDuration:0.5 animations:^{
//        arrowButton.transform = CGAffineTransformMakeRotation(angle);
//    }];

    //Height of the arrow
    CGFloat arrowHeight = 12;
//    BOOL reversed = isForward;
//    double len = reversed ? -15 : 15;
//    double width = 5;
//
    CGPoint loc = CGPointMake(0, 0);
//    CGPoint dir = direction;
//
    CGFloat arrowHeightHalf = arrowHeight/2;

    CGPoint p1 = CGPointMake(loc.x+arrowHeightHalf, loc.y+arrowHeightHalf);
    CGPoint p2 = CGPointMake(loc.x-arrowHeightHalf, loc.y+arrowHeightHalf);
    CGPoint p3 = CGPointMake(loc.x, loc.y-arrowHeightHalf);

    CGMutablePathRef arrowPath = CGPathCreateMutable();
    CGPathMoveToPoint(arrowPath, NULL, p1.x, p1.y);
    CGPathAddLineToPoint(arrowPath, NULL, p3.x, p3.y);
    CGPathAddLineToPoint(arrowPath, NULL, p2.x, p2.y);
    CGPathAddLineToPoint(arrowPath, NULL, loc.x, loc.y);
    CGPathCloseSubpath(arrowPath);
//
    CAShapeLayer * arrow = [CAShapeLayer new];
    arrow.path = arrowPath;
    arrow.lineWidth = 1;
    arrow.anchorPoint = CGPointMake(0.5, 0.5);
    
    CGFloat angle = isForward ? [TurnRestrictHwyView getAngle:location b:self.center] : [TurnRestrictHwyView getAngle:self.center b:location];
    
//    NSLog(@"##### ");
//    NSLog(@" %s ,location - (%f,%f) ,self.center - (%f,%f) ,angle - %f",isForward ? "1" : "0", location.x,location.y, self.center.x,self.center.y, angle);
//    NSLog(@"#####");

    arrow.affineTransform = CGAffineTransformMakeRotation(angle);
    arrow.position = location;

    arrow.fillColor = UIColor.blackColor.CGColor;
//    arrow.zPosition    = Z_ARROWS;
    [self.layer addSublayer:arrow];
    
    [self bringSubviewToFront:_layerButton];

}


//MARK: Layer Button  Action
-(void)layerButtonAction:(UIButton*)sender
{
    sender.selected = !sender.selected;

    if (_lineButtonPressCallback != nil)
    {
        _lineButtonPressCallback(self);
    }
}

//MARK: Get Angle
+ (float) getAngle:(CGPoint)a b:(CGPoint)b
{
    int x = a.x;
    int y = a.y;
    float dx = b.x - x;
    float dy = b.y - y;
    CGFloat radians = atan2(-dx,dy);        // in radians
//    CGFloat degrees = radians * 180 / 3.14; // in degrees
    return    radians   ;//angle;
}

//MARK: Point Pair To Bearing Degree
+ (CGFloat) pointPairToBearingDegrees:(CGPoint)startingPoint secondPoint:(CGPoint)endingPoint
{
    CGPoint originPoint = CGPointMake(endingPoint.x - startingPoint.x, endingPoint.y - startingPoint.y); // get origin point to origin by subtracting end from start
    float bearingRadians = atan2f(originPoint.y, originPoint.x); // get bearing in radians
    float bearingDegrees = bearingRadians * (180.0 / M_PI); // convert to degrees
    bearingDegrees = (bearingDegrees > 0.0 ? bearingDegrees : (360.0 + bearingDegrees)); // correct discontinuity
    return bearingDegrees;
}
@end
