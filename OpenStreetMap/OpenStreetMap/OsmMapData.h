//
//  XmlParserDelegate.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class MapView;
@class QuadBox;
@class QuadMap;
@class OsmBaseObject;
@class OsmNode;
@class OsmWay;
@class OsmMember;
@class OsmRelation;
@class UndoManager;


extern BOOL OsmBooleanForValue( NSString * value );
extern NSString * OsmValueForBoolean( BOOL b );


#if 1
#define OSM_API_URL	@"http://api.openstreetmap.org/"
#elif 1
#define OSM_API_URL	@"http://api.hosm.gwhat.org/"
#elif 0
#define OSM_API_URL	@"http://api06.dev.openstreetmap.org/"
#endif




@interface OsmUserStatistics : NSObject
@property (strong,nonatomic)	NSString	*	user;
@property (strong,nonatomic)	NSDate		*	lastEdit;
@property (assign,nonatomic)	NSInteger		editCount;
@property (strong,nonatomic)	NSMutableSet *	changeSets;
@property (assign,nonatomic)	NSInteger		changeSetsCount;
@end



@interface OsmMapData : NSObject <NSXMLParserDelegate, NSCoding, NSKeyedArchiverDelegate>
{
	NSString			*	_parserCurrentElementText;
	NSMutableArray		*	_parserStack;
	NSError				*	_parseError;
	NSMutableDictionary	*	_nodes;
	NSMutableDictionary	*	_ways;
	NSMutableDictionary	*	_relations;
	QuadMap				*	_region;	// currently downloaded region
	QuadBox				*	_spatial;	// spatial index of osm data
	UndoManager			*	_undoManager;

	BOOL					_substSpatialOnSave;
}

@property (copy,nonatomic)	NSString *	credentialsUserName;
@property (copy,nonatomic)	NSString *	credentialsPassword;

-(id)initWithCachedData;
-(BOOL)saveSubstitutingSpatial:(BOOL)substituteSpatial;

-(void)purgeHard;
-(void)purgeSoft;

// undo manager interface
-(void)undo;
-(void)redo;
-(BOOL)canUndo;
-(BOOL)canRedo;
-(void)beginUndoGrouping;
-(void)endUndoGrouping;
-(void)removeMostRecentRedo;
-(void)setUndoLocationCallback:(NSData * (^)(void))callback;


-(void)addChangeCallback:(void(^)(void))callback;
-(void)clearUndoStack;
-(void)setConstructed:(OsmBaseObject *)object;

-(OsmMapData *)modifiedObjects;

-(int32_t)wayCount;
-(int32_t)nodeCount;
-(int32_t)relationCount;

-(OsmNode *)nodeForRef:(NSNumber *)ref;
-(OsmWay *)wayForRef:(NSNumber *)ref;
-(OsmRelation *)relationForRef:(NSNumber *)ref;

- (void)enumerateObjectsUsingBlock:(void (^)(OsmBaseObject * obj))block;
- (void)enumerateObjectsInRegion:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;

-(NSMutableSet *)tagValuesForKey:(NSString *)key;

// editing
-(OsmNode *)createNodeAtLocation:(CLLocationCoordinate2D)loc;
-(OsmWay *)createWay;
-(OsmRelation *)createRelation;
-(void)deleteNode:(OsmNode *)node;
-(void)deleteWay:(OsmWay *)way;
-(void)addNode:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index;
-(void)deleteNodeInWay:(OsmWay *)way index:(NSInteger)index;

-(void)addMember:(OsmMember *)member toRelation:(OsmRelation *)relation atIndex:(NSInteger)index;
-(void)deleteMemberInRelation:(OsmRelation *)relation index:(NSInteger)index;

-(void)setLongitude:(double)longitude latitude:(double)latitude forNode:(OsmNode *)node inWay:(OsmWay *)way;
-(void)setTags:(NSDictionary *)dict forObject:(OsmBaseObject *)object;
-(void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects;
@property (strong,nonatomic) void (^undoCommentCallback)(BOOL,NSArray *);


- (void)updateWithBox:(OSMRect)box mapView:(MapView *)mapView completion:(void(^)(BOOL partial,NSError * error))completion;

// upload changeset
- (NSAttributedString *)changesetAsAttributedString;
- (NSArray *)createChangeset;
- (NSString *)changesetAsXml;
- (NSString *)changesetAsHtml;
- (void)uploadChangeset:(NSString *)comment completion:(void(^)(NSString * error))completion;
- (void)verifyUserCredentialsWithCompletion:(void(^)(NSString * errorMessage))completion;

-(NSArray *)userStatisticsForRegion:(OSMRect)rect;
-(OSMRect)rootRect;

@end
