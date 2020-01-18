//
//  OsmObjects.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/27/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "OsmBaseObject.h"

@class CAShapeLayer;
@class CurvedTextLayer;
@class OsmBaseObject;
@class OsmMapData;
@class OsmMember;
@class OsmNode;
@class OsmWay;
@class UndoManager;

BOOL IsInterestingTag(NSString * key);
NSDictionary * MergeTags(NSDictionary * myself, NSDictionary * tags, BOOL failOnConflict);


BOOL IsOsmBooleanTrue( NSString * value );
BOOL IsOsmBooleanFalse( NSString * value );

@interface OsmMember : NSObject <NSCoding>
{
	NSString *	_type;	// way, node, or relation: to help identify ref
	id			_ref;
	NSString *	_role;
}
@property (readonly,nonatomic)	NSString *	type;
@property (readonly,nonatomic)	id			ref;
@property (readonly,nonatomic)	NSString *	role;

-(id)initWithType:(NSString *)type ref:(NSNumber *)ref role:(NSString *)role;
-(id)initWithRef:(OsmBaseObject *)ref role:(NSString *)role;
-(void)resolveRefToObject:(OsmBaseObject *)object;

-(BOOL)isNode;
-(BOOL)isWay;
-(BOOL)isRelation;
@end
