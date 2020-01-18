//
//  OsmRelation.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmObjects.h"

@interface OsmRelation : OsmBaseObject <NSCoding>
{
    NSMutableArray    *    _members;
}
@property (readonly,nonatomic)    NSArray    *    members;

-(void)constructMember:(OsmMember *)member;

-(void)resolveToMapData:(OsmMapData *)mapData;
-(NSSet *)allMemberObjects;

-(void)removeMemberAtIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)addMember:(OsmMember *)member atIndex:(NSInteger)index undo:(UndoManager *)undo;
-(void)assignMembers:(NSArray *)members undo:(UndoManager *)undo;

-(BOOL)isMultipolygon;
-(BOOL)isRestriction;
-(BOOL)isRoute;

-(OsmMember *)memberByRole:(NSString *)role;
-(NSArray *)membersByRole:(NSString *)role;
-(OsmMember *)memberByRef:(OsmBaseObject *)ref;

-(NSMutableArray *)waysInMultipolygon;
-(NSArray *)buildMultipolygonRepairing:(BOOL)repairing;
+(NSArray *)buildMultipolygonFromMembers:(NSArray *)memberList repairing:(BOOL)repairing isComplete:(BOOL *)isComplete;

-(OSMPoint)centerPoint;

-(BOOL)containsObject:(OsmBaseObject *)object;

-(void)deresolveRefs;

@end
