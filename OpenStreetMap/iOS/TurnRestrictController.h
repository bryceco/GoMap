//
//  TurnRestrictController.h
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TurnRestrictHwyView.h"
#import "VectorMath.h"
#import "EditorMapLayer.h"
#import "TagInfo.h"

//width of the way line e.g 12, 17, 18 AND shadow width is +4 e.g 16, 21, 22
#define DEFAULT_POPUPLINEWIDTH        12


@class OsmNode;
@class OsmNotesDatabase;
@class OsmBaseObject;

@interface TurnRestrictController : UIViewController

@property (strong, nonatomic) IBOutlet NSLayoutConstraint *constraintContainerViewHeight;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint *constraintContainerViewWidth;

@property (strong, nonatomic) IBOutlet UIView *     containerView;
@property (strong, nonatomic) IBOutlet UIView *     viewWindowContainer;

@property (strong,nonatomic)    UIBezierPath *      bNodesPath;
@property (strong,nonatomic)    CAShapeLayer *      drawLayer;
@property (strong,nonatomic)    OsmNode *           selectedNode;
@property (strong,nonatomic)    NSMutableArray *    parentWays;
@property (assign,nonatomic)    CGPoint             mapCenter;
@property (assign,nonatomic)    CGFloat             birdsEyeRotation;
@property (assign,nonatomic)    CGFloat             birdsEyeDistance;
@property (assign,nonatomic)    OSMTransform        screenFromMapTransform;

@end
