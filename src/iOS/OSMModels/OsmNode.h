//
//  OsmNode.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmBaseObject.h"

@interface OsmNode : OsmBaseObject <NSCoding>
{
}
@property (readonly,nonatomic)    double        lat;
@property (readonly,nonatomic)    double        lon;
@property (readonly,nonatomic)    NSInteger    wayCount;
@property (assign,nonatomic)    OsmWay    *    turnRestrictionParentWay;    // temporarily used during turn restriction processing

-(void)setLongitude:(double)longitude latitude:(double)latitude undo:(UndoManager *)undo;
-(void)setWayCount:(NSInteger)wayCount undo:(UndoManager *)undo;

-(OSMPoint)location;
-(BOOL)isBetterToKeepThan:(OsmNode *)node;

@end
