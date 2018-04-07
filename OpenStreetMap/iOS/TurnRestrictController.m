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
    TurnRestrictHwyView *      selectedLine;
    UIButton *          centerButton;
    OsmRelation *       selectedRelation;
    UIView *            mapWindow;
    
    NSMutableArray *    pathViewArray; //Array of TurnRestrictHwyView to Store number of ways
    
    NSMutableArray *    selectedRelations;
    NSMutableArray *    editedRelation;
    NSMutableArray *    newCreatedRelation;
}
@end

@implementation TurnRestrictController


//MARK: ViewDid Load
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    pathViewArray = [[NSMutableArray alloc] init];
    
    [self createMapWindow];
}

//To dray Popup window
-(void)createMapWindow
{
    //    CGRect deviceRect = [[UIScreen mainScreen] bounds];
    
    //Popup Window Size iPhone
    CGFloat widthW =  240;
    CGFloat heightW = 220;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        //Popup Window 2X Size iPad
        widthW *= 2;
        heightW *= 2;
    }
    
    //Popup Window Topbar height
    heightW += 30;
    
    //    CGFloat bottomSpace = 44+11+43;
    _constraintContainerViewWidth.constant = widthW;
    _constraintContainerViewHeight.constant = heightW;
    
    [self.view layoutIfNeeded];
    
    mapWindow = _viewWindowContainer;
    mapWindow.clipsToBounds = true;
    
    _containerView.clipsToBounds = true;
    _containerView.alpha = 1;
    _containerView.layer.borderColor = [UIColor grayColor].CGColor;
    _containerView.layer.borderWidth = 1;
    _containerView.layer.cornerRadius = 3;
    
    //Getting collection node to center node
	NSArray *conectedNodes = [self getConnectedTurnRestrictionWaysForNode:_selectedNode ways:_parentWays];
    
    //Creating roads using connected nodes
    [self drawPathsToNodes:conectedNodes];
}




-(void)setAssociatedTurnRestrictionWays:(NSArray *)allWays
{
	for (OsmWay * way in allWays) {
		for (OsmNode * node in way.nodes) {
			node.associatedTurnRestrictionWay = way;
		}
	}
}

-(NSArray *)getConnectedTurnRestrictionWaysForNode:(OsmNode *)baseNode ways:(NSArray *)allWays
{
	NSMutableArray *connectedNodes = [NSMutableArray new];

	for (OsmWay * way in allWays) {
		if (way.isArea)
			continue; // An area won't have any connected ways to it
		for (int i = 0; i < way.nodes.count; i++) {
			OsmNode * node = [way.nodes objectAtIndex:i];
			if (node.ident.integerValue == baseNode.ident.integerValue) {
				if ((i+1) < way.nodes.count) {
					OsmNode * nodeNext = [way.nodes objectAtIndex:i+1];

					if ( ![connectedNodes containsObject:nodeNext] ) 	{
						nodeNext.associatedTurnRestrictionWay = way;
						[connectedNodes addObject:nodeNext];
					}
				}

				if ((i-1) >= 0)
				{
					OsmNode * nodeNext = [way.nodes objectAtIndex:i-1];

					if (![connectedNodes containsObject:nodeNext])
					{
						nodeNext.associatedTurnRestrictionWay = way;
						[connectedNodes addObject:nodeNext];
					}
				}
			}
		}
	}
	return connectedNodes;
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
-(void)drawPathsToNodes:(NSArray*)pointsArray
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;

    OsmNode * selectedNode = _selectedNode;
    
    //Convert location to CGPoint
    CGPoint selectedPoint = [self screenPointForLatitude:selectedNode.lat longitude:selectedNode.lon birdsEye:true];
    
    //Getting Mid point of center node
    CGFloat midX = mapWindow.frame.size.width/2;
    CGFloat midY = mapWindow.frame.size.height/2;
    
    CGPoint newSelectedPoint = CGPointMake(midX, midY);
    CGPoint pointxCenter =  CGPointSubtract(selectedPoint, newSelectedPoint);
    
    pathViewArray = [NSMutableArray new];
    
    CGFloat diff = 0;
    
    CGFloat minX = 0+diff;
    CGFloat maxX = mapWindow.frame.size.width-diff;
    CGFloat minY = 0+diff;
    CGFloat maxY = mapWindow.frame.size.height-diff;
    
    NSArray *arrayRelation = selectedNode.relations;
    
    // Getting relation related to restrictions
    selectedRelations = [NSMutableArray new];
    
    for (OsmRelation *objRelation in arrayRelation)
    {
        if (!objRelation.isRestriction && objRelation.members.count < 3)
        {
            continue;
        }
        [selectedRelations addObject:objRelation];
    }
    
    editedRelation = [NSMutableArray arrayWithArray:[selectedRelations mutableCopy]];
    
    for (OsmNode *pointNode in pointsArray)
    {
        CGPoint nodePoint = [self screenPointForLatitude:pointNode.lat longitude:pointNode.lon birdsEye:true];
        
//       CGPoint lastCenter = [self getCoordinateOfThePoints:nodePoint center:pointxCenter];
        
        CGPoint newCenter =  CGPointSubtract(nodePoint, pointxCenter);
        
        //Getting outside point of the window
        newCenter = [self getCoordinateOfThePoints:newCenter center:newSelectedPoint];

        //Getting edge points of the window popup
        if (newCenter.x < minX)
        {
            CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(minX, -FLT_MAX) to:CGPointMake(minX, FLT_MAX)];
            newCenter = [self getPointFromBounds:u to:newSelectedPoint bounds:mapWindow.bounds];
        }
        else if (newCenter.x > maxX)
        {
            CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(maxX, -FLT_MAX) to:CGPointMake(maxX, FLT_MAX)];
            newCenter = [self getPointFromBounds:u to:newSelectedPoint bounds:mapWindow.bounds];
        }
        else if (newCenter.y < minY)
        {
            CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(-FLT_MAX, minY) to:CGPointMake(FLT_MAX, minY)];
            newCenter = [self getPointFromBounds:u to:newSelectedPoint bounds:mapWindow.bounds];
        }
        else if (newCenter.y > maxY)
        {
            CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(-FLT_MAX, maxY) to:CGPointMake(FLT_MAX, maxY)];
            newCenter = [self getPointFromBounds:u to:newSelectedPoint bounds:mapWindow.bounds];
        }
        
        //Draw ways on the windoe popup
        UIBezierPath *bPath = [UIBezierPath bezierPath];
        [bPath moveToPoint:newSelectedPoint];
        [bPath addLineToPoint:newCenter];
//        [bPath closePath];
        
        UIBezierPath *bPathShadow = [UIBezierPath bezierPath];
        [bPathShadow moveToPoint:newSelectedPoint];
        [bPathShadow addLineToPoint:newCenter];
//        [bPath2 closePath];

        //Drawing Shadow Line
        CAShapeLayer *shadowLayer = [CAShapeLayer layer];
        
        shadowLayer.lineWidth   =  DEFAULT_POPUPLINEWIDTH+4;
        
        //Color of the shadow e.g redColor, yellowColor and color transparency e.g 0.5, 0.8
        shadowLayer.strokeColor = [[UIColor redColor] colorWithAlphaComponent:0.5].CGColor;
        shadowLayer.lineCap = kCALineCapButt;
        shadowLayer.path   = bPathShadow.CGPath;
        shadowLayer.bounds =  mapWindow.bounds;
        shadowLayer.fillColor = [UIColor whiteColor].CGColor;
//        shadowLayer.bounds =  mapWindow.bounds;
        shadowLayer.position = CGPointMake(mapWindow.bounds.size.width/2, mapWindow.bounds.size.height/2);
//        shadowLayer.shadowPath = shadowLayer.path;
//        shadowLayer.shadowRadius = 5.0;
//        shadowLayer.shadowOffset = CGSizeMake(2.0f, 2.0f);
//        shadowLayer.shadowColor = (__bridge CGColorRef _Nullable)([UIColor redColor]);

        
        //Drawing Way line
        CAShapeLayer *sLayer = [CAShapeLayer layer];
        // drawView.layer.mask = sLayer;
        TurnRestrictHwyView *viewLine = [[TurnRestrictHwyView alloc] initWithFrame:mapWindow.bounds];
        
        sLayer.lineWidth   =  DEFAULT_POPUPLINEWIDTH;
        sLayer.lineCap = kCALineCapButt;
        sLayer.path   = bPath.CGPath;
        
        //getting color of Line
        if (pointNode.associatedTurnRestrictionWay.tagInfo == nil)  {
            viewLine.wayColor = [UIColor blackColor];
        } else {
            viewLine.wayColor = pointNode.associatedTurnRestrictionWay.tagInfo.lineColor;
        }
        
        //Color of the line
        sLayer.strokeColor = viewLine.wayColor.CGColor; //pointNode.wayObj.tagInfo.lineColor.CGColor;

        sLayer.fillColor = [UIColor whiteColor].CGColor;
        sLayer.bounds =  mapWindow.bounds;
        sLayer.position = CGPointMake(mapWindow.bounds.size.width/2, mapWindow.bounds.size.height/2);
        sLayer.masksToBounds = false;
        sLayer.shadowPath = sLayer.path;
        sLayer.shadowRadius = 5.0;
        sLayer.shadowOffset = CGSizeMake(2.0f, 2.0f);
        sLayer.shadowColor = (__bridge CGColorRef _Nullable)([UIColor redColor]);
       
        viewLine.wayObj = pointNode.associatedTurnRestrictionWay;
        viewLine.centerNode = selectedNode;
        viewLine.connectedNode = pointNode;
        viewLine.centerPoint = newSelectedPoint;
        viewLine.endPoint = newCenter;
        viewLine.parentWaysArray = _parentWays;
        viewLine.layer.shadowPath = [UIBezierPath bezierPathWithRect:viewLine.bounds].CGPath;
        viewLine.layer.shadowRadius = 10.0;
        viewLine.layer.shadowOffset = CGSizeMake(2.0f, 2.0f);
        viewLine.layer.shadowColor = (__bridge CGColorRef _Nullable)([UIColor redColor]);
        
        viewLine.bPath = bPath;
        viewLine.sLayer = sLayer;
        viewLine.shadowLayer = shadowLayer;
        viewLine.Id = pointNode.ident.stringValue;
        viewLine.backgroundColor = [UIColor clearColor];
        
        [mapWindow addSubview:viewLine];
//        [viewLine.layer addSublayer:shadowLayer];
        [shadowLayer setHidden:true];
        [viewLine.layer addSublayer:sLayer];
        
        [viewLine.layer insertSublayer:shadowLayer below:sLayer];

        [viewLine createArrowButton];
        
        
        [viewLine createArrows];

        viewLine.layerButton.hidden = true;
        
        [pathViewArray addObject:viewLine];
        
        //Handle when User change the restriction status of the way
        viewLine.lineButtonPressCallback = ^(TurnRestrictHwyView *objLine)  {
            
            bool isRestricting = objLine.layerButton.selected;
            
            if (isRestricting)  {
                CGPoint cPt = objLine.centerPoint;
                CGPoint tOPt = objLine.endPoint;
                CGPoint fromPt = objLine.fromLine.endPoint;
                
                int fromAngle = (int)[TurnRestrictHwyView pointPairToBearingDegrees:fromPt secondPoint:cPt];
                int toAngle = (int)[TurnRestrictHwyView pointPairToBearingDegrees:fromPt secondPoint:tOPt];
                
                NSString *str = @"no_straight_on";
                
                if (ABS(toAngle - fromAngle) < 3)   {
                    str = @"no_straight_on";
                } else if (toAngle < fromAngle)   {
                    str = @"no_left_turn";
                } else {
                    str = @"no_right_turn";
                }
                
                TurnRestrictHwyView *fromLine = objLine;
                TurnRestrictHwyView *toLine = objLine.fromLine;
                
                
                OsmRelation *relation_Obj = [self getRelationFrom:selectedRelations
                                                           fromId:objLine.fromLine.wayObj.ident.stringValue
                                                            viaId:selectedNode.ident.stringValue
                                                             toId:objLine.wayObj.ident.stringValue];
                if (relation_Obj == nil)   {
                    //Get closed 
                    NSMutableArray *arraySplitWays = [NSMutableArray new];
                    if (fromLine.wayObj == toLine.wayObj)   {
                        NSUInteger indexfrom = [fromLine.wayObj.nodes indexOfObject:selectedNode];
                        
                        if (fromLine.wayObj.isClosed)  {
                            [arraySplitWays addObject:fromLine.wayObj];
                        } else if (indexfrom > 0 && indexfrom < fromLine.wayObj.nodes.count-1)  {
                            [arraySplitWays addObject:fromLine.wayObj];
                        }
                    } else {
                        NSUInteger indexfrom = [fromLine.wayObj.nodes indexOfObject:selectedNode];
                        
                        if (fromLine.wayObj.isClosed) {
                            [arraySplitWays addObject:fromLine.wayObj];
                        } else if (indexfrom > 0 && indexfrom < fromLine.wayObj.nodes.count-1) {
                            [arraySplitWays addObject:fromLine.wayObj];
                        }

                        NSUInteger indexTo = [toLine.wayObj.nodes indexOfObject:selectedNode];
                        
                        if (toLine.wayObj.isClosed) {
                            [arraySplitWays addObject:toLine.wayObj];
                        } else if (indexTo > 0 && indexTo < toLine.wayObj.nodes.count-1) {
                            [arraySplitWays addObject:toLine.wayObj];
                        }
                    }
                    
                    // Split Way
					for (OsmWay *objWay in arraySplitWays)  {
                        OsmWay *newWay = [mapData splitWay:objWay atNode:selectedNode];
                        [appDelegate.mapView.editorLayer setNeedsDisplay];
                        [appDelegate.mapView.editorLayer setNeedsLayout];
                        
                        [self.parentWays addObject:newWay];
                    }
					[self setAssociatedTurnRestrictionWays:_parentWays];
                    
                    for (TurnRestrictHwyView *viewOj in pathViewArray)   {
                        viewOj.wayObj = viewOj.connectedNode.associatedTurnRestrictionWay;
                    }
                    
                    //Create New
                    relation_Obj = [mapData createTurnRestrictionRelation:selectedNode
																  fromWay:objLine.fromLine.wayObj
																	toWay:objLine.wayObj
																	 turn:str];
                    
                    [selectedRelations addObject:relation_Obj];
                    
                } else {
                    [mapData updateTurnRestrictionRelation:relation_Obj
												   viaNode:selectedNode
												   fromWay:objLine.fromLine.wayObj
													 toWay:objLine.wayObj
													  turn:str];
                }
                [editedRelation addObject:relation_Obj];
                fromLine.objRel = relation_Obj;

            } else {
                //Remove Relation
                if (objLine.objRel)  {
//                    objLine.objRel.tags = @{};
                    
                    NSLog(@"%@", objLine.objRel);
                    
					[self removeFromParentRelation:mapData object:objLine.fromLine.wayObj relation:objLine.objRel];
                    [self removeFromParentRelation:mapData object:objLine.wayObj relation:objLine.objRel];
                    [self removeFromParentRelation:mapData object:selectedNode relation:objLine.objRel];
                    
                    [editedRelation removeObject:objLine.objRel];
                    
                    objLine.objRel = nil;
                }
            }
        };
        
        //Handle when select of change the way
        viewLine.lineSelectionCallback = ^(TurnRestrictHwyView *objLine) {
            
            objLine.wayObj = objLine.connectedNode.associatedTurnRestrictionWay;
            [self changeAngleofTheCenterUTurnIncon:objLine.endPoint lineView:objLine];
            
            NSString *selectedId = objLine.Id;
            //            NSLog(@"selected id is %@",objLine.wayObj.ident);
            
            bool onWay = false;
            
            if (objLine.wayObj.isOneWay == ONEWAY_FORWARD)
            {
                NSUInteger cIndex = [objLine.wayObj.nodes indexOfObject:objLine.connectedNode];
                NSUInteger adIndex = [objLine.wayObj.nodes indexOfObject:objLine.centerNode];
                
                if (cIndex > adIndex)
                {
                    onWay = true;
                }
            }
            
            for (TurnRestrictHwyView *viewOj in pathViewArray)
            {
                objLine.wayObj = objLine.connectedNode.associatedTurnRestrictionWay;
                
                if ([viewOj.Id isEqualToString:selectedId])
                {

//                    [viewOj.layer insertSublayer:viewOj.shadowLayer atIndex:0];
                    [viewOj.shadowLayer setHidden:false];
                    viewOj.sLayer.strokeColor = viewOj.wayColor.CGColor;
                    
                    viewOj.layerButton.hidden = true;
                }
                else
                {
                    [viewOj.shadowLayer setHidden:true];
                    
                    viewOj.sLayer.strokeColor = viewOj.wayColor.CGColor;
//                    viewOj.shadowLayer.strokeColor = [UIColor clearColor].CGColor;
                    
                    viewOj.fromLine = objLine;
                    
                    NSString *fromId = objLine.wayObj.ident.stringValue;
                    NSString *toId = viewOj.wayObj.ident.stringValue;
                    
                    OsmRelation *relationObj = [self getRelationFrom:editedRelation
                                                              fromId:fromId
                                                               viaId:selectedNode.ident.stringValue
                                                                toId:toId];
                    bool isSeleted = (relationObj == nil);
                    
                    viewOj.objRel = relationObj;
                    viewOj.layerButton.hidden = false;
                    viewOj.layerButton.selected = !isSeleted;
                    
                    if (onWay)
                    {
                        viewOj.layerButton.hidden = true;
                    }
                    else if (viewOj.wayObj.isOneWay == ONEWAY_FORWARD)
                    {
                        NSUInteger cIndex = [viewOj.wayObj.nodes indexOfObject:viewOj.connectedNode];
                        NSUInteger adIndex = [viewOj.wayObj.nodes indexOfObject:viewOj.centerNode];
                        
                        if (cIndex < adIndex)
                        {
                            viewOj.layerButton.hidden = true;
                        }
                    }
                }
            }
        };
    }
    self.view.backgroundColor = [UIColor clearColor];
    
    CGPoint location = CGPointMake(mapWindow.frame.size.width/2, mapWindow.frame.size.height/2);
    
    //Creating center restriction button and set the size of the icon e.g 30, 40,50
    centerButton = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, 30, 30)];
    [centerButton setImage:[UIImage imageNamed:@"uTurnAllow"] forState:UIControlStateNormal];
    [centerButton setImage:[UIImage imageNamed:@"uTurnRestrict"] forState:UIControlStateSelected];
    
    centerButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    centerButton.center = location;
    [centerButton addTarget:self action:@selector(btnClickedChangeButtonState:) forControlEvents:UIControlEventTouchUpInside];
    [mapWindow addSubview:centerButton];
    
    centerButton.hidden = true;
}

//Getting outside point of the window
-(CGPoint)getCoordinateOfThePoints:(CGPoint)location center:(CGPoint)center
{
    if (CGRectContainsPoint(mapWindow.bounds, location) == false)
    {
        return location;
    }
    
    CGFloat xc = center.x;
    CGFloat yc = center.y;
    
    CGFloat xp = location.x;
    CGFloat yp = location.y;
    
    
    if (xc == xp)
    {
        if (yc > yp)
        {
            yp = 0;
        }
        else
        {
            yp = mapWindow.bounds.size.height;
        }
        return CGPointMake(xp, yp);
    }
    else if (yc == yp)
    {
        if (xc > xp)
        {
            xp = mapWindow.bounds.size.width;
        }
        else
        {
            xp = 0;
        }
        return CGPointMake(xp, yp);
    }
    
    CGFloat xdiff = ABS(xc - xp);
    CGFloat ydiff = ABS(yc - yp);
    
    if (xp < xc && yp < yc)
    {
        //Fisry
        //x || y 0
        while (xp >= 0 || yp >= 0)
        {
            xp -= xdiff;
            yp -= ydiff;
        }
    }
    else if (xp > xc && yp < yc)
    {
        //x w || y 0
        while (xp <= mapWindow.frame.size.width || yp >= 0)
        {
            xp += xdiff;
            yp -= ydiff;
        }
    }
    else if (xp > xc && yp > yc)
    {
        //x w || y h
        while (xp <= mapWindow.frame.size.width || yp <= mapWindow.frame.size.height)
        {
            xp += xdiff;
            yp += ydiff;
        }

    }
    else if (xp < xc && yp > yc)
    {
        //x 0 || y h
        while (xp >= 0 || yp <= mapWindow.frame.size.height)
        {
            xp -= xdiff;
            yp += ydiff;
        }

    }
    return CGPointMake(xp, yp);
}

// Getting the Angle between two points for rotate the icons
-(void)changeAngleofTheCenterUTurnIncon:(CGPoint )location lineView:(TurnRestrictHwyView *)lineView
{
    selectedLine = lineView;
    
    centerButton.hidden = !(selectedLine.wayObj.isOneWay == ONEWAY_NONE);
    
    CGFloat angle = [TurnRestrictHwyView getAngle:location b:centerButton.center];
    centerButton.transform = CGAffineTransformMakeRotation(angle);
    
    NSString *fromId = selectedLine.wayObj.ident.stringValue;
    
    OsmRelation *relationObj = [self getRelationFrom:editedRelation
                                              fromId:fromId
                                               viaId:_selectedNode.ident.stringValue
                                                toId:fromId];
    selectedRelation = relationObj;
    
    bool isSeleted = (relationObj == nil);
    centerButton.selected = !isSeleted;
}

//Use clicked the button for change restriction relations
-(void)btnClickedChangeButtonState:(UIButton *)sender
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmMapData * mapData = appDelegate.mapView.editorLayer.mapData;
    OsmNode *seletedNode = _selectedNode;
    
    sender.selected = !sender.selected;
    
    bool isRestricting = sender.selected;
    TurnRestrictHwyView *fromLine = selectedLine;
    
    if (isRestricting)
    {
        NSString *str = @"no_u_turn";
        
        OsmRelation *relation_Obj = [self getRelationFrom:selectedRelations
                                                   fromId:fromLine.wayObj.ident.stringValue
                                                    viaId:seletedNode.ident.stringValue
                                                     toId:fromLine.wayObj.ident.stringValue];
        
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
                OsmWay *newWay = [mapData splitWay:objWay atNode:seletedNode];
                [appDelegate.mapView.editorLayer setNeedsDisplay];
                [appDelegate.mapView.editorLayer setNeedsLayout];

                [self.parentWays addObject:newWay];
            }
			[self setAssociatedTurnRestrictionWays:_parentWays];
            
            for ( TurnRestrictHwyView *viewOj in pathViewArray ) {
                viewOj.wayObj = viewOj.connectedNode.associatedTurnRestrictionWay;
            }
            
            //Create New
            relation_Obj = [mapData createTurnRestrictionRelation:seletedNode
														  fromWay:fromLine.wayObj
															toWay:fromLine.wayObj
															 turn:str];
            
            [selectedRelations addObject:relation_Obj];
        } else {
            [mapData updateTurnRestrictionRelation:relation_Obj
										   viaNode:seletedNode
										   fromWay:fromLine.wayObj
											 toWay:fromLine.wayObj
											  turn:str];
        }
        [editedRelation addObject:relation_Obj];
        selectedRelation = relation_Obj;
    } else {
        if ( selectedRelation ) {
            /*
            [mapData removeFromParentRelations:fromLine.wayObj relation:seletedRelation];
            [mapData removeFromParentRelations:seletedNode relation:seletedRelation];
            seletedRelation = nil
            */
            
            [mapData deleteRelation:selectedRelation];
            [editedRelation removeObject:selectedRelation];
        }
    }
}


//Getting restriction relation by From node, too Node and Via node
-(OsmRelation *)getRelationFrom:(NSMutableArray *)arrayRelation
                         fromId:(NSString *)fromId
                          viaId:(NSString *)viaId
                           toId:(NSString *)toId
{
    for (OsmRelation *objRel in arrayRelation)
    {
        if (objRel.members.count < 3)
        {
            continue;
        }
        OsmMember *fromM = [objRel memberByRole:@"from"];
        OsmWay *wayFrom = fromM.ref;
        
        OsmMember *viaM = [objRel memberByRole:@"via"];
        OsmNode *wayNode = viaM.ref;
        
        OsmMember *toM = [objRel memberByRole:@"to"];
        OsmWay *wayTo = toM.ref;
        
        
        if (![wayFrom isKindOfClass:[OsmWay class]]
            || ![wayNode isKindOfClass:[OsmNode class]]
            || ![wayTo isKindOfClass:[OsmWay class]]
            || wayFrom == nil
            || wayNode == nil
            || wayTo == nil
            )
        {
            continue;
        }
        
        if ([wayFrom.ident.stringValue isEqualToString:fromId]
            && [wayNode.ident.stringValue isEqualToString:viaId])
        {
            
            if ([wayTo.ident.stringValue isEqualToString:toId])
            {
                return objRel;
            }
        }
    }
    return nil;
}

//Getting edge point
- (CGPoint )getPointFromBounds:(CGPoint)point to:(CGPoint)newSelectedPoint bounds:(CGRect)bounds
{
    CGFloat diff = 0;
    
    CGFloat minX = bounds.origin.x+diff;
    CGFloat maxX = bounds.size.width-diff;
    CGFloat minY = bounds.origin.y+diff;
    CGFloat maxY = bounds.size.height-diff;
    
    CGPoint newCenter =  point;
    
    if (newCenter.x < minX)
    {
        CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(minX, -FLT_MAX) to:CGPointMake(minX, FLT_MAX)];
        newCenter = u;
    }
    else if (newCenter.x > maxX)
    {
        CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(maxX, -FLT_MAX) to:CGPointMake(maxX, FLT_MAX)];
        newCenter = u;
    }
    else if (newCenter.y < minY)
    {
        CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(-FLT_MAX, minY) to:CGPointMake(FLT_MAX, minY)];
        newCenter = u;
        
    }
    else if (newCenter.y > maxY)
    {
        CGPoint u =  [self intersectionOfLineFrom:newCenter to:newSelectedPoint withLineFrom:CGPointMake(-FLT_MAX, maxY) to:CGPointMake(FLT_MAX, maxY)];
        newCenter = u;
    }
    return newCenter;
}

//Getting edge point of the window popup
- (CGPoint )intersectionOfLineFrom:(CGPoint)p1 to:(CGPoint)p2 withLineFrom:(CGPoint)p3 to:(CGPoint)p4
{
    CGFloat d = (p2.x - p1.x)*(p4.y - p3.y) - (p2.y - p1.y)*(p4.x - p3.x);
    if (d == 0)
        return CGPointZero; // parallel lines
    CGFloat u = ((p3.x - p1.x)*(p4.y - p3.y) - (p3.y - p1.y)*(p4.x - p3.x))/d;
    CGFloat v = ((p3.x - p1.x)*(p2.y - p1.y) - (p3.y - p1.y)*(p2.x - p1.x))/d;
    if (u < 0.0 || u > 1.0)
        return CGPointZero; // intersection point not between p1 and p2
    if (v < 0.0 || v > 1.0)
        return CGPointZero; // intersection point not between p3 and p4
    CGPoint intersection;
    intersection.x = p1.x + u * (p2.x - p1.x);
    intersection.y = p1.y + u * (p2.y - p1.y);
    
    return intersection;
}

//Close the Window
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    CGPoint locationPoint = [[touches anyObject] locationInView:self.view];
    CGPoint viewPoint     = [_containerView convertPoint:locationPoint fromView:self.view];
    
    if (![_containerView pointInside:viewPoint withEvent:event])
    {
        [self dismissViewControllerAnimated:true completion:nil];
    }
}

//MARK:-------------------------
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//Convert location point to CGPoint
-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude birdsEye:(BOOL)birdsEye
{
    OSMPoint pt = MapPointForLatitudeLongitude( latitude, longitude );
    pt = [self screenPointFromMapPoint:pt birdsEye:birdsEye];
    return CGPointFromOSMPoint(pt);
}

-(OSMPoint)screenPointFromMapPoint:(OSMPoint)point birdsEye:(BOOL)birdsEye
{
    point = OSMPointApplyTransform( point, _screenFromMapTransform );
    if ( _birdsEyeRotation && birdsEye ) {
        CGPoint center = _mapCenter;
        point = ToBirdsEye( point, center, _birdsEyeDistance, _birdsEyeRotation );
    }
    return point;
}

@end

