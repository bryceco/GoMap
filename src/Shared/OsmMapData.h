//
//  OsmMapData.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

#import "DDXML.h"
//#import "MyUndoManager.h"
#import "VectorMath.h"

@class EditorMapLayer;
@class MapView;
@class NetworkStatus;
@class NSXMLDocument;
@class OsmBaseObject;
@class OsmMember;
@class OsmNode;
@class OsmRelation;
@class OsmWay;
@class QuadBox;
@class QuadMap;
@class QuadMapC;
@class OsmUserStatistics;

extern NSString * OSM_API_URL;	//	@"http://api.openstreetmap.org/"


typedef void 		(^EditAction)(void);
typedef void 		(^EditActionWithNode)(OsmNode * node);
typedef OsmWay    * (^EditActionReturnWay)(void);
typedef OsmNode   * (^EditActionReturnNode)(void);



@interface OsmUserStatistics : NSObject
@property (strong,nonatomic)	NSString	*	user;
@property (strong,nonatomic)	NSDate		*	lastEdit;
@property (assign,nonatomic)	NSInteger		editCount;
@property (strong,nonatomic)	NSMutableSet *	changeSets;
@property (assign,nonatomic)	NSInteger		changeSetsCount;
@end



@interface OsmMapData : NSObject <NSXMLParserDelegate, NSCoding, NSKeyedArchiverDelegate, NSKeyedUnarchiverDelegate>
{
	NSString										*	_parserCurrentElementText;
	NSMutableArray									*	_parserStack;
	NSError											*	_parseError;
	NSMutableDictionary<NSNumber *, OsmNode *>		*	_nodes;
	NSMutableDictionary<NSNumber *, OsmWay *>		*	_ways;
	NSMutableDictionary<NSNumber *, OsmRelation *>	*	_relations;
	QuadMap											*	_region;	// currently downloaded region
	QuadMap											*	_spatial;	// spatial index of osm data
	MyUndoManager									*	_undoManager;
	NSTimer											*	_periodicSaveTimer;
}

/**
 Initializes the object.

 @param userDefaults The `UserDefaults` instance to use.
 @return An initialized instance of this object.
 */
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults NS_DESIGNATED_INITIALIZER;

@property (copy,nonatomic)	NSString *	credentialsUserName;
@property (copy,nonatomic)	NSString *	credentialsPassword;

+(void)setEditorMapLayerForArchive:(EditorMapLayer *)editorLayer; // only used when saving/restoring undo manager
+(EditorMapLayer *)editorMapLayerForArchive; // only used when saving/restoring undo manager

-(void)save;
-(instancetype)initWithCachedData NS_DESIGNATED_INITIALIZER;

-(NSString *)getServer;
-(void)setServer:(NSString *)hostname;

-(void)purgeHard;
-(void)purgeSoft;

// undo manager interface
-(NSDictionary *)undo;
-(NSDictionary *)redo;
-(BOOL)canUndo;
-(BOOL)canRedo;
-(void)beginUndoGrouping;
-(void)endUndoGrouping;
-(void)removeMostRecentRedo;
-(void)addChangeCallback:(void(^)(void))callback;
-(void)clearUndoStack;
-(NSString *)undoManagerDescription;

// undo comments
@property (strong,nonatomic)	NSDictionary * 	(^undoContextForComment)(NSString * comment);
@property (strong,nonatomic) 	void 			(^undoCommentCallback)(BOOL undo,NSDictionary * context);
-(void)registerUndoCommentString:(NSString *)comment;
-(void)registerUndoCommentContext:(NSDictionary *)context;

-(NSInteger)modificationCount;

-(BOOL)discardStaleData;

-(int32_t)wayCount;
-(int32_t)nodeCount;
-(int32_t)relationCount;

-(NSArray<OsmWay *> *)waysContainingNode:(OsmNode *)node;

-(OsmNode *)nodeForRef:(NSNumber *)ref;
-(OsmWay *)wayForRef:(NSNumber *)ref;
-(OsmRelation *)relationForRef:(NSNumber *)ref;

- (void)enumerateObjectsUsingBlock:(void (^)(OsmBaseObject * obj))block;
- (void)enumerateObjectsInRegion:(OSMRect)bbox block:(void (^)(OsmBaseObject * _Nonnull obj))block;
- (OsmBaseObject *)objectWithExtendedIdentifier:(NSNumber *)extendedIdentifier;

- (void)clearCachedProperties;

-(NSMutableSet<NSString *> *)tagValuesForKey:(NSString *)key;

// editing
@property (class,readonly) NSSet<NSString *> * tagsToAutomaticallyStrip;

-(OsmNode *)createNodeAtLocation:(CLLocationCoordinate2D)loc;
-(OsmWay *)createWay;
-(OsmRelation *)createRelation;


-(void)setLongitude:(double)longitude latitude:(double)latitude forNode:(OsmNode *)node;
-(void)setTags:(NSDictionary<NSString *, NSString *> *)dict forObject:(OsmBaseObject *)object;

// download data
- (void)updateWithBox:(OSMRect)box progressDelegate:(MapView *)mapView completion:(void(^)(BOOL partial,NSError * error))completion;
- (void)cancelCurrentDownloads;

// upload changeset
- (NSAttributedString *)changesetAsAttributedString;
- (NSString *)changesetAsXml;
- (void)uploadChangesetWithComment:(NSString *)comment source:(NSString *)source imagery:(NSString *)imagery completion:(void(^)(NSString * error))completion;
- (void)uploadChangesetXml:(NSXMLDocument *)xmlDoc comment:(NSString *)comment source:(NSString *)source imagery:(NSString *)imagery completion:(void(^)(NSString * error))completion;
- (void)verifyUserCredentialsWithCompletion:(void(^)(NSString * errorMessage))completion;
- (void)putRequest:(NSString *)url method:(NSString *)method xml:(NSXMLDocument *)xml completion:(void(^)(NSData * data,NSString * error))completion;
+(NSString *)encodeBase64:(NSString *)plainText;

-(NSArray<OsmUserStatistics *> *)userStatisticsForRegion:(OSMRect)rect;

-(void)consistencyCheck;

@end
