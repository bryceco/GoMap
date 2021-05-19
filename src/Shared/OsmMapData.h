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

extern NSString * _Nonnull OSM_API_URL;	//	@"http://api.openstreetmap.org/"

typedef void 		(^EditAction)(void);
typedef void 		(^EditActionWithNode)(OsmNode * _Nonnull node);
typedef OsmWay    * _Nonnull (^EditActionReturnWay)(void);
typedef OsmNode   * _Nonnull(^EditActionReturnNode)(void);



@interface OsmUserStatistics : NSObject
@property (strong,nonatomic)	NSString	*_Nonnull	user;
@property (strong,nonatomic)	NSDate		*_Nonnull	lastEdit;
@property (assign,nonatomic)	NSInteger				editCount;
@property (strong,nonatomic)	NSMutableSet *_Nonnull	changeSets;
@property (assign,nonatomic)	NSInteger				changeSetsCount;
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
- (instancetype _Nullable)initWithUserDefaults:(NSUserDefaults *_Nonnull)userDefaults NS_DESIGNATED_INITIALIZER;

@property (copy,nonatomic)	NSString *_Nullable	credentialsUserName;
@property (copy,nonatomic)	NSString *_Nullable	credentialsPassword;

+(void)setEditorMapLayerForArchive:(EditorMapLayer *_Nonnull)editorLayer; // only used when saving/restoring undo manager
+(EditorMapLayer *_Nullable)editorMapLayerForArchive; // only used when saving/restoring undo manager

-(void)save;
-(instancetype _Nullable)initWithCachedData NS_DESIGNATED_INITIALIZER;

-(NSString *_Nonnull)getServer;
-(void)setServer:(NSString *_Nullable)hostname;

-(void)purgeHard;
-(void)purgeSoft;

// undo manager interface
-(NSDictionary *_Nonnull)undo;
-(NSDictionary *_Nonnull)redo;
-(BOOL)canUndo;
-(BOOL)canRedo;
-(void)beginUndoGrouping;
-(void)endUndoGrouping;
-(void)removeMostRecentRedo;
-(void)addChangeCallback:(void(^_Nonnull)(void))callback;
-(void)clearUndoStack;
-(NSString *_Nonnull)undoManagerDescription;

// undo comments
@property (strong,nonatomic)	NSDictionary *_Nonnull 	(^ _Nullable undoContextForComment)(NSString *_Nonnull comment);
@property (strong,nonatomic) 	void 					(^ _Nullable undoCommentCallback)(BOOL undo,NSDictionary *_Nonnull context);
-(void)registerUndoCommentString:(NSString *_Nonnull)comment;
-(void)registerUndoCommentContext:(NSDictionary *_Nonnull)context;

-(NSInteger)modificationCount;

-(BOOL)discardStaleData;

-(int32_t)wayCount;
-(int32_t)nodeCount;
-(int32_t)relationCount;

-(NSArray<OsmWay *> *_Nonnull)waysContainingNode:(OsmNode *_Nonnull)node;

-(OsmNode *_Nullable)nodeForRef:(NSNumber *_Nonnull)ref;
-(OsmWay *_Nullable)wayForRef:(NSNumber *_Nonnull)ref;
-(OsmRelation *_Nullable)relationForRef:(NSNumber *_Nonnull)ref;

- (void)enumerateObjectsUsingBlock:(void (^_Nonnull)(OsmBaseObject * _Nonnull obj))block;
- (void)enumerateObjectsInRegion:(OSMRect)bbox block:(void (^_Nonnull)(OsmBaseObject * _Nonnull obj))block;
- (OsmBaseObject *_Nullable)objectWithExtendedIdentifier:(NSNumber *_Nonnull)extendedIdentifier;

- (void)clearCachedProperties;

-(NSMutableSet<NSString *> *_Nonnull)tagValuesForKey:(NSString *_Nonnull)key;

// editing
@property (class,readonly) NSSet<NSString *> * _Nonnull tagsToAutomaticallyStrip;

-(OsmNode *_Nonnull)createNodeAtLocation:(CLLocationCoordinate2D)loc;
-(OsmWay *_Nonnull)createWay;
-(OsmRelation *_Nonnull)createRelation;


-(void)setLongitude:(double)longitude latitude:(double)latitude forNode:(OsmNode *_Nonnull)node;
-(void)setTags:(NSDictionary<NSString *, NSString *> *_Nonnull)dict forObject:(OsmBaseObject *_Nonnull)object;

// download data
- (void)updateWithBox:(OSMRect)box progressDelegate:(MapView *_Nonnull)mapView completion:(void(^_Nonnull)(BOOL partial,NSError * _Nullable error))completion;
- (void)cancelCurrentDownloads;

// upload changeset
- (NSAttributedString *_Nullable)changesetAsAttributedString;
- (NSString * _Nullable)changesetAsXml;
- (void)uploadChangesetWithComment:(NSString * _Nullable)comment source:(NSString * _Nullable)source imagery:(NSString * _Nullable)imagery completion:(void(^_Nullable)(NSString * _Nullable error))completion;
- (void)uploadChangesetXml:(NSXMLDocument * _Nullable)xmlDoc comment:(NSString * _Nullable)comment source:(NSString *_Nullable)source imagery:(NSString *_Nullable)imagery completion:(void(^_Nullable)(NSString *_Nullable error))completion;
- (void)verifyUserCredentialsWithCompletion:(void(^_Nonnull)(NSString *_Nullable errorMessage))completion;
- (void)putRequest:(NSString *_Nonnull)url method:(NSString *_Nonnull)method xml:(NSXMLDocument * _Nonnull)xml completion:(void(^_Nonnull)(NSData *_Nullable data,NSString *_Nullable error))completion;
+(NSString *_Nullable)encodeBase64:(NSString *_Nullable)plainText;

-(NSArray<OsmUserStatistics *> *_Nonnull)userStatisticsForRegion:(OSMRect)rect;

-(void)consistencyCheck;

@end
