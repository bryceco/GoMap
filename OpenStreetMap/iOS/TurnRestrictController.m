//
//  TurnRestrictController.m
//  Go Map!!
//
//  Created by Mukul Bakshi on 02/11/17.
//  Copyright © 2017 Bryce Cogswell. All rights reserved.
//

#import "TurnRestrictController.h"

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "OsmMapData+Orthogonalize.h"
#import "OsmMapData+Straighten.h"
#import "OsmObjects.h"


@interface TurnRestrictController ()
{
	NSMutableArray		*	_parentWays;
	NSMutableArray		*	_highwayViewArray; //	Array of TurnRestrictHwyView to Store number of ways

	TurnRestrictHwyView	*	_selectedHwy;
	UIButton			*   _uTurnButton;
	OsmRelation 		*   _currentUTurnRelation;

	NSMutableArray		*	_allRelations;
	NSMutableArray		*	_editedRelations;
}
@end


@implementation TurnRestrictController

- (void)viewDidLoad
{
    [super viewDidLoad];
    _highwayViewArray = [[NSMutableArray alloc] init];
    [self createMapWindow];
}

// To dray Popup window
-(void)createMapWindow
{
	// Popup Window Size iPhone
	CGSize size = { 240, 220 };
	if ( [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ) {
		//Popup Window 2X Size iPad
		size.width *= 2;
		size.height *= 2;
	}
	size.height += 30;	// Popup Window Topbar height
	_constraintViewWithTitleWidth.constant = size.width;
	_constraintViewWithTitleHeight.constant = size.height;

	[self.view layoutIfNeeded];

	_detailView.clipsToBounds = true;

	_viewWithTitle.clipsToBounds = true;
	_viewWithTitle.alpha = 1;
	_viewWithTitle.layer.borderColor = [UIColor grayColor].CGColor;
	_viewWithTitle.layer.borderWidth = 1;
	_viewWithTitle.layer.cornerRadius = 3;

	// Getting collection node to center node
	
	// get highways that contain selection
	OsmMapData * mapData = [AppDelegate getAppDelegate].mapView.editorLayer.mapData;
	NSArray * parentWays = [mapData waysContainingNode:_centralNode];
	parentWays = [parentWays filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OsmWay * way, NSDictionary *bindings) {
		return way.tags[@"highway"] != nil;
	}]];
	_parentWays = [parentWays mutableCopy];
	
	// Creating roads using adjacent connected nodes
	NSArray * conectedNodes = [TurnRestrictController getAdjacentNodes:_centralNode ways:_parentWays];
	[self createHighwayViews:conectedNodes];
}

+(NSArray *)getAdjacentNodes:(OsmNode *)centerNode ways:(NSArray *)parentWays
{
	NSMutableArray * connectedNodes = [NSMutableArray new];

	for (OsmWay * way in parentWays) {
		if (way.isArea)
			continue; // An area won't have any connected ways to it
		
		for ( int i = 0; i < way.nodes.count; i++) {
			OsmNode * node = [way.nodes objectAtIndex:i];
			if ( node == centerNode ) {
				if ( i+1 < way.nodes.count) {
					OsmNode * nodeNext = way.nodes[i+1];
					if ( ![connectedNodes containsObject:nodeNext] ) 	{
						nodeNext.turnRestrictionParentWay = way;
						[connectedNodes addObject:nodeNext];
					}
				}

				if ( i > 0 ) {
					OsmNode * nodePrev = way.nodes[i-1];
					if ( ![connectedNodes containsObject:nodePrev]) {
						nodePrev.turnRestrictionParentWay = way;
						[connectedNodes addObject:nodePrev];
					}
				}
			}
		}
	}
	return connectedNodes;
}

+(void)setAssociatedTurnRestrictionWays:(NSArray *)allWays
{
	for ( OsmWay * way in allWays ) {
		for ( OsmNode * node in way.nodes ) {
			node.turnRestrictionParentWay = way;
		}
	}
}


-(void)removeFromParentRelation:(OsmMapData *)mapData object:(OsmBaseObject *)object relation:(OsmRelation *)relation
{
	NSInteger memberIndex = 0;
	while ( memberIndex < relation.members.count ) {
		OsmMember * member = relation.members[memberIndex];
		if ( member.ref == object ) {
			[mapData deleteMemberInRelation:relation index:memberIndex];
		} else {
			++memberIndex;
		}
	}
}



//MARK: Create Path From Points
-(void)createHighwayViews:(NSArray*)nodesArray
{
	CGPoint	centerNodePos		= [self screenPointForLatitude:_centralNode.lat longitude:_centralNode.lon];
	CGPoint detailViewCenter	= CGPointMake( _detailView.frame.size.width/2, _detailView.frame.size.height/2 );
	CGPoint positionOffset		= CGPointSubtract( centerNodePos, detailViewCenter );

	// Get relations related to restrictions
	_allRelations = [NSMutableArray new];
	for ( OsmRelation * relation in _centralNode.relations )  {
		if ( relation.isRestriction && relation.members.count >= 3 )  {
			[_allRelations addObject:relation];
		}
	}

	_editedRelations = [_allRelations mutableCopy];

	// create highway views
	_highwayViewArray = [NSMutableArray new];
	for ( OsmNode * node in nodesArray )  {
		// get location of node
		CGPoint nodePoint = [self screenPointForLatitude:node.lat longitude:node.lon];
		nodePoint = CGPointSubtract(nodePoint, positionOffset);

		// force highway segment to extend from center node to edge of view
		CGSize size = _detailView.frame.size;
		OSMPoint direction = OSMPointMake( nodePoint.x - detailViewCenter.x, nodePoint.y - detailViewCenter.y );
		double distTop    = DistanceToVector( OSMPointFromCGPoint(detailViewCenter), direction, OSMPointMake(0,0),			OSMPointMake(size.width,0) );
		double distLeft   = DistanceToVector( OSMPointFromCGPoint(detailViewCenter), direction, OSMPointMake(0,0), 			OSMPointMake(0,size.height) );
		double distRight  = DistanceToVector( OSMPointFromCGPoint(detailViewCenter), direction, OSMPointMake(size.width,0), OSMPointMake(0,size.height) );
		double distBottom = DistanceToVector( OSMPointFromCGPoint(detailViewCenter), direction, OSMPointMake(0,size.height),OSMPointMake(size.width,0) );
		double best = FLT_MAX;
		if ( distTop > 0 && distTop < best )		best = distTop;
		if ( distLeft > 0 && distLeft < best )		best = distLeft;
		if ( distRight > 0 && distRight < best )	best = distRight;
		if ( distBottom > 0 && distBottom < best )	best = distBottom;
		nodePoint = CGPointMake( detailViewCenter.x+best*direction.x, detailViewCenter.y+best*direction.y );
		
		// highway path
		UIBezierPath *bPath = [UIBezierPath bezierPath];
		[bPath moveToPoint:detailViewCenter];
		[bPath addLineToPoint:nodePoint];
		
		// Highlight shape
		CAShapeLayer * highlightLayer = [CAShapeLayer layer];
		highlightLayer.lineWidth   	=  DEFAULT_POPUPLINEWIDTH + 6;
		highlightLayer.strokeColor 	= [UIColor cyanColor].CGColor;
		highlightLayer.lineCap 		= kCALineCapRound;
		highlightLayer.path   		= bPath.CGPath;
		highlightLayer.bounds 		= _detailView.bounds;
		highlightLayer.fillColor 	= [UIColor whiteColor].CGColor;
		highlightLayer.position 	= CGPointMake(_detailView.bounds.size.width/2, _detailView.bounds.size.height/2);
		highlightLayer.hidden		= YES;

		// Highway shape
		CAShapeLayer * highwayLayer = [CAShapeLayer layer];
		highwayLayer.lineWidth   	= DEFAULT_POPUPLINEWIDTH;
		highwayLayer.lineCap 		= kCALineCapRound;
		highwayLayer.path 	  		= bPath.CGPath;
		highwayLayer.strokeColor 	= node.turnRestrictionParentWay.tagInfo.lineColor.CGColor ?: [UIColor blackColor].CGColor;
		highwayLayer.bounds 		= _detailView.bounds;
		highwayLayer.position	 	= CGPointMake(_detailView.bounds.size.width/2, _detailView.bounds.size.height/2);
		highwayLayer.masksToBounds 	= NO;

		// Highway view
		TurnRestrictHwyView * viewLine = [[TurnRestrictHwyView alloc] initWithFrame:_detailView.bounds];
		viewLine.wayObj 			= node.turnRestrictionParentWay;
		viewLine.centerNode 		= _centralNode;
		viewLine.connectedNode 		= node;
		viewLine.centerPoint 		= detailViewCenter;
		viewLine.endPoint 			= nodePoint;
		viewLine.parentWaysArray 	= _parentWays;
		
		viewLine.highwayLayer 		= highwayLayer;
		viewLine.highlightLayer 	= highlightLayer;
		viewLine.backgroundColor 	= [UIColor clearColor];
		
		[viewLine.layer addSublayer:highwayLayer];
		[viewLine.layer insertSublayer:highlightLayer below:highwayLayer];

		[viewLine createArrowButton];
		[viewLine createOneWayArrowsForHighway];

		viewLine.arrowButton.hidden = YES;
	
		viewLine.lineButtonPressCallback = ^(TurnRestrictHwyView *objLine) { [self toggleTurnRestriction:objLine];	};
		viewLine.lineSelectionCallback 	 = ^(TurnRestrictHwyView *objLine) { [self toggleHighwaySelection:objLine]; };

		[_detailView addSubview:viewLine];
		[_highwayViewArray addObject:viewLine];
	}
	
	// Center green circle in center
	UIView * centerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
	centerView.backgroundColor = [UIColor greenColor];
	centerView.layer.cornerRadius = centerView.frame.size.height/2;
	centerView.center = detailViewCenter;
	[_detailView addSubview:centerView];
	[_detailView bringSubviewToFront:centerView];
	
	self.view.backgroundColor = [UIColor clearColor];

	//Creating center restriction button and set the size of the icon e.g 30, 40,50
	_uTurnButton = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 30, 30)];
	_uTurnButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
	_uTurnButton.center = detailViewCenter;
	[_uTurnButton setImage:[UIImage imageNamed:@"uTurnAllow"]	 forState:UIControlStateNormal];
	[_uTurnButton setImage:[UIImage imageNamed:@"uTurnRestrict"] forState:UIControlStateSelected];
	[_uTurnButton addTarget:self action:@selector(uTurnButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
	[_detailView addSubview:_uTurnButton];

	_uTurnButton.hidden = true;
}

-(void)toggleHighwaySelection:(TurnRestrictHwyView *)selectedHwy
{
	selectedHwy.wayObj = selectedHwy.connectedNode.turnRestrictionParentWay;
	[self rotateUTurnIconForHighway:selectedHwy.endPoint lineView:selectedHwy];
	
	NSString * selectedId = selectedHwy.Id;
	
	// highway exits center one-way
	BOOL selectedHwyIsOneWayExit = NO;
	if ( selectedHwy.wayObj.isOneWay ) {
		NSUInteger centerIndex = [selectedHwy.wayObj.nodes indexOfObject:selectedHwy.centerNode];
		NSUInteger otherIndex = [selectedHwy.wayObj.nodes indexOfObject:selectedHwy.connectedNode];
		if ( (otherIndex > centerIndex) == (selectedHwy.wayObj.isOneWay == ONEWAY_FORWARD) ) {
			selectedHwyIsOneWayExit = YES;	// means no turn restriction can apply, since we can't proceed through the intersection
		}
	}
	
	for ( TurnRestrictHwyView * highway in _highwayViewArray ) {

		selectedHwy.wayObj = selectedHwy.connectedNode.turnRestrictionParentWay;
		
		if ( [highway.Id isEqualToString:selectedId] ) {
			// highway is selected
			highway.highlightLayer.hidden = NO;
			highway.arrowButton.hidden = YES;
		} else {
			// highway is deselected, so display restrictions applied to it
			highway.highlightLayer.hidden = YES;
			highway.fromHwy = selectedHwy;
			
			OsmRelation * relation = [self getRelationFrom:_editedRelations
													  fromId:selectedHwy.wayObj
													   viaId:_centralNode
														toId:highway.wayObj];
			BOOL isSelected = (relation == nil);
			
			highway.objRel = relation;
			highway.arrowButton.hidden = NO;
			highway.arrowButton.selected = !isSelected;
			
			if ( selectedHwyIsOneWayExit ) {
				highway.arrowButton.hidden = YES;
			} else if ( highway.wayObj.isOneWay ) {
				NSUInteger cIndex = [highway.wayObj.nodes indexOfObject:highway.connectedNode];
				NSUInteger adIndex = [highway.wayObj.nodes indexOfObject:highway.centerNode];
				
				if ( (cIndex < adIndex) == (highway.wayObj.isOneWay == ONEWAY_FORWARD) ) {
					highway.arrowButton.hidden = YES;	// highway is one way into intersection, so we can't turn onto it
				}
			}
		}
	}
}

-(void)toggleTurnRestriction:(TurnRestrictHwyView *)objLine
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;
	
	bool isRestricting = objLine.arrowButton.selected;
	
	if ( isRestricting )  {
		CGPoint viaPt 	= objLine.centerPoint;
		CGPoint toPt 	= objLine.endPoint;
		CGPoint fromPt 	= objLine.fromHwy.endPoint;
		
		CGFloat fromAngle = [TurnRestrictHwyView pointPairToBearingDegrees:fromPt secondPoint:viaPt];
		CGFloat toAngle   = [TurnRestrictHwyView pointPairToBearingDegrees:viaPt  secondPoint:toPt];
		CGFloat angle     = toAngle - fromAngle;
		if ( angle >= 180 ) angle -= 360;
		if ( angle < -180 )	angle += 360;
		
		NSString *str = @"no_straight_on";
		
		if (ABS(angle) < 3)   {
			str = @"no_straight_on";
		} else if ( angle < 0 )   {
			str = @"no_left_turn";
		} else {
			str = @"no_right_turn";
		}
		
		TurnRestrictHwyView * fromLine = objLine;
		TurnRestrictHwyView * toLine = objLine.fromHwy;
		
		OsmRelation *relation_Obj = [self getRelationFrom:_allRelations
												   fromId:objLine.fromHwy.wayObj
													viaId:_centralNode
													 toId:objLine.wayObj];
		if (relation_Obj == nil)   {
			//Get closed
			NSMutableArray *arraySplitWays = [NSMutableArray new];
			if (fromLine.wayObj == toLine.wayObj)   {
				NSUInteger indexfrom = [fromLine.wayObj.nodes indexOfObject:_centralNode];
				
				if (fromLine.wayObj.isClosed)  {
					[arraySplitWays addObject:fromLine.wayObj];
				} else if (indexfrom > 0 && indexfrom < fromLine.wayObj.nodes.count-1)  {
					[arraySplitWays addObject:fromLine.wayObj];
				}
			} else {
				NSUInteger indexfrom = [fromLine.wayObj.nodes indexOfObject:_centralNode];
				
				if (fromLine.wayObj.isClosed) {
					[arraySplitWays addObject:fromLine.wayObj];
				} else if (indexfrom > 0 && indexfrom < fromLine.wayObj.nodes.count-1) {
					[arraySplitWays addObject:fromLine.wayObj];
				}
				
				NSUInteger indexTo = [toLine.wayObj.nodes indexOfObject:_centralNode];
				
				if (toLine.wayObj.isClosed) {
					[arraySplitWays addObject:toLine.wayObj];
				} else if (indexTo > 0 && indexTo < toLine.wayObj.nodes.count-1) {
					[arraySplitWays addObject:toLine.wayObj];
				}
			}
			
			// Split Way
			for (OsmWay *objWay in arraySplitWays)  {
				OsmWay *newWay = [mapData splitWay:objWay atNode:_centralNode];
				[appDelegate.mapView.editorLayer setNeedsDisplay];
				[appDelegate.mapView.editorLayer setNeedsLayout];
				
				[_parentWays addObject:newWay];
			}
			[TurnRestrictController setAssociatedTurnRestrictionWays:_parentWays];
			
			for (TurnRestrictHwyView *viewOj in _highwayViewArray)   {
				viewOj.wayObj = viewOj.connectedNode.turnRestrictionParentWay;
			}
			
			//Create New
			relation_Obj = [mapData createTurnRestrictionRelation:_centralNode
														  fromWay:objLine.fromHwy.wayObj
															toWay:objLine.wayObj
															 turn:str];
			
			[_allRelations addObject:relation_Obj];
			
		} else {
			[mapData updateTurnRestrictionRelation:relation_Obj
										   viaNode:_centralNode
										   fromWay:objLine.fromHwy.wayObj
											 toWay:objLine.wayObj
											  turn:str];
		}
		[_editedRelations addObject:relation_Obj];
		fromLine.objRel = relation_Obj;
		
	} else {
		
		//Remove Relation
		if ( objLine.objRel )  {
			NSLog(@"%@", objLine.objRel);

			[self removeFromParentRelation:mapData object:objLine.fromHwy.wayObj relation:objLine.objRel];
			[self removeFromParentRelation:mapData object:objLine.wayObj relation:objLine.objRel];
			[self removeFromParentRelation:mapData object:_centralNode relation:objLine.objRel];
			
			[_editedRelations removeObject:objLine.objRel];
			
			objLine.objRel = nil;
		}
	}
}


// Getting the Angle between two points for rotate the icons
-(void)rotateUTurnIconForHighway:(CGPoint )location lineView:(TurnRestrictHwyView *)lineView
{
	_selectedHwy = lineView;

	_uTurnButton.hidden = _selectedHwy.wayObj.isOneWay != ONEWAY_NONE;

	CGFloat angle = [TurnRestrictHwyView getAngle:location b:_uTurnButton.center];
	_uTurnButton.transform = CGAffineTransformMakeRotation(angle);

	OsmRelation * relationObj = [self getRelationFrom:_editedRelations
											  fromId:_selectedHwy.wayObj
											   viaId:_centralNode
												toId:_selectedHwy.wayObj];
	_currentUTurnRelation = relationObj;

	bool isSelected = (relationObj == nil);
	_uTurnButton.selected = !isSelected;
}

// Use clicked the U-Turn button
-(void)uTurnButtonClicked:(UIButton *)sender
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;
    OsmNode *seletedNode = _centralNode;
    
    sender.selected = !sender.selected;
    
    bool isRestricting = sender.selected;
    TurnRestrictHwyView *fromLine = _selectedHwy;
    
    if (isRestricting)
    {
        NSString *str = @"no_u_turn";
        
        OsmRelation *relation_Obj = [self getRelationFrom:_allRelations
                                                   fromId:fromLine.wayObj
                                                    viaId:seletedNode
                                                     toId:fromLine.wayObj];
        
        if (relation_Obj == nil)
        {
            NSMutableArray *arraySplitWays = [NSMutableArray new];
            
            NSUInteger indexfrom = [fromLine.wayObj.nodes indexOfObject:seletedNode];
            
            if ( fromLine.wayObj.isClosed )  {
                [arraySplitWays addObject:fromLine.wayObj];
            } else if (indexfrom > 0 && indexfrom < fromLine.wayObj.nodes.count-1) {
                [arraySplitWays addObject:fromLine.wayObj];
            }
            
            for (OsmWay *objWay in arraySplitWays)  {
                OsmWay * newWay = [mapData splitWay:objWay atNode:seletedNode];
                [appDelegate.mapView.editorLayer setNeedsDisplay];
                [appDelegate.mapView.editorLayer setNeedsLayout];

                [_parentWays addObject:newWay];
            }
			[TurnRestrictController setAssociatedTurnRestrictionWays:_parentWays];
            
            for ( TurnRestrictHwyView *viewOj in _highwayViewArray ) {
                viewOj.wayObj = viewOj.connectedNode.turnRestrictionParentWay;
            }
            
            //Create New
            relation_Obj = [mapData createTurnRestrictionRelation:seletedNode
														  fromWay:fromLine.wayObj
															toWay:fromLine.wayObj
															 turn:str];
            
            [_allRelations addObject:relation_Obj];
        } else {
            [mapData updateTurnRestrictionRelation:relation_Obj
										   viaNode:seletedNode
										   fromWay:fromLine.wayObj
											 toWay:fromLine.wayObj
											  turn:str];
        }
        [_editedRelations addObject:relation_Obj];
        _currentUTurnRelation = relation_Obj;
    } else {
        if ( _currentUTurnRelation ) {
            /*
            [mapData removeFromParentRelations:fromLine.wayObj relation:seletedRelation];
            [mapData removeFromParentRelations:seletedNode relation:seletedRelation];
            seletedRelation = nil
            */
            
            [mapData deleteRelation:_currentUTurnRelation];
            [_editedRelations removeObject:_currentUTurnRelation];
        }
    }
}


// Getting restriction relation by From node, To node and Via node
-(OsmRelation *)getRelationFrom:(NSArray *)arrayRelation
                         fromId:(OsmWay *)fromId
                          viaId:(OsmNode *)viaId
                           toId:(OsmWay *)toId
{
	for ( OsmRelation *objRel in arrayRelation )  {
		OsmWay 	*	fromWay = [objRel memberByRole:@"from"].ref;
		OsmNode *	viaNode = [objRel memberByRole:@"via"].ref;
		OsmWay 	*	toWay	= [objRel memberByRole:@"to"].ref;
		if ( fromWay == fromId && viaNode == viaId && toWay == toId )
			return objRel;
	}
	return nil;
}



// Close the window if user touches outside it
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
	CGPoint viewPoint     = [_viewWithTitle convertPoint:locationPoint fromView:self.view];

	if ( ![_viewWithTitle pointInside:viewPoint withEvent:event] )  {
		[self dismissViewControllerAnimated:true completion:nil];
	}
}


// Convert location point to CGPoint
-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude
{
	OSMPoint pt = MapPointForLatitudeLongitude( latitude, longitude );
	pt = OSMPointApplyTransform( pt, _screenFromMapTransform );
	return CGPointFromOSMPoint(pt);
}

@end

