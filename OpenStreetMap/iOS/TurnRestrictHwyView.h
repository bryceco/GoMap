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

@property (strong,nonatomic) OsmRelation			*	objRel;		// associated relation
@property (strong,nonatomic) OsmWay					*	wayObj;		// associated way
@property (strong,nonatomic) OsmNode				*	centerNode;
@property (strong,nonatomic) OsmNode				*	connectedNode;

@property (assign, nonatomic) CGPoint					centerPoint;
@property (assign, nonatomic) CGPoint					endPoint;

@property (strong, nonatomic) CAShapeLayer			*	highlightLayer;
@property (strong, nonatomic) CAShapeLayer 			*	highwayLayer;

@property (strong,nonatomic) BlockTurnRestrictHwyView	lineSelectionCallback;
@property (strong,nonatomic) BlockTurnRestrictHwyView	lineButtonPressCallback;

@property (strong,nonatomic) UIButton *                 arrowButton;
@property (strong,nonatomic) NSArray *                  parentWaysArray;

-(void)createTurnRestrictionButton;
-(void)createOneWayArrowsForHighway;

-(BOOL)isOneWayExitingCenter;
-(BOOL)isOneWayEnteringCenter;

-(double)turnAngleDegreesFromPoint:(CGPoint)fromPoint;

+ (float)headingFromPoint:(CGPoint)a toPoint:(CGPoint)b;
+ (CGFloat)bearingDegreesFromPoint:(CGPoint)startingPoint toPoint:(CGPoint)endingPoint;

@end
