//
//  PushPinView.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "DLog.h"
#import "PushPinView.h"

@implementation PushPinView

@synthesize arrowPoint = _arrowPoint;
@synthesize placeholderLayer = _placeholderLayer;
@synthesize labelOnBottom = _labelOnBottom;

- (id)init
{
    self = [super initWithFrame:CGRectZero];
	if (self) {

		_labelOnBottom = YES;

		_shapeLayer = [CAShapeLayer layer];
		_shapeLayer.fillColor = UIColor.grayColor.CGColor;
		_shapeLayer.strokeColor = UIColor.whiteColor.CGColor;
		_shapeLayer.shadowColor = UIColor.blackColor.CGColor;
		_shapeLayer.shadowOffset = CGSizeMake(3,3);
		_shapeLayer.shadowOpacity = 0.6;
		[self.layer addSublayer:_shapeLayer];

		// text layer
		_textLayer = [CATextLayer layer];
        _textLayer.contentsScale = UIScreen.mainScreen.scale;
		
		UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
		_textLayer.font 			= (__bridge CFTypeRef)font;
		_textLayer.fontSize 		= font.pointSize;
		_textLayer.alignmentMode	= kCAAlignmentLeft;
		_textLayer.truncationMode	= kCATruncationEnd;

		_textLayer.foregroundColor 	= UIColor.whiteColor.CGColor;
		[_shapeLayer addSublayer:_textLayer];

		_moveButton = [CALayer layer];
		_moveButton.frame 			= CGRectMake( 0, 0, 25, 25 );
		_moveButton.contents 		= (__bridge id)[UIImage imageNamed:@"move.png"].CGImage;
		[_shapeLayer addSublayer:_moveButton];

		_placeholderLayer = [CALayer layer];
		[_shapeLayer addSublayer:_placeholderLayer];

		[self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(draggingGesture:)]];
	}
	return self;
}

-(void)dealloc
{
}

-(NSString *)text
{
	return _textLayer.string;
}
-(void)setText:(NSString *)text
{
	if ( [text isEqualToString:_textLayer.string] )
		return;
	_textLayer.string = text;
	[self updateShape];
}

-(CGPoint)arrowPoint
{
	return _arrowPoint;
}
-(void)setArrowPoint:(CGPoint)arrowPoint
{
	if ( isnan(arrowPoint.x) || isnan(arrowPoint.y) ) {
		DLog(@"bad arrow location");
		return;
	}
	_arrowPoint = arrowPoint;
	self.center = CGPointMake( arrowPoint.x, arrowPoint.y + self.bounds.size.height/2 );
}

-(CALayer *)placeholderLayer
{
	return _placeholderLayer;
}

-(BOOL)labelOnBottom
{
	return _labelOnBottom;
}
-(void)setLabelOnBottom:(BOOL)labelOnBottom
{
	if ( labelOnBottom != _labelOnBottom ) {
		_labelOnBottom = labelOnBottom;
		[self updateShape];
	}
}


- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	if ( CGRectContainsPoint( _hittestRect, point ) )
		return self;
	for ( UIButton * button in _buttonList ) {
		CGPoint point2 = [button convertPoint:point fromView:self];
		UIView * hit = [button hitTest:point2 withEvent:event];
		if ( hit )
			return hit;
	}
	return nil;
}

-(void)updateShape
{
	CGSize	textSize = _textLayer.preferredFrameSize;
	if ( textSize.width > 300 )
		textSize.width = 300;

	const NSInteger buttonCount = MAX(_buttonList.count,1);
	const CGFloat	moveButtonGap = 3.0;
	const CGFloat	buttonVerticalSpacing = 55;
	const CGFloat	textAlleyWidth = 5;
	const CGSize	boxSize = { textSize.width + 2*textAlleyWidth + moveButtonGap + _moveButton.frame.size.width,
								textSize.height + 2*textAlleyWidth };
	const CGFloat	arrowHeight = 20 + (buttonCount * buttonVerticalSpacing)/2;
	const CGFloat	arrowWidth = 20;
	const CGFloat	buttonHorzOffset = 44;
	const CGFloat	buttonHeight = _buttonList.count ? [_buttonList[0] frame].size.height : 0;

	CGFloat topGap	= buttonHeight/2 + (buttonCount-1)*buttonVerticalSpacing/2;

	// creat path with arrow
	const CGFloat cornerRadius = 4;
	CGMutablePathRef viewPath = CGPathCreateMutable();
	if ( _labelOnBottom ) {
		_hittestRect = CGRectMake( 0, arrowHeight, boxSize.width, boxSize.height );
		CGPathMoveToPoint(viewPath, NULL, boxSize.width/2, 0);	// arrow top
		CGPathAddLineToPoint(viewPath, NULL, boxSize.width/2-arrowWidth/2, arrowHeight);	// arrow top-left
		CGPathAddArcToPoint(viewPath, NULL, 0, arrowHeight, 0, boxSize.height+arrowHeight, cornerRadius);	// bottom right corner
		CGPathAddArcToPoint(viewPath, NULL, 0, boxSize.height+arrowHeight, boxSize.width, boxSize.height+arrowHeight, cornerRadius);	// top left corner
		CGPathAddArcToPoint(viewPath, NULL, boxSize.width, boxSize.height+arrowHeight, boxSize.width, arrowHeight, cornerRadius); // top right corner
		CGPathAddArcToPoint(viewPath, NULL, boxSize.width, arrowHeight, 0, arrowHeight, cornerRadius);	// bottom right corner
		CGPathAddLineToPoint(viewPath, NULL, boxSize.width/2+arrowWidth/2, arrowHeight );	// arrow top-right
		CGPathCloseSubpath(viewPath);
	} else {
		CGPathMoveToPoint(viewPath, NULL, boxSize.width/2, boxSize.height+arrowHeight);	// arrow bottom
		CGPathAddLineToPoint(viewPath, NULL, boxSize.width/2-arrowWidth/2, boxSize.height);	// arrow top-left
		CGPathAddArcToPoint(viewPath, NULL, 0, boxSize.height, 0, 0, cornerRadius);	// bottom right corner
		CGPathAddArcToPoint(viewPath, NULL, 0, 0, boxSize.width, 0, cornerRadius);	// top left corner
		CGPathAddArcToPoint(viewPath, NULL, boxSize.width, 0, boxSize.width, boxSize.height, cornerRadius); // top right corner
		CGPathAddArcToPoint(viewPath, NULL, boxSize.width, boxSize.height, 0, boxSize.height, cornerRadius);	// bottom right corner
		CGPathAddLineToPoint(viewPath, NULL, boxSize.width/2+arrowWidth/2, boxSize.height );	// arrow top-right
		CGPathCloseSubpath(viewPath);
	}

	// make hit target a little larger
	_hittestRect = CGRectInset( _hittestRect, -7, -7 );

	CGRect viewRect = CGPathGetPathBoundingBox( viewPath );
	_shapeLayer.frame = CGRectMake( 0, 0, 20, 20 );	// arbitrary since it is a shape
	_shapeLayer.path = viewPath;
	_shapeLayer.shadowPath = viewPath;
	CGPathRelease( viewPath );

	if ( _labelOnBottom ) {
		_textLayer.frame = CGRectMake( textAlleyWidth, topGap+arrowHeight+textAlleyWidth,
									  boxSize.width - textAlleyWidth, textSize.height );
		_moveButton.frame = CGRectMake( boxSize.width - _moveButton.frame.size.width - 3,
									   topGap + arrowHeight+(boxSize.height-_moveButton.frame.size.height)/2,
									   _moveButton.frame.size.width,
									   _moveButton.frame.size.height );
	} else {
		_textLayer.frame = CGRectMake( textAlleyWidth, textAlleyWidth, boxSize.width - textAlleyWidth, boxSize.height - textAlleyWidth );
	}

	// place buttons
	CGRect rc = viewRect;
	for ( NSInteger i = 0; i < _buttonList.count; ++i ) {
		// place button
		UIButton * button = _buttonList[i];
		CGRect buttonRect;
		buttonRect.size = button.frame.size;
		if ( _labelOnBottom ) {
			buttonRect.origin = CGPointMake( viewRect.size.width/2 + buttonHorzOffset,
											 i*buttonVerticalSpacing );
		} else {
			buttonRect.origin = CGPointMake( viewRect.size.width/2 + buttonHorzOffset,
											viewRect.size.height + (i - _buttonList.count/2.0)*buttonVerticalSpacing + 5 );
		}
		button.frame = buttonRect;

		// place line to button
		CAShapeLayer * line = _lineLayers[i];
		CGMutablePathRef buttonPath = CGPathCreateMutable();
		CGPoint start	= { viewRect.size.width/2, _labelOnBottom ? topGap : viewRect.size.height };
		CGPoint end		= { buttonRect.origin.x + buttonRect.size.width/2, buttonRect.origin.y + buttonRect.size.height/2 };
		double dx = end.x - start.x;
		double dy = end.y - start.y;
		double dist = hypot( dx, dy );
		start.x += 15 * dx / dist;
		start.y += 15 * dy / dist;
		end.x	-= 15 * dx / dist;
		end.y	-= 15 * dy / dist;
		CGPathMoveToPoint( buttonPath, NULL, start.x, start.y );
		CGPathAddLineToPoint(buttonPath, NULL, end.x, end.y );
		line.path = buttonPath;
		CGPathRelease(buttonPath);
		
		// get union of subviews
		rc = CGRectUnion( rc, buttonRect );
	}

	_placeholderLayer.position = CGPointMake( viewRect.size.width/2, _labelOnBottom ? topGap : viewRect.size.height );

	if ( _labelOnBottom ) {
		self.frame = CGRectMake( _arrowPoint.x - viewRect.size.width/2, _arrowPoint.y - topGap, rc.size.width, rc.size.height);
	} else {
		self.frame = CGRectMake( _arrowPoint.x - viewRect.size.width/2, _arrowPoint.y - viewRect.size.height, rc.size.width, rc.size.height);
	}
}

-(void)buttonPress:(id)sender
{
	NSInteger index = [_buttonList indexOfObject:sender];
	assert( index != NSNotFound );
	void (^callback)(void) = _callbackList[ index ];
	callback();
}

- (void)addButton:(UIButton *)button callback:(void (^)(void))callback
{
	assert( button && callback );
	CAShapeLayer * line = [CAShapeLayer layer];
	if ( _buttonList == nil ) {
		_buttonList = [NSMutableArray arrayWithObject:button];
		_callbackList = [NSMutableArray arrayWithObject:callback];
		_lineLayers = [NSMutableArray arrayWithObject:line];
	} else {
		[_buttonList addObject:button];
		[_callbackList addObject:callback];
		[_lineLayers addObject:line];
	}
	line.lineWidth = 2.0;
	line.strokeColor = UIColor.whiteColor.CGColor;
	line.shadowColor = UIColor.blackColor.CGColor;
	line.shadowRadius = 5;
	[_shapeLayer addSublayer:line];

	[self addSubview:button];
	[button addTarget:self action:@selector(buttonPress:) forControlEvents:UIControlEventTouchUpInside];

	[self updateShape];
}



- (void)animateMoveFrom:(CGPoint)startPos
{
	[self layoutIfNeeded];

	CGPoint			posA		= startPos;
	CGPoint			posC		= self.layer.position;
	CGPoint			posB		= { posC.x, posA.y };
	
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathMoveToPoint( path, NULL, posA.x, posA.y );
	CGPathAddQuadCurveToPoint ( path, NULL, posB.x, posB.y, posC.x, posC.y );

	CAKeyframeAnimation *	theAnimation;
	theAnimation						= [CAKeyframeAnimation animationWithKeyPath:@"position"];
	theAnimation.path					= path;
	theAnimation.timingFunction			= [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
	theAnimation.repeatCount			= 0;
	theAnimation.removedOnCompletion	= YES;
	theAnimation.fillMode				= kCAFillModeBoth;
	theAnimation.duration				= 0.5;

	// let us get notified when animation completes
	theAnimation.delegate				= self;

	self.layer.position = posC;
	[self.layer addAnimation:theAnimation forKey:@"animatePosition"];

	CGPathRelease( path );
}

-(void)draggingGesture:(UIPanGestureRecognizer *)gesture
{
	CGPoint newCoord = [gesture locationInView:gesture.view];
	CGFloat dX = 0;
	CGFloat dY = 0;

	if ( gesture.state == UIGestureRecognizerStateBegan ) {
		_panCoord = newCoord;
	} else {
		dX = newCoord.x - _panCoord.x;
		dY = newCoord.y - _panCoord.y;
		_arrowPoint = CGPointMake( _arrowPoint.x + dX, _arrowPoint.y + dY );

		CGPoint newCenter = { self.center.x + dX, self.center.y + dY };
		gesture.view.center = newCenter;
	}

	if ( _dragCallback ) {
		_dragCallback( gesture.state, dX, dY, gesture );
	}
}

@end
