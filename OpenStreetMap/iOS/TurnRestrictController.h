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

@property (strong, nonatomic) IBOutlet NSLayoutConstraint 	*	constraintViewWithTitleHeight;
@property (strong, nonatomic) IBOutlet NSLayoutConstraint 	*	constraintViewWithTitleWidth;
@property (strong, nonatomic) IBOutlet UIView 				* 	viewWithTitle;
@property (strong, nonatomic) IBOutlet UIView 				*	detailView;

@property (strong,nonatomic)    OsmNode 		*	centralNode;	// the central node

// these are used for screen calculations:
@property (assign,nonatomic)    CGPoint            	parentViewCenter;
@property (assign,nonatomic)    OSMTransform       	screenFromMapTransform;

@end
