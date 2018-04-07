//
//  TurnRestrictHwyView.h
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce. All rights reserved.
//

@class TurnRestrictHwyView;
@class OsmNode;
@class OsmWay;
@class OsmRelation;
@class OsmNotesDatabase;
@class OsmBaseObject;


typedef void(^BlockTurnRestrictHwyView)(TurnRestrictHwyView *objLine);

@interface TurnRestrictHwyView : UIView

@property (strong,nonatomic) TurnRestrictHwyView *             fromLine;
@property (strong,nonatomic) OsmRelation *              objRel;
@property (strong,nonatomic) OsmWay	*                   wayObj;
@property (strong,nonatomic) OsmNode	*               centerNode;
@property (strong,nonatomic) OsmNode	*               connectedNode;

@property (strong,nonatomic)    UIColor *               wayColor;
@property (assign, nonatomic)   CGPoint                 centerPoint;
@property (assign, nonatomic)   CGPoint                 endPoint;

@property (strong, nonatomic) CAShapeLayer *            shadowLayer;
@property (strong, nonatomic) CAShapeLayer *            sLayer;
@property (strong, nonatomic) UIBezierPath *            bPath;

@property (strong, nonatomic) NSString *Id;

//@property (assign, nonatomic) BOOL                      isSeleted;


@property (strong,nonatomic) BlockTurnRestrictHwyView          lineSelectionCallback;
@property (strong,nonatomic) BlockTurnRestrictHwyView          lineButtonPressCallback;

@property (strong,nonatomic) UIButton *                 layerButton;



@property (strong,nonatomic) NSArray *                  parentWaysArray;

-(void)createArrowButton;
-(void)createCenterPoint;
-(void)createArrows;

+ (float) getAngle:(CGPoint)a b:(CGPoint)b;
+ (CGFloat) pointPairToBearingDegrees:(CGPoint)startingPoint secondPoint:(CGPoint)endingPoint;

@end
