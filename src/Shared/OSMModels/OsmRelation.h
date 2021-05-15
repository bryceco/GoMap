//
//  OsmRelation.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//


@interface OsmRelation : OsmBaseObject <NSCoding>
{
    NSMutableArray    *    _members;
}
@property (readonly,nonatomic)    NSArray<OsmMember *>    *    members;

-(void)constructMember:(OsmMember *)member;

-(BOOL)resolveToMapData:(OsmMapData *)mapData;
-(NSSet *)allMemberObjects;

-(void)removeMemberAtIndex:(NSInteger)index undo:(MyUndoManager *)undo;
-(void)addMember:(OsmMember *)member atIndex:(NSInteger)index undo:(MyUndoManager *)undo;
-(void)assignMembers:(NSArray *)members undo:(MyUndoManager *)undo;

-(BOOL)isMultipolygon;
-(BOOL)isBoundary;
-(BOOL)isWaterway;
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
