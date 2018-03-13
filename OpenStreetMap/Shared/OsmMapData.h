//
//  XmlParserDelegate.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

#import "UndoManager.h"
#import "VectorMath.h"

@class EditorMapLayer;
@class MapView;
@class NSXMLDocument;
@class OsmBaseObject;
@class OsmMember;
@class OsmNode;
@class OsmRelation;
@class OsmWay;
@class QuadBox;
@class QuadMap;
@class QuadMapC;


BOOL IsOsmBooleanTrue( NSString * value );
BOOL IsOsmBooleanFalse( NSString * value );
extern NSString * OsmValueForBoolean( BOOL b );


#if 1
//#define OSM_API_URL	@"http://api.openstreetmap.org/"
extern NSString * OSM_API_URL;//	@"http://api.openstreetmap.org/"
//#define OSM_API_URL	@"http://api.openstreetmap.fr/"	// faster: 4.62 seconds compared to 7.4 for .org server
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



@interface OsmMapData : NSObject <NSXMLParserDelegate, NSCoding, NSKeyedArchiverDelegate, NSKeyedUnarchiverDelegate, UndoManagerDelegate>
{
	NSString			*	_parserCurrentElementText;
	NSMutableArray		*	_parserStack;
	NSError				*	_parseError;
	NSMutableDictionary	*	_nodes;
	NSMutableDictionary	*	_ways;
	NSMutableDictionary	*	_relations;
	QuadMap				*	_region;	// currently downloaded region
	QuadMap				*	_spatial;	// spatial index of osm data
	UndoManager			*	_undoManager;
	NSTimer				*	_periodicSaveTimer;
}

@property (copy,nonatomic)	NSString *	credentialsUserName;
@property (copy,nonatomic)	NSString *	credentialsPassword;

+(void)setEditorMapLayerForArchive:(EditorMapLayer *)editorLayer; // only used when saving/restoring undo manager
+(EditorMapLayer *)editorMapLayerForArchive; // only used when saving/restoring undo manager

-(id)initWithCachedData;
-(void)save;

-(NSString *)getServer;
-(void)setServer:(NSString *)hostname;

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
-(NSString *)undoManagerDescription;

-(void)addChangeCallback:(void(^)(void))callback;
-(void)clearUndoStack;
-(void)setConstructed:(OsmBaseObject *)object;

-(OsmMapData *)modifiedObjects;

-(int32_t)wayCount;
-(int32_t)nodeCount;
-(int32_t)relationCount;

-(NSArray *)waysContainingNode:(OsmNode *)node;
-(NSArray *)objectsContainingObject:(OsmBaseObject *)object;

-(OsmNode *)nodeForRef:(NSNumber *)ref;
-(OsmWay *)wayForRef:(NSNumber *)ref;
-(OsmRelation *)relationForRef:(NSNumber *)ref;

- (void)enumerateObjectsUsingBlock:(void (^)(OsmBaseObject * obj))block;
- (void)enumerateObjectsInRegion:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block;
- (OsmBaseObject *)objectWithExtendedIdentifier:(NSNumber *)extendedIdentifier;

- (void)clearCachedProperties;

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
- (void)uploadChangeset:(NSXMLDocument *)xmlChanges comment:(NSString *)comment retries:(NSInteger)retries completion:(void(^)(NSString * error))completion;
- (void)uploadChangesetWithComment:(NSString *)comment completion:(void(^)(NSString * error))completion;
- (void)verifyUserCredentialsWithCompletion:(void(^)(NSString * errorMessage))completion;
- (void)putRequest:(NSString *)url method:(NSString *)method xml:(NSXMLDocument *)xml completion:(void(^)(NSData * data,NSString * error))completion;
+(NSString *)encodeBase64:(NSString *)plainText;

-(NSArray *)userStatisticsForRegion:(OSMRect)rect;
-(OSMRect)rootRect;

@end
