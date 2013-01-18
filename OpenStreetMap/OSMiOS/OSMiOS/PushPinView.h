//
//  PushPinView.h
//  OSMiOS
//
//  Created by Bryce on 12/16/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void (^	PushPinViewDragCallback)(UIGestureRecognizerState state, CGFloat dx, CGFloat dy);

@interface PushPinView : UIButton
{
	CGPoint					_panCoord;
	UIGestureRecognizer	*	_panRecognizer;

	CGMutablePathRef		_path;
	CAShapeLayer		*	_shapeLayer;	// shape for balloon
	CATextLayer			*	_textLayer;		// text in balloon
	CALayer				*	_placeholderLayer;

	CALayer				*	_moveButton;

	NSMutableArray		*	_buttonList;
	NSMutableArray		*	_callbackList;
	NSMutableArray		*	_lineLayers;
}

@property (strong,nonatomic)	UIImage					*	placeholderImage;
@property (copy,nonatomic)		NSString				*	text;
@property (assign,nonatomic)	CGPoint						arrowPoint;
@property (strong,nonatomic)	PushPinViewDragCallback		dragCallback;
@property (assign,nonatomic)	BOOL						labelOnBottom;


- (void)addButton:(UIButton *)button callback:(void(^)(void))callback;
- (void)animateMoveFrom:(CGPoint)startPos;

@end
