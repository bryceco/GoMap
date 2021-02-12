//
//  OsmWay.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmBaseObject.h"

@interface OsmWay : OsmBaseObject <NSCoding>
{
    NSMutableArray    *    _nodes;
}
@property (readonly,nonatomic)    NSArray<OsmNode *> *    nodes;

-(void)constructNode:(NSNumber *)node;
-(void)constructNodeList:(NSMutableArray *)nodes;
-(void)removeNodeAtIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)addNode:(OsmNode *)node atIndex:(NSInteger)index undo:(UndoManager *)undo;

-(void)resolveToMapData:(OsmMapData *)mapData;
-(OSMPoint)centerPoint;
-(OSMPoint)centerPointWithArea:(double *)area;
-(double)lengthInMeters;
-(ONEWAY)computeIsOneWay;
-(BOOL)sharesNodesWithWay:(OsmWay *)way;
-(BOOL)isArea;
-(BOOL)isClosed;
-(BOOL)isClockwise;
-(double)wayArea;
-(BOOL)isMultipolygonMember;
-(BOOL)isSimpleMultipolygonOuterMember;
+(BOOL)isClockwiseArrayOfNodes:(NSArray *)nodes;
-(BOOL)isSelfIntersection:(OsmNode *)node;
+(CGPathRef)shapePathForNodes:(NSArray *)nodes forward:(BOOL)forward withRefPoint:(OSMPoint *)pRefPoint CF_RETURNS_RETAINED;
-(BOOL)hasDuplicatedNode;
-(BOOL)needsNoNameHighlight;
-(OsmNode *)connectsToWay:(OsmWay *)way;
-(NSInteger)segmentClosestToPoint:(OSMPoint)point;
@end
