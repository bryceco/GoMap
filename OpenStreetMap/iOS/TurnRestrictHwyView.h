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


typedef enum {
	TURN_RESTRICT_NONE = 0,
	TURN_RESTRICT_NO = 1,
	TURN_RESTRICT_ONLY = 2
} TURN_RESTRICT;


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

@property (strong,nonatomic) BlockTurnRestrictHwyView	highwaySelectedCallback;
@property (strong,nonatomic) BlockTurnRestrictHwyView	restrictionChangedCallback;

@property (strong,nonatomic) UIButton *                 arrowButton;
@property (strong,nonatomic) NSArray *                  parentWaysArray;

@property (assign,nonatomic) TURN_RESTRICT				restriction;

-(void)createTurnRestrictionButton;
-(void)createOneWayArrowsForHighway;

-(BOOL)isOneWayExitingCenter;
-(BOOL)isOneWayEnteringCenter;

-(double)turnAngleDegreesFromPoint:(CGPoint)fromPoint;
-(void)rotateButtonForDirection;

+ (float)headingFromPoint:(CGPoint)a toPoint:(CGPoint)b;
+ (CGFloat)bearingDegreesFromPoint:(CGPoint)startingPoint toPoint:(CGPoint)endingPoint;

@end
