//
//  CoreData.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/8/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "iosapi.h"
#import "VectorMath.h"
#import "TagInfo.h"
#import "UndoManager.h"



@interface CoreData : NSObject
{
	NSMutableArray * nodeList;
}
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *	persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel		*	managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext		*	managedObjectContext;

@end



@interface OsmBaseObjectCD : NSManagedObject
{
@protected
	int32_t				_modifyCount;
	BOOL				_constructed;
	NSDictionary	*	_tags;
	NSNumber		*	_ident;
	NSArray			*	_relations;
@public
	OSMRect				_boundingBox;
}
@property (assign,nonatomic)	BOOL				wasDeleted;
@property (assign,nonatomic)	int32_t				modifyCount;
@property (strong,nonatomic)	NSArray			*	relations;

// attributes
@property (strong,nonatomic)	NSDictionary	*	tags;
@property (assign,nonatomic)	long long			ident;
@property (strong,nonatomic)	NSString		*	user;
@property (strong,nonatomic)	NSString		*	timestamp;
@property (assign,nonatomic)	int32_t				version;
@property (assign,nonatomic)	OsmIdentifier		changeset;
@property (assign,nonatomic)	int32_t				uid;
@property (assign,nonatomic)	BOOL				visible;

// extra stuff
@property (strong,nonatomic)	TagInfo				*	tagInfo;
@property (strong,nonatomic)	NSMutableDictionary	*	renderProperties;
@property (assign,nonatomic)	NSInteger			renderPriorityCached;
@property (assign,nonatomic)	OSMRect				boundingBox;

#if 0
-(OSMRect)boundingBoxCompute;

+(NSArray *)typeKeys;
+(NSDateFormatter *)rfc3339DateFormatter;

-(void)constructTag:(NSString *)tag value:(NSString *)value;
-(void)constructBaseAttributesFromXmlDict:(NSDictionary *)attributeDict;
-(void)constructAsUserCreated:(NSString *)userName;
-(void)setConstructed;
-(void)incrementModifyCount:(UndoManager *)undo;
-(void)setTags:(NSDictionary *)tags undo:(UndoManager *)undo;
-(void)setTimestamp:(NSDate *)date undo:(UndoManager *)undo;
-(void)setDeleted:(BOOL)deleted undo:(UndoManager *)undo;
-(void)resetModifyCount:(UndoManager *)undo;
-(void)serverUpdateVersion:(NSInteger)version;
-(void)serverUpdateIdent:(OsmIdentifier)ident;
-(void)serverUpdateInPlace:(OsmBaseObject *)newerVersion;
-(void)addRelation:(OsmRelation *)relation undo:(UndoManager *)undo;
-(void)removeRelation:(OsmRelation *)relation undo:(UndoManager *)undo;

-(OsmNode *)isNode;
-(OsmWay *)isWay;
-(OsmRelation *)isRelation;

-(NSDate *)dateForTimestamp;

-(NSSet *)nodeSet;
-(BOOL)overlapsBox:(OSMRect)box;
-(OSMRect)boundingBox;
-(NSString *)friendlyDescription;

-(BOOL)hasInterestingTags;

-(BOOL)isCoastline;

-(BOOL)isModified;

+(NSInteger)nextUnusedIdentifier;
#endif
@end



@interface OsmNodeCD : OsmBaseObjectCD
{
}
@property (assign,nonatomic)	double		lat;
@property (assign,nonatomic)	double		lon;
@property (assign,nonatomic)	NSInteger	wayCount;

#if 0
-(void)setLongitude:(double)longitude latitude:(double)latitude undo:(UndoManager *)undo;
-(void)setWayCount:(NSInteger)wayCount undo:(UndoManager *)undo;

-(OSMPoint)location;
#endif

@end
