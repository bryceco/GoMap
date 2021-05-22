//
//  OsmMapData.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <zlib.h>

#if TARGET_OS_IPHONE
#import "DDXML.h"
//#import "../iOS/AppDelegate.h"
#else
//#import "AppDelegate.h"
#endif

#import "DLog.h"
//#import "DownloadThreadPool.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmMapData+Edit.h"
//#import "OsmMember.h"
//#import "QuadMap.h"
//#import "MyUndoManager.h"
#import "VectorMath.h"

#import "Database.h"
//#import "EditorMapLayer.h"

#define OSM_SERVER_KEY	@"OSM Server"

NSString * OSM_API_URL;

@implementation OsmUserStatistics
@synthesize changeSetsCount = _changeSetsCount;
-(id)copyWithZone:(NSZone *)zone
{
	return self;
}
@end


@interface ServerQuery : NSObject
@property (strong,nonatomic)	NSMutableArray *	quadList;
@property (assign,nonatomic)	OSMRect				rect;
@end
@implementation ServerQuery
@end


#pragma mark OsmMapData

@interface OsmMapData ()

@property (readonly,nonnull) NSUserDefaults *userDefaults;
@property (readonly,nonnull)    NSDate *            previousDiscardDate;

@end



@implementation OsmMapData

static EditorMapLayer * g_EditorMapLayerForArchive = nil;

+(void)setEditorMapLayerForArchive:(EditorMapLayer *)editorLayer
{
	DbgAssert(editorLayer);
	g_EditorMapLayerForArchive = editorLayer;

}
+(EditorMapLayer *)editorMapLayerForArchive
{
	DbgAssert(g_EditorMapLayerForArchive);
	return g_EditorMapLayerForArchive;
}

-(void)initCommon
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[self.userDefaults registerDefaults:@{ OSM_SERVER_KEY : @"https://api.openstreetmap.org/" }];
	});
	NSString * server = [self.userDefaults objectForKey:OSM_SERVER_KEY];
	[self setServer:server];
	[self setupPeriodicSaveTimer];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
    if (self = [super init]) {
        _userDefaults = userDefaults;
        _parserStack    = [NSMutableArray arrayWithCapacity:20];
        _nodes            = [NSMutableDictionary dictionaryWithCapacity:1000];
        _ways            = [NSMutableDictionary dictionaryWithCapacity:1000];
        _relations        = [NSMutableDictionary dictionaryWithCapacity:10];
        _region            = [QuadMap new];
        _spatial        = [QuadMap new];
        _undoManager    = [MyUndoManager new];
        
        [self initCommon];
    }
    
    return self;
}

- (instancetype)init {
    return [self initWithUserDefaults:[NSUserDefaults standardUserDefaults]];
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MyUndoManager.UndoManagerDidChangeNotification object:_undoManager];
	[_periodicSaveTimer invalidate];
}

-(void)setServer:(NSString *)hostname
{
	hostname = [hostname stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if ( hostname.length == 0 )
		hostname = @"api.openstreetmap.org";

	if ( [hostname hasPrefix:@"http://"] || [hostname hasPrefix:@"https://"] ) {
		// great
	} else {
		hostname = [@"https://" stringByAppendingString:hostname];
	}

	while ( [hostname hasSuffix:@"//"] ) {
		// fix for previous releases that may have accidently set an extra slash
		hostname = [hostname substringToIndex:hostname.length-1];
	}
	if ( [hostname hasSuffix:@"/"] ) {
		// great
	} else {
		hostname = [hostname stringByAppendingString:@"/"];
	}

	if ( [OSM_API_URL isEqualToString:hostname] ) {
		// no change
		return;
	}

	if ( OSM_API_URL.length ) {
		// get rid of old data before connecting to new server
		[self purgeSoft];
	}
	
	[self.userDefaults setObject:hostname forKey:OSM_SERVER_KEY];
	OSM_API_URL = hostname;
}

-(NSString *)getServer
{
	return OSM_API_URL;
}

-(void)setupPeriodicSaveTimer
{
	__weak OsmMapData * weakSelf = self;

	[[NSNotificationCenter defaultCenter] addObserverForName:MyUndoManager.UndoManagerDidChangeNotification object:_undoManager queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		OsmMapData * myself = weakSelf;
		if ( myself == nil )
			return;
		if ( myself->_periodicSaveTimer == nil ) {
			myself->_periodicSaveTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:myself selector:@selector(periodicSave:) userInfo:nil repeats:NO];
		}
	}];
}
-(void)periodicSave:(NSTimer *)timer
{
	AppDelegate * appDelegate = AppDelegate.shared;
	[appDelegate.mapView save];	// this will also invalidate the timer
}


+(NSSet<NSString *> *)tagsToAutomaticallyStrip
{
	static dispatch_once_t onceToken;
	static NSSet<NSString *> * s_ignoreSet = nil;
	dispatch_once(&onceToken, ^{
		s_ignoreSet = [NSSet setWithObjects:
				@"tiger:upload_uuid",
				@"tiger:tlid",
				@"tiger:source",
				@"tiger:separated",
				@"geobase:datasetName",
				@"geobase:uuid",
				@"sub_sea:type",
				@"odbl",
				@"odbl:note",
				@"yh:LINE_NAME",
				@"yh:LINE_NUM",
				@"yh:STRUCTURE",
				@"yh:TOTYUMONO",
				@"yh:TYPE",
				@"yh:WIDTH_RANK",
				nil];
	});
	return s_ignoreSet;
}


-(void)setConstructed
{
	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident,OsmNode * node,BOOL * stop) {
		[node setConstructed];
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident,OsmWay * way,BOOL * stop) {
		[way setConstructed];
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident,OsmRelation * relation,BOOL * stop) {
		[relation setConstructed];
	}];
}

-(int32_t)wayCount
{
	return (int32_t)_ways.count;
}
-(int32_t)nodeCount
{
	return (int32_t)_nodes.count;
}
-(int32_t)relationCount
{
	return (int32_t)_relations.count;
}

-(OsmNode *)nodeForRef:(NSNumber *)ref
{
	return [_nodes objectForKey:ref];
}
-(OsmWay *)wayForRef:(NSNumber *)ref
{
	return [_ways objectForKey:ref];
}
-(OsmRelation *)relationForRef:(NSNumber *)ref
{
	return [_relations objectForKey:ref];
}

- (OsmBaseObject *)objectWithExtendedIdentifier:(NSNumber *)extendedIdentifier
{
	OsmIdentifier	ident;
	OSM_TYPE		type;
	[OsmBaseObject decomposeExtendedIdentifier:extendedIdentifier.longLongValue type:&type ident:&ident];
	switch ( type ) {
		case OSM_TYPE_NODE:
			return _nodes[ @(ident) ];
		case OSM_TYPE_WAY:
			return _ways[ @(ident) ];
		case OSM_TYPE_RELATION:
			return _relations[ @(ident) ];
		default:
			return nil;
	}
}

-(NSArray<OsmWay *> *)waysContainingNode:(OsmNode *)node
{
	__block NSMutableArray<OsmWay *> * a = [NSMutableArray new];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * w, BOOL *stop) {
		if ( [w.nodes containsObject:node] )
			[a addObject:w];
	}];
	return a;
}
-(NSArray *)objectsContainingObject:(OsmBaseObject *)object
{
	__block NSMutableArray * a = [NSMutableArray new];
	if ( object.isNode ) {
		[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
			if ( [way.nodes containsObject:(id)object] )
				[a addObject:way];
		}];
	}
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		if ( [relation containsObject:object] )
			[a addObject:relation];
	}];
	return a;
}



- (void)enumerateObjectsUsingBlock:(void (^)(OsmBaseObject * obj))block
{
	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident,OsmNode * node,BOOL * stop){
		block( node );
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident,OsmWay * way,BOOL * stop) {
		block( way );
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident,OsmRelation * relation,BOOL * stop){
		block( relation );
	}];
}
- (void)enumerateObjectsInRegion:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block
{
#if 0 && DEBUG
	NSLog(@"box = %@",NSStringFromCGRect(CGRectFromOSMRect(bbox)));
#endif
	if ( bbox.origin.x < 180 && bbox.origin.x + bbox.size.width > 180 ) {
		OSMRect left = { bbox.origin.x, bbox.origin.y, 180-bbox.origin.x, bbox.size.height };
		OSMRect right = { -180, bbox.origin.y, bbox.origin.x + bbox.size.width - 180, bbox.size.height };
		[self enumerateObjectsInRegion:left block:block];
		[self enumerateObjectsInRegion:right block:block];
		return;
	}

	[_spatial findObjectsInArea:bbox block:block];
}


-(NSMutableSet<NSString *> *)tagValuesForKey:(NSString *)key
{
	NSMutableSet<NSString *> * set = [NSMutableSet set];
	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmBaseObject * object, BOOL *stop) {
		NSString * value = [object.tags objectForKey:key];
		if ( value ) {
			[set addObject:value];
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmBaseObject * object, BOOL *stop) {
		NSString * value = [object.tags objectForKey:key];
		if ( value ) {
			[set addObject:value];
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmBaseObject * object, BOOL *stop) {
		NSString * value = [object.tags objectForKey:key];
		if ( value ) {
			[set addObject:value];
		}
	}];

	// special case for street names
	if ( [key isEqualToString:@"addr:street"] ) {
		[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmBaseObject * object, BOOL *stop) {
			NSString * value = [object.tags objectForKey:@"highway"];
			if ( value ) {
				value = [object.tags objectForKey:@"name"];
				if ( value ) {
					[set addObject:value];
				}
			}
		}];
	}
	return set;
}


-(NSArray<OsmUserStatistics *> *)userStatisticsForRegion:(OSMRect)rect
{
	NSMutableDictionary<NSString *, OsmUserStatistics *> * dict = [NSMutableDictionary dictionary];

	[self enumerateObjectsInRegion:rect block:^(OsmBaseObject * base) {
		NSDate * date = [base dateForTimestamp];
		if ( base.user.length == 0 ) {
			DLog(@"Empty user name for object: object %@, uid = %ld", base, (long)base.uid);
			return;
		}
		OsmUserStatistics * stats = dict[ base.user ];
		if ( stats == nil ) {
			stats = [OsmUserStatistics new];
			stats.user = base.user;
			stats.changeSets = [NSMutableSet setWithObject:@(base.changeset)];
			stats.lastEdit = date;
			stats.editCount = 1;
			dict[ base.user ] = stats;
		} else {
			++stats.editCount;
			[stats.changeSets addObject:@(base.changeset)];
			if ( [date compare:stats.lastEdit] > 0 )
				stats.lastEdit = date;
		}
		stats.changeSetsCount = stats.changeSets.count;
	}];

	return [dict allValues];
}

- (void)clearCachedProperties
{
	[self enumerateObjectsUsingBlock:^(OsmBaseObject *obj) {
		[obj clearCachedProperties];
	}];
}


-(NSInteger)modificationCount
{
	__block NSInteger modifications = 0;
	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmNode * node, BOOL *stop) {
		modifications += node.deleted ? node.ident > 0 : node.isModified;
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
		modifications += way.deleted ? way.ident > 0 : way.isModified;
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		modifications += relation.deleted ? relation.ident > 0 : relation.isModified;
	}];
	NSInteger undoCount = _undoManager.countUndoGroups;
	return MIN(modifications,undoCount);	// different ways to count, but both can be inflated so take the minimum
}

#pragma mark Editing

-(void)incrementModifyCount:(OsmBaseObject *)object
{
	[_undoManager registerUndoWithTarget:self selector:@selector(incrementModifyCount:) objects:@[object]];
	[object incrementModifyCount:_undoManager];
}

-(void)clearCachedProperties:(OsmBaseObject *)object undo:(MyUndoManager *)undo
{
	[undo registerUndoWithTarget:self selector:@selector(clearCachedProperties:undo:) objects:@[object,undo]];
	[object clearCachedProperties];
}

static NSString * StringTruncatedTo255( NSString * s )
{
	if ( s.length > 255 )
		s = [s substringToIndex:255];
	return s;
}
static NSDictionary * DictWithTagsTruncatedTo255( NSDictionary * tags )
{
	NSMutableDictionary * newDict = [[NSMutableDictionary alloc] initWithCapacity:tags.count];
	[tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
		key		= StringTruncatedTo255( key );
		value	= StringTruncatedTo255( value );
		[newDict setObject:value forKey:key];
	}];
	return newDict;
}

-(void)setTags:(NSDictionary<NSString *, NSString *> *)dict forObject:(OsmBaseObject *)object
{
	dict = DictWithTagsTruncatedTo255( dict );

	[self registerUndoCommentString:NSLocalizedString(@"set tags",nil)];

	[object setTags:dict undo:_undoManager];
}


-(OsmNode *)createNodeAtLocation:(CLLocationCoordinate2D)loc
{
	OsmNode * node = [OsmNode new];
	[node constructAsUserCreated:self.credentialsUserName];
	[node setLongitude:loc.longitude latitude:loc.latitude undo:nil];
	[node setDeleted:YES undo:nil];
	[self setConstructed:node];
	[_nodes setObject:node forKey:@(node.ident)];
	
	[self registerUndoCommentString:NSLocalizedString(@"create node",nil)];
	[node setDeleted:NO undo:_undoManager];
	[_spatial addMember:node undo:_undoManager];
	return node;
}

-(OsmWay *)createWay
{
	OsmWay * way = [OsmWay new];
	[way constructAsUserCreated:self.credentialsUserName];
	[way setDeleted:YES undo:nil];
	[self setConstructed:way];
	[_ways setObject:way forKey:@(way.ident)];

	[self registerUndoCommentString:NSLocalizedString(@"create way",nil)];
	[way setDeleted:NO undo:_undoManager];
	return way;
}

-(OsmRelation *)createRelation
{
	OsmRelation * relation = [OsmRelation new];
	[relation constructAsUserCreated:self.credentialsUserName];
	[relation setDeleted:YES undo:nil];
	[self setConstructed:relation];
	[_relations setObject:relation forKey:@(relation.ident)];

	[self registerUndoCommentString:NSLocalizedString(@"create relation",nil)];
	[relation setDeleted:NO undo:_undoManager];
	return relation;
}

-(void)removeFromParentRelationsUnsafe:(OsmBaseObject *)object
{
	while ( object.parentRelations.count ) {
		OsmRelation * relation = object.parentRelations.lastObject;
		NSInteger memberIndex = 0;
		while ( memberIndex < relation.members.count ) {
			OsmMember * member = relation.members[memberIndex];
			if ( member.obj == object ) {
				[self deleteMemberInRelationUnsafe:relation index:memberIndex];
			} else {
				++memberIndex;
			}
		}
	}
}


-(void)deleteNodeUnsafe:(OsmNode *)node
{
	assert( node.wayCount == 0 );
	[self registerUndoCommentString:NSLocalizedString(@"delete node",nil)];

	[self removeFromParentRelationsUnsafe:node];

	[node setDeleted:YES undo:_undoManager];

	(void)[_spatial removeMember:node undo:_undoManager];
}

-(void)deleteWayUnsafe:(OsmWay *)way
{
	[self registerUndoCommentString:NSLocalizedString(@"delete way",nil)];
	(void)[_spatial removeMember:way undo:_undoManager];

	[self removeFromParentRelationsUnsafe:way];

	while ( way.nodes.count ) {
		OsmNode * node = way.nodes.lastObject;
		[self deleteNodeInWayUnsafe:way index:way.nodes.count-1 preserveNode:node.hasInterestingTags];
	}
	[way setDeleted:YES undo:_undoManager];
}

-(void)deleteRelationUnsafe:(OsmRelation *)relation
{
	NSString * message 	= relation.isRestriction ? NSLocalizedString(@"delete restriction",nil)
						: relation.isMultipolygon ? NSLocalizedString(@"delete multipolygon",nil)
						: relation.isRoute ? NSLocalizedString(@"delete route",nil)
						: NSLocalizedString(@"delete relation",nil);
	[self registerUndoCommentString:message];

	(void)[_spatial removeMember:relation undo:_undoManager];

	[self removeFromParentRelationsUnsafe:relation];

	while ( relation.members.count ) {
		[relation removeMemberAtIndex:relation.members.count-1 undo:_undoManager];
	}
	[relation setDeleted:YES undo:_undoManager];
}

-(void)addNodeUnsafe:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index
{
	[self registerUndoCommentString:NSLocalizedString(@"add node to way",nil)];
	OSMRect origBox = way.boundingBox;
	[way addNode:node atIndex:index undo:_undoManager];
	[_spatial updateMember:way fromBox:origBox undo:_undoManager];
}

-(void)deleteNodeInWayUnsafe:(OsmWay *)way index:(NSInteger)index preserveNode:(BOOL)preserveNode
{
	[self registerUndoCommentString:NSLocalizedString(@"delete node from way",nil)];
	OsmNode * node = way.nodes[ index ];
	DbgAssert( node.wayCount > 0 );

	OSMRect bbox = way.boundingBox;
	[way removeNodeAtIndex:index undo:_undoManager];
	// if removing the node leads to 2 identical nodes being consecutive delete one of them as well
	while ( index > 0 && index < way.nodes.count && way.nodes[index-1] == way.nodes[index] )
		[way removeNodeAtIndex:index undo:_undoManager];
	[_spatial updateMember:way fromBox:bbox undo:_undoManager];

	if ( node.wayCount == 0 && !preserveNode ) {
		[self deleteNodeUnsafe:node];
	}
}


#pragma mark external editing commands


-(void)setLongitude:(double)longitude latitude:(double)latitude forNode:(OsmNode *)node
{
	[self registerUndoCommentString:NSLocalizedString(@"move",nil)];

	// need to update all ways/relation which contain the node
	NSArray * parents = [self objectsContainingObject:node];
	NSMutableArray * parentBoxes = [NSMutableArray arrayWithCapacity:parents.count];
	for ( OsmBaseObject * parent in parents ) {
		[parentBoxes addObject:[OSMRectBoxed rectWithRect:parent.boundingBox]];
	}

	OSMRect bboxNode = node.boundingBox;
	[node setLongitude:longitude latitude:latitude undo:_undoManager];
	[_spatial updateMember:node fromBox:bboxNode undo:_undoManager];

	for ( NSInteger i = 0; i < parents.count; ++i ) {
		OsmBaseObject * parent = parents[i];
		OSMRectBoxed * box = parentBoxes[i];
#if 0
		// mark parent as modified when child node changes
		[self incrementModifyCount:parent];
#else
		[self clearCachedProperties:parent undo:_undoManager];
#endif
		[parent computeBoundingBox];
		[_spatial updateMember:parent fromBox:box.rect undo:_undoManager];
	}
}

-(void)addMemberUnsafe:(OsmMember *)member toRelation:(OsmRelation *)relation atIndex:(NSInteger)index
{
	[self registerUndoCommentString:NSLocalizedString(@"add object to relation",nil)];
	OSMRect bbox = relation.boundingBox;
	[relation addMember:member atIndex:index undo:_undoManager];
	[_spatial updateMember:relation fromBox:bbox undo:_undoManager];
	[self updateMultipolygonRelationRoles:relation];
}
-(void)deleteMemberInRelationUnsafe:(OsmRelation *)relation index:(NSInteger)index
{
	if ( relation.members.count == 1 ) {
		// deleting last member of relation, so delete relation
		[self deleteRelationUnsafe:relation];
	} else {
		[self registerUndoCommentString:NSLocalizedString(@"delete object from relation",nil)];
		OSMRect bbox = relation.boundingBox;
		[relation removeMemberAtIndex:index undo:_undoManager];
		[_spatial updateMember:relation fromBox:bbox undo:_undoManager];
		[self updateMultipolygonRelationRoles:relation];
	}
}
-(void)updateMembersUnsafe:(NSArray *)memberList inRelation:(OsmRelation *)relation
{
	[self registerUndoCommentString:NSLocalizedString(@"update relation members",nil)];
	OSMRect bbox = relation.boundingBox;
	[relation assignMembers:memberList undo:_undoManager];
	[_spatial updateMember:relation fromBox:bbox undo:_undoManager];

}

#pragma mark Undo manager

-(NSDictionary *)undo
{
	NSDictionary * comment = [_undoManager undo];
	if ( self.undoCommentCallback )
		self.undoCommentCallback(YES, comment);
	return comment;
}
-(NSDictionary *)redo
{
	NSDictionary * comment = [_undoManager redo];
	if ( self.undoCommentCallback )
		self.undoCommentCallback(NO, comment);
	return comment;
}
-(BOOL)canUndo
{
	return [_undoManager canUndo];
}
-(BOOL)canRedo
{
	return [_undoManager canRedo];
}
-(void)addChangeCallback:(void(^)(void))callback
{
	[[NSNotificationCenter defaultCenter] addObserverForName:MyUndoManager.UndoManagerDidChangeNotification object:_undoManager queue:nil usingBlock:^(NSNotification * _Nonnull fnote) {
		callback();
	}];
}
-(void)beginUndoGrouping
{
	[_undoManager beginUndoGrouping];
}
-(void)endUndoGrouping
{
	[_undoManager endUndoGrouping];
}
-(void)removeMostRecentRedo
{
	[_undoManager removeMostRecentRedo];
}
-(void)clearUndoStack
{
	[_undoManager removeAllActions];
}
-(void)setConstructed:(OsmBaseObject *)object
{
	[object setConstructed];
}
-(void)registerUndoCommentContext:(NSDictionary *)context
{
	[_undoManager registerUndoComment:context];
}
-(void)registerUndoCommentString:(NSString *)comment
{
	NSDictionary * context = self.undoContextForComment(comment);
	[self registerUndoCommentContext:context];
}


-(NSString *)undoManagerDescription
{
	return [_undoManager description];
}

#pragma mark Server query

// returns a list of ServerQuery objects
+ (NSArray *)coalesceQuadQueries:(NSArray *)quadList
{
	NSMutableArray * queries = [NSMutableArray new];

#if 0
	DLog(@"\nquad list:");
	for ( QuadBox * q in quadList ) DLog(@"  %@", NSStringFromRect(q.rect));
#endif

	// sort by row
	quadList = [quadList sortedArrayUsingComparator:^NSComparisonResult(QuadBox * q1, QuadBox * q2) {
		double diff = q1.rect.origin.y - q2.rect.origin.y;
		if ( diff == 0 )
			diff = q1.rect.origin.x - q2.rect.origin.x;
		return diff < 0 ? NSOrderedAscending : diff > 0 ? NSOrderedDescending : NSOrderedSame;
	}];

	ServerQuery	*	query = nil;
	OSMRect			rect;
	for ( QuadBox * q in quadList ) {
		if ( query  &&  q.rect.origin.y == rect.origin.y  &&  q.rect.origin.x == rect.origin.x+rect.size.width  &&  q.rect.size.height == rect.size.height ) {
			// combine with previous quad(s)
			[query.quadList	addObject:q];
			rect.size.width += q.rect.size.width;
			query.rect = rect;
		} else {
			// create new query for quad
			rect = q.rect;
			query = [ServerQuery new];
			query.quadList = [NSMutableArray arrayWithObject:q];
			query.rect = rect;
			[queries addObject:query];
		}
	}

	// any items that didn't get grouped get put back on the list
	NSMutableArray * newQuadList = [NSMutableArray new];
	for ( NSInteger index = 0; index < queries.count; ++index ) {
		query = queries[index];
		if ( query.quadList.count == 1 ) {
			[newQuadList addObject:query.quadList.lastObject];
			[queries removeObjectAtIndex:index];
			--index;
		}
	}
	quadList = newQuadList;

	// sort by column
	quadList = [quadList sortedArrayUsingComparator:^NSComparisonResult(QuadBox * q1, QuadBox * q2) {
		double diff = q1.rect.origin.x - q2.rect.origin.x;
		if ( diff == 0 )
			diff = q1.rect.origin.y - q2.rect.origin.y;
		return diff < 0 ? NSOrderedAscending : diff > 0 ? NSOrderedDescending : NSOrderedSame;
	}];

	query = nil;
	for ( QuadBox * q in quadList ) {
		if ( query  &&  q.rect.origin.x == rect.origin.x  &&  q.rect.origin.y == rect.origin.y+rect.size.height  &&  q.rect.size.width == rect.size.width ) {
			[query.quadList	addObject:q];
			rect.size.height += q.rect.size.height;
			query.rect = rect;
			continue;
		}

		rect = q.rect;
		query = [ServerQuery new];
		query.quadList = [NSMutableArray arrayWithObject:q];
		query.rect = rect;
		[queries addObject:query];
	}

#if 0
	DLog(@"\nquery list:");
	for ( ServerQuery * q in queries )
		DLog(@"  %@", NSStringFromCGRect(CGRectFromOSMRect(q.rect)));
#endif

	return queries;
}

// http://wiki.openstreetmap.org/wiki/API_v0.6#Retrieving_map_data_by_bounding_box:_GET_.2Fapi.2F0.6.2Fmap
+ (void)osmDataForUrl:(NSString *)url quads:(ServerQuery *)quads completion:(void(^)(ServerQuery * quads,OsmMapData * data,NSError * error))completion
{
	[[DownloadThreadPool osmPool] streamForUrl:url callback:^(NSInputStream * stream,NSError * error2){

		if ( error2 || stream.streamError ) {

			dispatch_async(dispatch_get_main_queue(), ^{
				completion( quads, nil, stream.streamError ?: error2 );
			});

		} else {

			OsmMapData * mapData = [[OsmMapData alloc] init];
			NSError * error = nil;
			BOOL ok = [mapData parseXmlStream:stream error:&error];
			if ( !ok ) {
				if ( 0 /*agent.dataHeader.length*/ ) {
#if 0
					// probably some html-encoded error message from the server, or if cancelled then the leading portion of the xml download
					//NSString * s = [[NSString alloc] initWithBytes:agent.dataHeader.bytes length:agent.dataHeader.length encoding:NSUTF8StringEncoding];
					//error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : s }];
					error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : NSLocalizedString(@"Data not available",nil) }];
#endif
				} else if ( stream.streamError ) {
					error = stream.streamError;
				} else if ( error ) {
					// use the parser's reported error
				} else {
					error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : NSLocalizedString(@"Data not available",nil) }];
				}
			}
			if ( error ) {
				mapData = nil;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				completion( quads, mapData, error );
			});
		}

	}];
}
+ (void)osmDataForBox:(ServerQuery *)query completion:(void(^)(ServerQuery * query,OsmMapData * data,NSError * error))completion
{
	OSMRect box = query.rect;
	NSMutableString * url = [NSMutableString stringWithString:OSM_API_URL];
	[url appendFormat:@"api/0.6/map?bbox=%f,%f,%f,%f", box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height];

	[self osmDataForUrl:url quads:query completion:completion];
}

- (void)updateWithBox:(OSMRect)box progressDelegate:(NSObject<MapViewProgress> *)progress completion:(void(^)(BOOL partial,NSError * error))completion
{
	__block int activeRequests = 0;

	void(^mergePartialResults)(ServerQuery * query,OsmMapData * mapData,NSError * error) = ^(ServerQuery * query,OsmMapData * mapData,NSError * error){
		[progress progressDecrement];
		--activeRequests;
		if ( activeRequests == 0 ) {
		}
		if ( mapData )
			DLog(@"begin merge %ld objects", (long)mapData.nodeCount + mapData.wayCount + mapData.relationCount);
		[self merge:mapData fromDownload:YES quadList:query.quadList success:(mapData && error==nil)];
		completion( activeRequests > 0, error );
	};

	// get list of new quads to fetch
	NSArray * newQuads = [_region newQuadsForRect:box];

	if ( newQuads.count == 0 ) {
		++activeRequests;
		[progress progressIncrement];
		mergePartialResults( nil, nil, nil );
	} else {
		NSArray * queryList = [OsmMapData coalesceQuadQueries:newQuads];
		for ( ServerQuery * query in queryList ) {
			++activeRequests;
			[progress progressIncrement];
			[OsmMapData osmDataForBox:query completion:mergePartialResults];
		}
	}

	[progress progressAnimate];
}

-(void)cancelCurrentDownloads
{
	if ( [DownloadThreadPool.osmPool downloadsInProgress] > 0 ) {
		[DownloadThreadPool.osmPool cancelAllDownloads];
	}
}

#pragma mark Download parsing


- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName attributes:(NSDictionary *)attributeDict
{
	_parserCurrentElementText = nil;

	if ( [elementName isEqualToString:@"node"] ) {

		double lat	= [[attributeDict objectForKey:@"lat"] doubleValue];
		double lon	= [[attributeDict objectForKey:@"lon"] doubleValue];
		OsmNode * node = [OsmNode new];
		[node setLongitude:lon latitude:lat undo:nil];
		[node constructBaseAttributesFromXmlDict:attributeDict];

		[_nodes setObject:node forKey:@(node.ident)];
		[_parserStack addObject:node];
		
	} else if ( [elementName isEqualToString:@"way"] ) {

		OsmWay * way = [OsmWay new];
		[way constructBaseAttributesFromXmlDict:attributeDict];

		[_ways setObject:way forKey:@(way.ident)];
		[_parserStack addObject:way];

	} else if ( [elementName isEqualToString:@"tag"] ) {
		
		NSString * key		= [attributeDict objectForKey:@"k"];
		NSString * value	= [attributeDict objectForKey:@"v"];
		assert( key && value );
		OsmBaseObject * object = _parserStack.lastObject;
		[object constructTag:key value:value];
		[_parserStack addObject:@"tag"];
		
	} else if ( [elementName isEqualToString:@"nd"] ) {

		OsmWay * way = [_parserStack lastObject];
		NSString * ref = [attributeDict objectForKey:@"ref"];
		assert( ref );
		[way constructNode:@(ref.longLongValue)];
		[_parserStack addObject:@"nd"];

	} else if ( [elementName isEqualToString:@"relation"] ) {

		OsmRelation * relation = [OsmRelation new];
		[relation constructBaseAttributesFromXmlDict:attributeDict];

		[_relations setObject:relation forKey:@(relation.ident)];
		[_parserStack addObject:relation];

	} else if ( [elementName isEqualToString:@"member"] ) {

		NSString *	type = [attributeDict objectForKey:@"type"];
		NSNumber *	ref  = @([[attributeDict objectForKey:@"ref"] longLongValue]);
		NSString *	role = [attributeDict objectForKey:@"role"];

		OsmMember * member = [[OsmMember alloc] initWithType:type ref:ref.longLongValue role:role];

		OsmRelation * relation = [_parserStack lastObject];
		[relation constructMember:member];
		[_parserStack addObject:member];

	} else if ( [elementName isEqualToString:@"osm"] ) {

		// osm header
		NSString * version		= [attributeDict objectForKey:@"version"];
		if ( ![version isEqualToString:@"0.6"] ) {
			_parseError = [[NSError alloc] initWithDomain:@"Parser" code:102 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"OSM data must be version 0.6 (fetched '%@')",nil), version]}];
			[parser abortParsing];
		}
		[_parserStack addObject:@"osm"];

	} else if ( [elementName isEqualToString:@"bounds"] ) {
#if 0
		double minLat = [[attributeDict objectForKey:@"minlat"] doubleValue];
		double minLon = [[attributeDict objectForKey:@"minlon"] doubleValue];
		double maxLat = [[attributeDict objectForKey:@"maxlat"] doubleValue];
		double maxLon = [[attributeDict objectForKey:@"maxlon"] doubleValue];
#endif
		[_parserStack addObject:@"bounds"];

	} else if ( [elementName isEqualToString:@"note"] ) {

		// issued by Overpass API server
		[_parserStack addObject:elementName];
		
	} else if ( [elementName isEqualToString:@"meta"] ) {

		// issued by Overpass API server
		[_parserStack addObject:elementName];
		
	} else {

		DLog(@"OSM parser: Unknown tag '%@'", elementName);
		[_parserStack addObject:elementName];
#if 0
		_parseError = [[NSError alloc] initWithDomain:@"Parser" code:102 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"OSM parser: Unknown tag '%@'", elementName]}];
		[parser abortParsing];
#endif

	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	[_parserStack removeLastObject];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if ( _parserCurrentElementText == nil ) {
		_parserCurrentElementText = string;
	} else {
		_parserCurrentElementText = [_parserCurrentElementText stringByAppendingString:string];
	}
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
	DLog(@"Parse error: %@, line %ld, column %ld", parseError.localizedDescription, (long)parser.lineNumber, (long)parser.columnNumber );
	_parseError = parseError;
}

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
	assert( _parserStack.count == 0 || _parseError );
	_parserCurrentElementText = nil;
	_parserStack = nil;
}


-(BOOL)parseXmlStream:(NSInputStream *)stream error:(NSError **)error
{
	NSXMLParser * parser = [[NSXMLParser alloc] initWithStream:stream];
	parser.delegate = self;
	_parseError = nil;

	BOOL ok = [parser parse] && _parseError == nil;

	if ( !ok ) {
		if ( error ) {
			*error = _parseError;
		}
		[stream close];	// close stream so the writer knows if we won't be reading any more
	}

	return ok;
}


- (void)merge:(OsmMapData *)newData fromDownload:(BOOL)downloaded quadList:(NSArray *)quadList success:(BOOL)success
{
	if ( newData ) {

		NSMutableArray<OsmNode *> * newNodes = [NSMutableArray new];
		NSMutableArray<OsmWay *> * newWays = [NSMutableArray new];
		NSMutableArray<OsmRelation *> * newRelations = [NSMutableArray new];

		[newData->_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmNode * node,BOOL * stop){
			OsmNode * current = [_nodes objectForKey:key];
			if ( current == nil ) {
				[_nodes setObject:node forKey:key];
				[_spatial addMember:node undo:nil];
				[newNodes addObject:node];
			} else if ( current.version < node.version ) {
				// already exists, so do an in-place update
				OSMRect bbox = current.boundingBox;
				[current serverUpdateInPlace:node];
				[_spatial updateMember:current fromBox:bbox undo:nil];
				[newNodes addObject:current];
			}
		}];
		[newData->_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmWay * way,BOOL * stop){
			OsmWay * current = [_ways objectForKey:key];
			if ( current == nil ) {
				[_ways setObject:way forKey:key];
				[way resolveToMapData:self];
				[_spatial addMember:way undo:nil];
				[newWays addObject:way];
			} else if ( current.version < way.version ) {
				OSMRect bbox = current.boundingBox;
				[current serverUpdateInPlace:way];
				[current resolveToMapData:self];
				[_spatial updateMember:current fromBox:bbox undo:nil];
				[newWays addObject:current];
			}
		}];
		[newData->_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmRelation * relation,BOOL * stop){

			OsmRelation * current = [_relations objectForKey:key];
			if ( [_relations objectForKey:key] == nil ) {
				[_relations setObject:relation forKey:key];
				[_spatial addMember:relation undo:nil];
				[newRelations addObject:relation];
			} else if ( current.version < relation.version ) {
				OSMRect bbox = current.boundingBox;
				[current serverUpdateInPlace:relation];
				[_spatial updateMember:current fromBox:bbox undo:nil];
				[newRelations addObject:current];
			}
		}];

		// all relations, including old ones, need to be resolved against new objects
		__block BOOL didChange = YES;
		while ( didChange ) {
			didChange = NO;
			[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmRelation * relation,BOOL * stop){
				OSMRect bbox = relation.boundingBox;
				didChange |= [relation resolveToMapData:self];
				[_spatial updateMember:relation fromBox:bbox undo:nil];
			}];
		}

		[newData->_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmNode * node,BOOL * stop){
			[node setConstructed];
		}];
		[newData->_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmWay * way,BOOL * stop){
			[way setConstructed];
		}];
		[newData->_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmRelation * relation,BOOL * stop){
			[relation setConstructed];
		}];

		// store new nodes in database
		if ( downloaded ) {
			[self sqlSaveNodes:newNodes
                      saveWays:newWays
                 saveRelations:newRelations
                   deleteNodes:nil
                    deleteWays:nil
               deleteRelations:nil
                      isUpdate:NO];

			// purge old data
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[AppDelegate.shared.mapView discardStaleData];
			});
		}
	}

	for ( QuadBox * q in quadList ) {
		[_region makeWhole:q success:success];
	}
}

#pragma mark Upload

-(void) updateObjectDictionary:(NSMutableDictionary *)dictionary oldId:(OsmIdentifier)oldId  newId:(OsmIdentifier)newId version:(NSInteger)newVersion changeset:(OsmIdentifier)changeset sqlUpdate:(NSMutableDictionary *)sqlUpdate
{
	OsmBaseObject * object = [dictionary objectForKey:@(oldId)];
	if ( object == nil ) {
		// this can happen if they edited the upload XML and included an object that is not downloaded.
		return;
	}
	assert( object.ident == oldId );
	if ( newVersion == 0 && newId == 0 ) {
		// Delete object for real
		// When a way is deleted we delete the nodes also, but they aren't marked as deleted in the graph.
		// If nodes are still in use by another way the newId and newVersion will be set and we won't take this path.
		assert( newId == 0 && newVersion == 0 );
		if ( object.isNode ) {
			[_nodes removeObjectForKey:@(object.ident)];
		} else if ( object.isWay ) {
			[_ways removeObjectForKey:@(object.ident)];
		} else if ( object.isRelation ) {
			[_relations removeObjectForKey:@(object.ident)];
		} else {
			assert(NO);
		}
		[sqlUpdate setObject:@(NO) forKey:object];	// mark for deletion
		return;
	}

	assert( newVersion > 0 );
	[object serverUpdateVersion:newVersion];
	[object serverUpdateChangeset:changeset];
	[sqlUpdate setObject:@(YES) forKey:object];	// mark for insertion

	if ( oldId != newId ) {
		// replace placeholder object with new server provided identity
		assert( oldId < 0 && newId > 0 );
		[dictionary removeObjectForKey:@(object.ident)];
		[object serverUpdateIdent:newId];
		[dictionary setObject:object forKey:@(object.ident)];
	} else {
		assert( oldId > 0 );
	}
	[object resetModifyCount:_undoManager];
}


+(NSString *)encodeBase64:(NSString *)plainText
{
	NSData * data = [plainText dataUsingEncoding:NSUTF8StringEncoding];
	NSString * output = [data base64EncodedStringWithOptions:0];
	return output;
}


- (NSData *)gzippedData:(NSData *)input
{
	const int CHUNK = 65536;
	z_stream stream = { 0 };
    stream.avail_in = (uint)input.length;
    stream.next_in = (unsigned char *)input.bytes;
    if ( deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY) != Z_OK )
		return nil;
	NSMutableData *output = [NSMutableData dataWithLength:CHUNK];
	while ( stream.avail_out == 0 ) {
		if ( stream.total_out >= output.length ) {
			output.length += CHUNK;
		}
		stream.next_out = (uint8_t *)output.mutableBytes + stream.total_out;
		stream.avail_out = (uInt)(output.length - stream.total_out);
		deflate(&stream, Z_FINISH);
	}
	deflateEnd(&stream);
	output.length = stream.total_out;

    return output;
}


-(void)putRequest:(NSString *)url method:(NSString *)method xml:(NSXMLDocument *)xml completion:(void(^)(NSData * data,NSString * error))completion
{
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	[request setHTTPMethod:method];
	if ( xml ) {
		NSData * data = [xml XMLDataWithOptions:0];
		data = [self gzippedData:data];
		[request setHTTPBody:data];
		[request setValue:@"text/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
		[request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
	}
	[request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
	// request.timeoutInterval = 15*60;

	NSString * auth = [NSString stringWithFormat:@"%@:%@", _credentialsUserName, _credentialsPassword];
	auth = [OsmMapData encodeBase64:auth];
	auth = [NSString stringWithFormat:@"Basic %@", auth];
	[request setValue:auth forHTTPHeaderField:@"Authorization"];

	NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NSHTTPURLResponse * httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (id)response : nil;
			if ( data && error == nil && httpResponse && httpResponse.statusCode >= 200 && httpResponse.statusCode <= 299  ) {
				completion(data,nil);
			} else {
				NSString * errorMessage;
				if ( data.length > 0 ) {
					errorMessage = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
				} else {
					errorMessage = error ? error.localizedDescription : httpResponse ? [NSString stringWithFormat:@"HTTP Error %ld", (long)httpResponse.statusCode] : @"Unknown error";
				}
				errorMessage = [errorMessage stringByAppendingFormat:@"\n\n%@ %@",method,url];
				completion(nil,errorMessage);
			}
		});
	}];
	[task resume];
}


+ (NSXMLDocument *)createXmlWithType:(NSString *)type tags:(NSDictionary *)dictionary
{
#if TARGET_OS_IPHONE
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:@"<osm></osm>" options:0 error:NULL];
	NSXMLElement * root = [doc rootElement];
#else
	NSXMLElement * root = (NSXMLElement *)[NSXMLNode elementWithName:@"osm"];
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithRootElement:root];
	[doc setCharacterEncoding:@"UTF-8"];
#endif
	NSXMLElement * typeElement = [NSXMLNode elementWithName:type];
	[root addChild:typeElement];
	[dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
		NSXMLElement * tag = [NSXMLNode elementWithName:@"tag"];
		[typeElement addChild:tag];
		NSXMLNode * attrKey   = [NSXMLNode attributeWithName:@"k" stringValue:key];
		NSXMLNode * attrValue = [NSXMLNode attributeWithName:@"v" stringValue:value];
		[tag addAttribute:attrKey];
		[tag addAttribute:attrValue];
	}];
	return doc;
}


+(NSXMLElement *)elementForObject:(OsmBaseObject *)object
{
	NSString * type =	object.isNode		? @"node" :
						object.isWay		? @"way" :
						object.isRelation	? @"relation" :
						nil;
	assert(type);

	NSXMLElement * element = [NSXMLNode elementWithName:type];
	[element addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:@(object.ident).stringValue]];
	[element addAttribute:[NSXMLNode attributeWithName:@"timestamp" stringValue:object.timestamp]];
	[element addAttribute:[NSXMLNode attributeWithName:@"version" stringValue:@(object.version).stringValue]];
	return element;
}

+(void)addTagsForObject:(OsmBaseObject *)object element:(NSXMLElement *)element
{
	[object.tags enumerateKeysAndObjectsUsingBlock:^(NSString * tag, NSString * value, BOOL *stop) {
		NSXMLElement * tagElement = [NSXMLElement elementWithName:@"tag"];
		[tagElement addAttribute:[NSXMLNode attributeWithName:@"k" stringValue:tag]];
		[tagElement addAttribute:[NSXMLNode attributeWithName:@"v" stringValue:value]];
		[element addChild:tagElement];
	}];
}

- (NSXMLDocument *)createXml
{
	NSXMLElement * createNodeElement	= [NSXMLNode elementWithName:@"create"];
	NSXMLElement * modifyNodeElement	= [NSXMLNode elementWithName:@"modify"];
	NSXMLElement * deleteNodeElement	= [NSXMLNode elementWithName:@"delete"];
	NSXMLElement * createWayElement		= [NSXMLNode elementWithName:@"create"];
	NSXMLElement * modifyWayElement		= [NSXMLNode elementWithName:@"modify"];
	NSXMLElement * deleteWayElement		= [NSXMLNode elementWithName:@"delete"];
	NSXMLElement * createRelationElement = [NSXMLNode elementWithName:@"create"];
	NSXMLElement * modifyRelationElement = [NSXMLNode elementWithName:@"modify"];
	NSXMLElement * deleteRelationElement = [NSXMLNode elementWithName:@"delete"];

	[deleteNodeElement		addAttribute:[NSXMLNode attributeWithName:@"if-unused" stringValue:@"yes"]];
	[deleteWayElement		addAttribute:[NSXMLNode attributeWithName:@"if-unused" stringValue:@"yes"]];
	[deleteRelationElement	addAttribute:[NSXMLNode attributeWithName:@"if-unused" stringValue:@"yes"]];

	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmNode * node, BOOL *stop) {
		if ( node.deleted && node.ident > 0 ) {
			// deleted
			NSXMLElement * element = [OsmMapData elementForObject:node];
			[deleteNodeElement addChild:element];
		} else if ( node.isModified && !node.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:node];
			[element addAttribute:[NSXMLNode attributeWithName:@"lat" stringValue:@(node.lat).stringValue]];
			[element addAttribute:[NSXMLNode attributeWithName:@"lon" stringValue:@(node.lon).stringValue]];
			[OsmMapData addTagsForObject:node element:element];
			if ( node.ident < 0 ) {
				[createNodeElement addChild:element];
			} else {
				[modifyNodeElement addChild:element];
			}
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
		if ( way.deleted && way.ident > 0 ) {
			NSXMLElement * element = [OsmMapData elementForObject:way];
			[deleteWayElement addChild:element];
			for ( OsmNode * node in way.nodes ) {
				NSXMLElement * nodeElement = [OsmMapData elementForObject:node];
				[deleteWayElement addChild:nodeElement];
			}
		} else if ( way.isModified && !way.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:way];
			for ( OsmNode * node in way.nodes ) {
				NSXMLElement * refElement = [NSXMLElement elementWithName:@"nd"];
				[refElement addAttribute:[NSXMLNode attributeWithName:@"ref" stringValue:@(node.ident).stringValue]];
				[element addChild:refElement];
			}
			[OsmMapData addTagsForObject:way element:element];
			if ( way.ident < 0 ) {
				[createWayElement addChild:element];
			} else {
				[modifyWayElement addChild:element];
			}
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		if ( relation.deleted && relation.ident > 0 ) {
			NSXMLElement * element = [OsmMapData elementForObject:relation];
			[deleteRelationElement addChild:element];
		} else if ( relation.isModified && !relation.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:relation];
			for ( OsmMember * member in relation.members ) {
				NSXMLElement * memberElement = [NSXMLElement elementWithName:@"member"];
				[memberElement addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:member.type]];
				[memberElement addAttribute:[NSXMLNode attributeWithName:@"ref" stringValue:@(member.ref).stringValue]];
				[memberElement addAttribute:[NSXMLNode attributeWithName:@"role" stringValue:member.role]];
				[element addChild:memberElement];
			}
			[OsmMapData addTagsForObject:relation element:element];
			if ( relation.ident < 0 ) {
				[createRelationElement addChild:element];
			} else {
				[modifyRelationElement addChild:element];
			}
		}
	}];


#if TARGET_OS_IPHONE
	AppDelegate * appDelegate = AppDelegate.shared;
	NSString * text = [NSString stringWithFormat:@"<?xml version=\"1.0\"?>"
												@"<osmChange generator=\"%@ %@\" version=\"0.6\"></osmChange>",
												appDelegate.appName, appDelegate.appVersion];
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:NULL];
	NSXMLElement * root = [doc rootElement];
#else
	AppDelegate * appDelegate = (id)[[NSApplication sharedApplication] delegate];
	NSXMLElement * root = (NSXMLElement *)[NSXMLNode elementWithName:@"osmChange"];
	[root addAttribute:[NSXMLNode attributeWithName:@"generator" stringValue:appDelegate.appName]];
	[root addAttribute:[NSXMLNode attributeWithName:@"version"   stringValue:@"0.6"]];
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithRootElement:root];
	[doc setCharacterEncoding:@"UTF-8"];
#endif

	if ( createNodeElement.childCount > 0 )		[root addChild:createNodeElement];
	if ( createWayElement.childCount > 0 )		[root addChild:createWayElement];
	if ( createRelationElement.childCount > 0 )	[root addChild:createRelationElement];

	if ( modifyNodeElement.childCount > 0 )		[root addChild:modifyNodeElement];
	if ( modifyWayElement.childCount > 0 )		[root addChild:modifyWayElement];
	if ( modifyRelationElement.childCount > 0 )	[root addChild:modifyRelationElement];

	if ( deleteRelationElement.childCount > 0 )	[root addChild:deleteRelationElement];
	if ( deleteWayElement.childCount > 0 )		[root addChild:deleteWayElement];
	if ( deleteNodeElement.childCount > 0 )		[root addChild:deleteNodeElement];

	if ( root.childCount == 0 )
		return nil;	// nothing to add

	return doc;
}


- (NSArray *)createChangeset
{
	NSMutableArray * createNode		= [NSMutableArray new];
	NSMutableArray * modifyNode		= [NSMutableArray new];
	NSMutableArray * deleteNode		= [NSMutableArray new];
	NSMutableArray * createWay		= [NSMutableArray new];
	NSMutableArray * modifyWay		= [NSMutableArray new];
	NSMutableArray * deleteWay		= [NSMutableArray new];
	NSMutableArray * createRelation	= [NSMutableArray new];
	NSMutableArray * modifyRelation	= [NSMutableArray new];
	NSMutableArray * deleteRelation	= [NSMutableArray new];

	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmNode * node, BOOL *stop) {
		if ( node.deleted && node.ident > 0 ) {
			// deleted
			[deleteNode addObject:node];
		} else if ( node.isModified && !node.deleted ) {
			// added/modified
			if ( node.ident < 0 ) {
				[createNode addObject:node];
			} else {
				[modifyNode addObject:node];
			}
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
		if ( way.deleted && way.ident > 0 ) {
			[deleteWay addObject:way];
			for ( OsmNode * node in way.nodes ) {
				[deleteNode addObject:node];
			}
		} else if ( way.isModified && !way.deleted ) {
			// added/modified
			if ( way.ident < 0 ) {
				[createWay addObject:way];
			} else {
				[modifyWay addObject:way];
			}
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		if ( relation.deleted && relation.ident > 0 ) {
			[deleteRelation addObject:relation];
		} else if ( relation.isModified && !relation.deleted ) {
			// added/modified
			if ( relation.ident < 0 ) {
				[createRelation addObject:relation];
			} else {
				[modifyRelation addObject:relation];
			}
		}
	}];

	NSArray * list = @[
		@[	@"createNode", createNode ],
		@[ 	@"modifyNode", modifyNode ],
		@[ 	@"deleteNode", deleteNode ],
		@[ 	@"createWay", createWay ],
		@[ 	@"modifyWay", modifyWay ],
		@[ 	@"deleteWay", deleteWay ],
		@[ 	@"createRelation", createRelation ],
		@[ 	@"modifyRelation", modifyRelation ],
		@[ 	@"deleteRelation", deleteRelation ],
	];
	list = [list filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * object, NSDictionary *bindings) {
		NSArray * a = object.lastObject;
		return a.count > 0;
	}]];
	return list ?: nil;
}


+ (void)updateChangesetXml:(NSXMLDocument *)xmlDoc withChangesetID:(NSString *)changesetID
{
	NSXMLElement * osmChange = [xmlDoc rootElement];
	for ( NSXMLElement * changeType in osmChange.children ) {	// create/modify/delete
		for ( NSXMLElement * osmObject in changeType.children ) {	// node/way/relation
			if ( [osmObject isKindOfClass:[NSXMLElement class]] ) {
				[osmObject addAttribute:[NSXMLNode attributeWithName:@"changeset" stringValue:changesetID]];
			}
		}
	}
}



- (void)uploadChangesetXML:(NSXMLDocument *)xmlChanges changesetID:(NSString *)changesetID retries:(NSInteger)retries completion:(void(^)(NSString * errorMessage))completion
{
	NSString * url2 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/changeset/%@/upload", changesetID];
	[self putRequest:url2 method:@"POST" xml:xmlChanges completion:^(NSData *postData,NSString * postErrorMessage) {
		NSString * response = [[NSString alloc] initWithBytes:postData.bytes length:postData.length encoding:NSUTF8StringEncoding];

		if ( retries > 0 && [response hasPrefix:@"Version mismatch"] ) {

			// update the bad element and retry
			DLog( @"Upload error: %@", response);
			uint32_t localVersion = 0, serverVersion = 0;
			OsmIdentifier objId = 0;
			char type[256] = "";
			if ( sscanf( response.UTF8String, "Version mismatch: Provided %d, server had: %d of %[a-zA-Z] %lld", &localVersion, &serverVersion, type, &objId ) == 4 ) {
				type[0] = _tolower( type[0] );
				NSString * url3 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/%s/%lld", type, objId];
				if ( strcmp(type,"way")==0 || strcmp(type,"relation")==0 ) {
					url3 = [url3 stringByAppendingString:@"/full"];
				}

				[OsmMapData osmDataForUrl:url3 quads:nil completion:^(ServerQuery *quads, OsmMapData * mapData, NSError *error) {
					[self merge:mapData fromDownload:YES quadList:nil success:YES];
					// try again:
					[self uploadChangeset:changesetID retries:retries-1 completion:completion];
				}];
				return;
			}
		}

		if ( ![response hasPrefix:@"<?xml"] ) {
			completion( postErrorMessage ?: response );
			return;
		}

		NSError * error = nil;
		NSXMLDocument * diffDoc = [[NSXMLDocument alloc] initWithData:postData options:0 error:&error];
		if ( error ) {
			completion( error.localizedDescription );
			return;
		}

		if ( ![diffDoc.rootElement.name isEqualToString:@"diffResult"] ) {
			completion( @"Upload failed: invalid server respsonse" );
			return;
		}

		NSMutableDictionary * sqlUpdate = [NSMutableDictionary new];
		for ( NSXMLElement * element in diffDoc.rootElement.children ) {
			NSString * name			= element.name;
			NSString * oldId		= [element attributeForName:@"old_id"].stringValue;
			NSString * newId		= [element attributeForName:@"new_id"].stringValue;
			NSString * newVersion	= [element attributeForName:@"new_version"].stringValue;

			if ( [name isEqualToString:@"node"] ) {
				[self updateObjectDictionary:_nodes oldId:oldId.longLongValue newId:newId.longLongValue version:newVersion.integerValue changeset:changesetID.longLongValue sqlUpdate:sqlUpdate];
			} else if ( [name isEqualToString:@"way"] ) {
				[self updateObjectDictionary:_ways oldId:oldId.longLongValue newId:newId.longLongValue version:newVersion.integerValue changeset:changesetID.longLongValue sqlUpdate:sqlUpdate];
			} else if ( [name isEqualToString:@"relation"] ) {
				[self updateObjectDictionary:_relations oldId:oldId.longLongValue newId:newId.longLongValue version:newVersion.integerValue changeset:changesetID.longLongValue sqlUpdate:sqlUpdate];
			} else {
				DLog( @"Bad upload diff document" );
			}
		}

		[self updateSql:sqlUpdate];

		NSString * url3 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/changeset/%@/close", changesetID];
		[self putRequest:url3 method:@"PUT" xml:nil completion:^(NSData *data,NSString * errorMessage) {
			if ( errorMessage )
				errorMessage = [errorMessage stringByAppendingString:@" (ignored, changes already committed)"];
			completion(errorMessage);
			// DLog(@"changeset closed");
		}];

		// reset undo stack after upload so user can't accidently undo a commit (wouldn't work anyhow because we don't undo version numbers on objects)
		[_undoManager removeAllActions];
	}];
}

// upload xml generated by mapData
- (void)uploadChangeset:(NSString *)changesetID retries:(NSInteger)retries completion:(void(^)(NSString * errorMessage))completion
{
	NSXMLDocument * xmlChanges = [self createXml];
	[OsmMapData updateChangesetXml:xmlChanges withChangesetID:changesetID];

	[self uploadChangesetXML:xmlChanges changesetID:changesetID retries:retries completion:completion];
}

// create a new changeset to upload to
-(void)createChangesetWithComment:(NSString *)comment source:(NSString *)source imagery:(NSString *)imagery completion:(void(^)(NSString * changesetID, NSString * errorMessage))completion
{
	AppDelegate * appDelegate = AppDelegate.shared;
	NSString * creator = [NSString stringWithFormat:@"%@ %@", appDelegate.appName, appDelegate.appVersion];
	NSMutableDictionary * tags = [NSMutableDictionary dictionaryWithDictionary:@{ @"created_by" : creator }];
	if ( comment.length )
		tags[@"comment"] = comment;
	if ( imagery.length )
		tags[@"imagery_used"] = imagery;
	if ( source.length )
		tags[@"source"] = source;
	NSXMLDocument * xmlCreate = [OsmMapData createXmlWithType:@"changeset" tags:tags];
	NSString * url = [OSM_API_URL stringByAppendingString:@"api/0.6/changeset/create"];
	[self putRequest:url method:@"PUT" xml:xmlCreate completion:^(NSData * putData,NSString * putErrorMessage){
        if (!putData || putErrorMessage) {
            completion(nil, putErrorMessage);
            return;
        }
        
        NSString *responseString = [[NSString alloc] initWithBytes:putData.bytes length:putData.length encoding:NSUTF8StringEncoding];
        
        NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([responseString rangeOfCharacterFromSet:notDigits].location == NSNotFound) {
            // The response string only contains of the digits 0 through 9.
            // Assume that the request was successful and that the server responded with a changeset ID.
            completion(responseString, nil);
        } else {
            // The response did not only contain digits; treat this as an error.
            completion(nil, responseString);
        }
	}];
}

// upload xml generated by mapData
- (void)uploadChangesetWithComment:(NSString *)comment source:(NSString *)source imagery:(NSString *)imagery completion:(void(^)(NSString * errorMessage))completion
{
	[self createChangesetWithComment:comment source:source imagery:imagery completion:^(NSString *changesetID, NSString *errorMessage) {
		if ( changesetID ) {
			[self uploadChangeset:changesetID retries:20 completion:completion];
		} else {
			completion(errorMessage);
		}
	}];
}

// upload xml edited by user
- (void)uploadChangesetXml:(NSXMLDocument *)xmlChanges comment:(NSString *)comment source:(NSString *)source imagery:(NSString *)imagery completion:(void(^)(NSString * error))completion
{
	[self createChangesetWithComment:comment source:source imagery:imagery completion:^(NSString *changesetID, NSString *errorMessage) {
		if ( changesetID ) {
			[OsmMapData updateChangesetXml:xmlChanges withChangesetID:changesetID];
			[self uploadChangesetXML:xmlChanges changesetID:changesetID retries:0 completion:completion];
		} else {
			completion(errorMessage);
		}
	}];
}


- (void)verifyUserCredentialsWithCompletion:(void(^)(NSString * errorMessage))completion
{
	AppDelegate * appDelegate = AppDelegate.shared;

	self.credentialsUserName = appDelegate.userName;
	self.credentialsPassword = appDelegate.userPassword;

	NSString * url = [OSM_API_URL stringByAppendingString:@"api/0.6/user/details"];
	[self putRequest:url method:@"GET" xml:nil completion:^(NSData * data,NSString * errorMessage){
		BOOL ok = NO;
		if ( data ) {
			NSString * text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:NULL];
			NSXMLElement * root = [doc rootElement];
			NSArray * users = [root elementsForName:@"user"];
			if ( users.count ) {
				NSXMLElement * user = [users lastObject];
				NSString * displayName = [user attributeForName:@"display_name"].stringValue;
				if ( [displayName compare:_credentialsUserName options:NSCaseInsensitiveSearch] == NSOrderedSame ) {
					// update display name to have proper case:
					self.credentialsUserName = displayName;
					appDelegate.userName = displayName;
					ok = YES;
				}
			}
		}
		if ( ok ) {
			completion(nil);
		} else {
			if ( errorMessage == nil )
				errorMessage = NSLocalizedString(@"Not found",@"User credentials not found");
			completion(errorMessage);
		}
	}];
}



#pragma mark Pretty print changeset


-(void)updateString:(NSMutableAttributedString *)string withTag:(NSXMLElement *)tag
{
#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleCallout];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
    
    UIColor *foregroundColor = UIColor.blackColor;
    if (@available(iOS 13.0, *)) {
        foregroundColor = UIColor.labelColor;
    }
    
	NSString * text = [NSString stringWithFormat:@"\t\t%@ = %@\n",
					   [tag attributeForName:@"k"].stringValue,
					   [tag attributeForName:@"v"].stringValue];
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];
}
-(void)updateString:(NSMutableAttributedString *)string withMember:(NSXMLElement *)tag
{
#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleCallout];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
    
    UIColor *foregroundColor = UIColor.blackColor;
    if (@available(iOS 13.0, *)) {
        foregroundColor = UIColor.labelColor;
    }
    
	NSString * text = [NSString stringWithFormat:@"\t\t%@ %@: \"%@\"\n",
					   [tag attributeForName:@"type"].stringValue,
					   [tag attributeForName:@"ref"].stringValue,
					   [tag attributeForName:@"role"].stringValue];
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];
}

-(void)updateString:(NSMutableAttributedString *)string withNode:(NSXMLElement *)node
{
#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
    
    UIColor *foregroundColor = UIColor.blackColor;
    if (@available(iOS 13.0, *)) {
        foregroundColor = UIColor.labelColor;
    }

	NSString * nodeName = [node attributeForName:@"id"].stringValue;
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tNode " attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:nodeName
																   attributes:@{ NSFontAttributeName : font,
																				 NSLinkAttributeName : [@"n" stringByAppendingString:nodeName] }]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{ NSFontAttributeName : font }]];
	for ( NSXMLElement * tag in node.children ) {
		if ( [tag.name isEqualToString:@"tag"] ) {
			[self updateString:string withTag:tag];
		} else {
			assert(NO);
		}
	}
}
-(void)updateString:(NSMutableAttributedString *)string withWay:(NSXMLElement *)way
{
	int nodeCount = 0;
	for ( NSXMLElement * tag in way.children ) {
		if ( [tag.name isEqualToString:@"nd"] ) {
			nodeCount++;
		}
	}

#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
    
    UIColor *foregroundColor = UIColor.blackColor;
    if (@available(iOS 13.0, *)) {
        foregroundColor = UIColor.labelColor;
    }

	NSString * wayName = [way attributeForName:@"id"].stringValue;
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"\tWay ",nil) attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:wayName
																   attributes:@{ NSFontAttributeName : font,
																				 NSLinkAttributeName : [@"w" stringByAppendingString:wayName] }]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@" (%d nodes)\n",nil),nodeCount]
                                                                   attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];

	for ( NSXMLElement * tag in way.children ) {
		if ( [tag.name isEqualToString:@"tag"] ) {
			[self updateString:string withTag:(NSXMLElement *)tag];
		} else if ( [tag.name isEqualToString:@"nd"] ) {
			// skip
		} else {
			assert(NO);
		}
	}
}
-(void)updateString:(NSMutableAttributedString *)string withRelation:(NSXMLElement *)relation
{
	int memberCount = 0;
	for ( NSXMLElement * tag in relation.children ) {
		if ( [tag.name isEqualToString:@"member"] ) {
			memberCount++;
		}
	}

#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
    
    UIColor *foregroundColor = UIColor.blackColor;
    if (@available(iOS 13.0, *)) {
        foregroundColor = UIColor.labelColor;
    }

	NSString * relationName = [relation attributeForName:@"id"].stringValue;
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:NSLocalizedString(@"\tRelation ",nil) attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:relationName
																   attributes:@{ NSFontAttributeName : font,
																				 NSLinkAttributeName : [@"r" stringByAppendingString:relationName] }]];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@" (%d members)\n",nil),memberCount]
                                                                   attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];

	for ( NSXMLElement * tag in relation.children ) {
		if ( [tag.name isEqualToString:@"tag"] ) {
			[self updateString:string withTag:(NSXMLElement *)tag];
		} else if ( [tag.name isEqualToString:@"member"] ) {
			[self updateString:string withMember:(NSXMLElement *)tag];
		} else {
			assert(NO);
		}
	}
}
-(void)updateString:(NSMutableAttributedString *)string withHeader:(NSString *)header objects:(NSArray *)objects
{
	if ( objects.count == 0 )
		return;
    
    UIColor *foregroundColor = UIColor.blackColor;
    if (@available(iOS 13.0, *)) {
        foregroundColor = UIColor.labelColor;
    }

#if TARGET_OS_IPHONE
	UIFont * font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
#else
	NSFont * font = [NSFont labelFontOfSize:12];
#endif
    [string appendAttributedString:[[NSAttributedString alloc] initWithString:header attributes:@{ NSFontAttributeName : font, NSForegroundColorAttributeName: foregroundColor }]];
	for ( NSXMLElement * object in objects ) {
		if ( [object.name isEqualToString:@"node"] ) {
			[self updateString:string withNode:object];
		} else if ( [object.name isEqualToString:@"way"] ) {
			[self updateString:string withWay:object];
		} else if ( [object.name isEqualToString:@"relation"] ) {
			[self updateString:string withRelation:object];
		} else {
			assert(NO);
		}
	}
}

-(NSAttributedString *)changesetAsAttributedString
{
	NSXMLDocument * doc = [self createXml];
	if ( doc == nil )
		return nil;
	NSMutableAttributedString * string = [NSMutableAttributedString new];
	NSXMLElement * root = [doc rootElement];
	
	NSArray * deletes = [root elementsForName:@"delete"];
	NSArray * creates = [root elementsForName:@"create"];
	NSArray * modifys = [root elementsForName:@"modify"];
	for ( NSXMLElement * delete in deletes ) {
		[self updateString:string withHeader:NSLocalizedString(@"Delete\n",nil) objects:delete.children];
	}
	for ( NSXMLElement * create in creates ) {
		[self updateString:string withHeader:NSLocalizedString(@"Create\n",nil) objects:create.children];
	}
	for ( NSXMLElement * modify in modifys ) {
		[self updateString:string withHeader:NSLocalizedString(@"Modify\n",nil) objects:modify.children];
	}
	return string;
}

- (NSString *)changesetAsXml
{
	NSXMLDocument * xml = [self createXml];
	if ( xml == nil )
		return nil;
	return [xml XMLStringWithOptions:NSXMLNodePrettyPrint];
}

#pragma mark Save/Restore


- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_nodes			forKey:@"nodes"];
	[coder encodeObject:_ways			forKey:@"ways"];
	[coder encodeObject:_relations		forKey:@"relations"];
	[coder encodeObject:_region			forKey:@"region"];
	[coder encodeObject:_spatial		forKey:@"spatial"];
	[coder encodeObject:_undoManager	forKey:@"undoManager"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [self init];
	if ( self ) {

		@try {
			_nodes			= [coder decodeObjectForKey:@"nodes"];
			_ways			= [coder decodeObjectForKey:@"ways"];
			_relations		= [coder decodeObjectForKey:@"relations"];
			_region			= [coder decodeObjectForKey:@"region"];
			_spatial		= [coder decodeObjectForKey:@"spatial"];
			_undoManager	= [coder decodeObjectForKey:@"undoManager"];

			[self initCommon];

			if ( _nodes == nil || _ways == nil || _relations == nil || _undoManager == nil || _spatial == nil ) {
				self = nil;
			} else {
				if ( _region == nil ) {
					// This path taken if we came from a quick-save
					_region	= [QuadMap new];

					// didn't save spatial, so add everything back into it
					[self enumerateObjectsUsingBlock:^(OsmBaseObject *object) {
						[_spatial addMember:object undo:nil];
					}];
				}
			}
		} @catch ( NSException * exception ) {
			self = nil;
		}
	}
	return self;
}

-(void)copyNode:(OsmNode *)node
{
	[_nodes setObject:node forKey:@(node.ident)];
}
-(void)copyWay:(OsmWay *)way
{
	[_ways setObject:way forKey:@(way.ident)];
	for ( OsmNode * node in way.nodes ) {
		[self copyNode:node];
	}
}
-(void)copyRelation:(OsmRelation *)relation
{
	[_relations setObject:relation forKey:@(relation.ident)];
	// don't copy member objects
}
-(OsmMapData *)modifiedObjects
{
	// get modified nodes and ways
	OsmMapData * modified = [[OsmMapData alloc] initWithUserDefaults:self.userDefaults];

	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmNode * object, BOOL *stop) {
		if ( object.deleted ? object.ident > 0 : object.isModified ) {
			[modified copyNode:object];
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmWay * object, BOOL *stop) {
		if ( object.deleted ? object.ident > 0 : object.isModified ) {
			[modified copyWay:object];
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmRelation * object, BOOL *stop) {
		if ( object.deleted ? object.ident > 0 : object.isModified ) {
			[modified copyRelation:object];
		}
	}];

	NSSet * undoObjects = [_undoManager objectRefs];
	for ( id object in undoObjects ) {
		if ( [object isKindOfClass:[OsmBaseObject class]] ) {
			OsmBaseObject * obj = object;
			if ( obj.isNode ) {
				[modified copyNode:object];
			} else if ( obj.isWay ) {
				[modified copyWay:object];
			} else if ( obj.isRelation ) {
				[modified copyRelation:object];
			} else {
				assert(NO);
			}
		}
	}
	modified->_undoManager = _undoManager;
	
	return modified;
}


-(void)purgeExceptUndo
{
	[_nodes removeAllObjects];
	[_ways removeAllObjects];
	[_relations removeAllObjects];
	[_spatial.rootQuad reset];
	_region  = [QuadMap new];

	dispatch_async(Database.dispatchQueue, ^{
		[Database deleteDatabaseWithName:nil];
	});
}

-(void)purgeHard
{
	[self purgeExceptUndo];
	[_undoManager removeAllActions];
}

-(void)purgeSoft
{
	// get a list of all dirty objects
	NSMutableSet * dirty = [NSMutableSet new];
	[_nodes enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * object, BOOL *stop) {
		if ( object.isModified ) {
			[dirty addObject:object];
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * object, BOOL *stop) {
		if ( object.isModified ) {
			[dirty addObject:object];
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * object, BOOL *stop) {
		if ( object.isModified ) {
			[dirty addObject:object];
		}
	}];

	// get objects referenced by undo manager
	NSSet * undoRefs = [_undoManager objectRefs];
	[dirty unionSet:undoRefs];

	// add nodes in ways to dirty set, because we must preserve them to maintain consistency
	for ( OsmWay * way in dirty.allObjects ) {
		if ( [way isKindOfClass:[OsmWay class]] ) {
			[dirty addObjectsFromArray:way.nodes];
		}
	}

	// deresolve relations
	for ( OsmRelation * rel in dirty ) {
		if ( [rel isKindOfClass:[OsmRelation class]] ) {
			[rel deresolveRefs];
		}
	}

	// purge everything
	[self purgeExceptUndo];

	// put dirty stuff back in
	for ( OsmBaseObject * object in dirty ) {

		if ( [object isKindOfClass:[OsmBaseObject class]] ) {

			if ( object.isNode ) {
				[_nodes setObject:object.isNode forKey:@(object.ident)];
			} else if ( object.isWay ) {
				[_ways setObject:object.isWay forKey:@(object.ident)];
			} else if ( object.isRelation ) {
				[_relations setObject:object.isRelation forKey:@(object.ident)];
			} else {
				assert(NO);
			}

		} else {
			// it's an undo comment
		}
	}

	// restore relation references
	for ( OsmRelation * rel in dirty ) {
		if ( [rel isKindOfClass:[OsmRelation class]] ) {
			(void)[rel resolveToMapData:self];
		}
	}

	// rebuild spatial
	for ( OsmBaseObject * obj in dirty ) {
		if ( [obj isKindOfClass:[OsmBaseObject class]] ) {
			if ( !obj.deleted ) {
				[_spatial addMember:obj undo:nil];
			}
		}
	}

	[self consistencyCheck];
}



-(NSString *)pathToArchiveFile
{
	// get tile cache folder
	NSArray *paths = NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES );
	if ( [paths count] ) {
		NSString * bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
		NSString * path = [[[paths objectAtIndex:0]
							stringByAppendingPathComponent:bundleName]
						   stringByAppendingPathComponent:@"OSM Downloaded Data.archive"];
		[[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:NULL error:NULL];
		return path;
	}
	return nil;
}

-(id)archiver:(NSKeyedArchiver *)archiver willEncodeObject:(id)object
{
	if ( [object isKindOfClass:[OsmMapData class]] ) {
		return self;
	}
	if ( [object isKindOfClass:[EditorMapLayer class]] ) {
		DbgAssert( g_EditorMapLayerForArchive );
		return g_EditorMapLayerForArchive;
	}
	return object;
}
-(id)unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:(id)object
{
	DLog(@"didDecode %@: %@",[object class],object);
	if ( [object isKindOfClass:[EditorMapLayer class]] ) {
		DbgAssert( g_EditorMapLayerForArchive );
		return g_EditorMapLayerForArchive;
	}
	return object;
}

-(id)unarchiver:(NSKeyedArchiver *)unarchiver cannotDecodeObjectOfClassName:(nonnull NSString *)name originalClasses:(nonnull NSArray<NSString *> *)classNames
{
	DLog(@"archive error: %@",name);
	return nil;
}

- (void)unarchiver:(NSKeyedUnarchiver *)unarchiver willReplaceObject:(id)object withObject:(id)newObject
{
	DLog(@"replacing %@ -> %@", object, newObject);
}


-(BOOL)saveArchive
{
	NSString * path = [self pathToArchiveFile];

	NSMutableData * data = [NSMutableData data];
	NSKeyedArchiver * archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	archiver.delegate = self;
	[archiver encodeObject:self forKey:@"OsmMapData"];
	[archiver finishEncoding];
	BOOL ok = data  &&  [data writeToFile:path atomically:YES];
	return ok;
}

-(void)sqlSaveNodes:(NSArray<OsmNode *> *)saveNodes
           saveWays:(NSArray<OsmWay *> *)saveWays
      saveRelations:(NSArray<OsmRelation *> *)saveRelations
        deleteNodes:(NSArray<OsmNode *> *)deleteNodes
         deleteWays:(NSArray<OsmWay *> *)deleteWays
    deleteRelations:(NSArray<OsmRelation *> *)deleteRelations
           isUpdate:(BOOL)isUpdate
{
	if ( saveNodes.count + saveWays.count + saveRelations.count + deleteNodes.count + deleteWays.count + deleteRelations.count == 0 )
		return;

	dispatch_async(Database.dispatchQueue, ^{
		CFTimeInterval t = CACurrentMediaTime();
		BOOL ok;
		{
			Database * db = [Database new];
			[db createTables];
			ok = [db saveNodes:saveNodes
                      saveWays:saveWays
                 saveRelations:saveRelations
                   deleteNodes:deleteNodes
                    deleteWays:deleteWays
               deleteRelations:deleteRelations
                      isUpdate:isUpdate];
			if ( !ok ) {
				[Database deleteDatabaseWithName:nil];
			}
		}
		t = CACurrentMediaTime() - t;

		dispatch_async(dispatch_get_main_queue(), ^{
			DLog(@"%@sql save %ld objects, time = %f (%ld objects total)",
				 t > 1.0 ? @"*** " : @"",
				 (long)saveNodes.count+saveWays.count+saveRelations.count, t, (long)self.nodeCount+self.wayCount+self.relationCount );

			if ( !ok ) {
				// database failure
				_region = [QuadMap new];
			}
			[self save];
		});
	});
}


-(BOOL)discardStaleData
{
	if ( self.modificationCount > 0 )
		return NO;

	// don't discard too frequently
	NSDate * now = [NSDate date];
	if ( [now timeIntervalSinceDate:_previousDiscardDate] < 60 ) {
		return NO;
	}
	
	// remove objects if they are too old, or we have too many:
	NSInteger limit = 100000;
	NSDate * oldest = [NSDate dateWithTimeIntervalSinceNow:-24*60*60];
	
	// get rid of old quads marked as downloaded
	double fraction = (double)(_nodes.count + _ways.count + _relations.count) / limit;
	if ( fraction <= 1.0 ) {
		// the number of objects is acceptable
		fraction = 0.0;
	} else {
		fraction = 1.0 - 1.0/fraction;
		if ( fraction < 0.3 )
			fraction = 0.3;	// don't waste resources trimming tiny quantities
	}

	CFTimeInterval t = CACurrentMediaTime();

	BOOL didExpand = NO;
	for (;;) {

		oldest = [_region discardOldestQuads:fraction oldest:oldest];
		if ( oldest == nil ) {
			if ( !didExpand ) {
				return NO;	// nothing to discard
			}
			break;	// nothing more to drop
		}

#if DEBUG
		NSTimeInterval interval = [now timeIntervalSinceDate:oldest];
		if ( interval < 2*60 )
			NSLog(@"Discarding %f%% stale data %ld seconds old\n",100*fraction,(long)ceil(interval));
		else if ( interval < 60*60 )
			NSLog(@"Discarding %f%% stale data %ld minutes old\n",100*fraction,(long)interval/60);
		else
			NSLog(@"Discarding %f%% stale data %ld hours old\n",100*fraction,(long)interval/60/60);
#endif
		
		_previousDiscardDate = [NSDate distantFuture];	// mark as distant future until we're done discarding
		
		// now go through all objects and determine which are no longer in a downloaded region
		NSMutableArray * removeRelations	= [NSMutableArray new];
		NSMutableArray * removeWays			= [NSMutableArray new];
		NSMutableArray * removeNodes		= [NSMutableArray new];
		[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL * _Nonnull stop) {
			NSSet * objects = [relation allMemberObjects];
			BOOL covered = NO;
			for ( OsmBaseObject * obj in objects ) {
				if ( obj.isNode ) {
					if ( [_region pointIsCovered:obj.isNode.location] ) {
						covered = YES;
					}
				} else if ( obj.isWay ) {
					if ( [_region nodesAreCovered:obj.isWay.nodes] ) {
						covered = YES;
					}
				}
				if ( covered )
					break;
			}
			if ( !covered ) {
				[removeRelations addObject:ident];
			}
		}];
		[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL * _Nonnull stop) {
			if ( ! [_region nodesAreCovered:way.nodes] ) {
				[removeWays addObject:ident];
				for ( OsmNode * node in way.nodes ) {
					DbgAssert( node.wayCount > 0 );
					[node setWayCount:node.wayCount-1 undo:nil];
				}
			}
		}];
		[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmNode * node, BOOL * _Nonnull stop) {
			if ( node.wayCount == 0 ) {
				if ( ! [_region pointIsCovered:node.location] ) {
					[removeNodes addObject:ident];
				}
			}
		}];
		
		// remove from dictionaries
		[_nodes 	removeObjectsForKeys:removeNodes];
		[_ways		removeObjectsForKeys:removeWays];
		[_relations removeObjectsForKeys:removeRelations];

		NSLog(@"remove %ld objects\n",(long)removeNodes.count+removeWays.count+removeRelations.count);

		if ( _nodes.count + _ways.count + _relations.count < limit*1.3 ) {
			// good enough
			if ( !didExpand && removeNodes.count + removeWays.count + removeRelations.count == 0 ) {
				_previousDiscardDate = now;
				return NO;
			}
			break;
		}

		// we still have way too much stuff, need to be more aggressive
		didExpand = YES;
		fraction = 0.3;
	}
	
	// remove objects from spatial that are no longer in a dictionary
	[_spatial deleteObjectsWithPredicate:^BOOL(OsmBaseObject *obj) {
		if ( obj.isNode ) {
			return _nodes[@(obj.ident)] == nil;
		} else if ( obj.isWay ) {
			return _ways[@(obj.ident)] == nil;
		} else if ( obj.isRelation ) {
			return _relations[@(obj.ident)] == nil;
		} else {
			return YES;
		}
	}];
	
	// fixup relation references
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		[relation deresolveRefs];
		(void)[relation resolveToMapData:self];
	}];

	[self consistencyCheck];

	t = CACurrentMediaTime() - t;
	NSLog(@"Discard sweep time = %f\n",t);

	// make a copy of items to save because the dictionary might get updated by the time the Database block runs
	NSArray<OsmNode *> * saveNodes 	= [_nodes allValues];
	NSArray<OsmWay *> * saveWays 		= [_ways allValues];
	NSArray<OsmRelation *> * saveRelations = [_relations allValues];
	
	dispatch_async(Database.dispatchQueue, ^{
		
		CFTimeInterval	t2 = CACurrentMediaTime();
		NSString * tmpPath;
		{
			// its faster to create a brand new database than to update the existing one, because SQLite deletes are slow
			[Database deleteDatabaseWithName:@"tmp"];
			Database * db2 = [[Database alloc] initWithName:@"tmp"];
			tmpPath = db2.path;
			[db2 createTables];
			[db2 saveNodes:saveNodes
                  saveWays:saveWays
             saveRelations:saveRelations
               deleteNodes:nil
                deleteWays:nil
           deleteRelations:nil
                  isUpdate:NO];
		}
		
		NSString * realPath = [Database databasePathWithName:nil];
		int error = rename( tmpPath.UTF8String, realPath.UTF8String );
		if ( error )
			NSLog(@"failed to rename SQL database\n");
		
		t2 = CACurrentMediaTime() - t2;
		NSLog(@"%@Discard save time = %f, saved %ld objects\n",
			  t2 > 1.0 ? @"*** " : @"",
			  t2,(long)self.nodeCount+self.wayCount+self.relationCount);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			_previousDiscardDate = [NSDate date];
		});
	});
	
	return YES;
}


// after uploading a changeset we have to update the SQL database to reflect the changes the server replied with
-(void)updateSql:(NSDictionary *)sqlUpdate
{
	NSMutableArray<OsmNode *> * insertNode		= [NSMutableArray new];
	NSMutableArray<OsmWay *> * insertWay		= [NSMutableArray new];
    NSMutableArray<OsmRelation *> * insertRelation    = [NSMutableArray new];
	NSMutableArray<OsmNode *> * deleteNode		= [NSMutableArray new];
	NSMutableArray<OsmWay *> * deleteWay		= [NSMutableArray new];
	NSMutableArray<OsmRelation *> * deleteRelation	= [NSMutableArray new];
	[sqlUpdate enumerateKeysAndObjectsUsingBlock:^(OsmBaseObject * object, NSNumber * insert, BOOL *stop) {
		if ( object.isNode ) {
			if ( insert.boolValue )
				[insertNode addObject:object.isNode];
			else
				[deleteNode addObject:object.isNode];
		} else if ( object.isWay ) {
			if ( insert.boolValue )
				[insertWay addObject:object.isWay];
			else
				[deleteWay addObject:object.isWay];
		} else if ( object.isRelation ) {
			if ( insert.boolValue )
				[insertRelation addObject:object.isRelation];
			else
				[deleteRelation addObject:object.isRelation];
		} else {
			assert(NO);
		}
	}];
	[self sqlSaveNodes:insertNode
              saveWays:insertWay
         saveRelations:insertRelation
           deleteNodes:deleteNode
            deleteWays:deleteWay
       deleteRelations:deleteRelation
              isUpdate:YES];
}


-(void)save
{
	CFTimeInterval t = CACurrentMediaTime();
	// save dirty data and relations
	DbgAssert(g_EditorMapLayerForArchive);
	OsmMapData * modified = [self modifiedObjects];
	modified->_region = _region;
	modified->_spatial = _spatial;
	QuadBox * spatialRoot = _spatial.rootQuad;
	_spatial.rootQuad = nil;	// This aliases modified->_spatial.rootQuad, which we will rebuild when we reload
	[modified saveArchive];
	_spatial.rootQuad = spatialRoot;

	t = CACurrentMediaTime() - t;
	(void)t;
	DLog(@"archive save %ld,%ld,%ld,%ld,%ld = %f", (long)modified.nodeCount, (long)modified.wayCount, (long)modified.relationCount, (long)_undoManager.countUndoGroups, (long)_region.count, t);
	DLog(@"Save objects = %ld", (long)self.nodeCount+self.wayCount+self.relationCount);
	
	[_periodicSaveTimer invalidate];
	_periodicSaveTimer = nil;
}

-(instancetype)initWithCachedData
{
	NSString * path = [self pathToArchiveFile];
	NSData * data = [NSData dataWithContentsOfFile:path];
	if ( data == nil ) {
		return nil;
	}

	NSKeyedUnarchiver * unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	unarchiver.delegate = self;
	self = [unarchiver decodeObjectForKey:@"OsmMapData"];
	if ( self ) {

		// rebuild spatial database
		_spatial.rootQuad = [QuadBox new];
		[self enumerateObjectsUsingBlock:^(OsmBaseObject *obj) {
			if ( !obj.deleted )
				[_spatial addMember:obj undo:nil];
		}];

		// merge info from SQL database
		Database * db = [Database new];
		@try {
			NSMutableDictionary<NSNumber *, OsmNode *> * newNodes			= [db querySqliteNodes];
			NSAssert(newNodes,nil);
			NSMutableDictionary<NSNumber *, OsmWay *> * newWays				= [db querySqliteWays];
			NSAssert(newWays,nil);
			NSMutableDictionary<NSNumber *, OsmRelation *> * newRelations	= [db querySqliteRelations];
			NSAssert(newRelations,nil);
			@try {
				OsmMapData * newData = [[OsmMapData alloc] init];
				newData->_nodes = newNodes;
				newData->_ways = newWays;
				newData->_relations = newRelations;
				[self merge:newData fromDownload:NO quadList:nil success:YES];
			} @catch (id exception) {
				// we couldn't resolve references correctly, which leaves us in an inconsistent state
				NSLog(@"Unable to read database: recreating from scratch\n");
				[db close];
				[Database deleteDatabaseWithName:nil];
				// try again
				return [[OsmMapData alloc] initWithCachedData];
			}
		} @catch (id exception) {
			// database couldn't be read
			NSLog(@"Unable to read database: recreating from scratch\n");
			[db close];
			[Database deleteDatabaseWithName:nil];
			// download all regions
			_region = [QuadMap new];
		}
		[self consistencyCheck];
	}

	return self;
}


-(void)consistencyCheckRelationMembers
{
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL * _Nonnull stop) {
		for ( OsmMember * member in relation.members ) {
			OsmBaseObject * object = member.obj;
			if ( [object isKindOfClass:[NSNumber class]] )
				continue;;
			assert( [object.parentRelations containsObject:relation] );
		}
	}];
}

-(void)consistencyCheck
{
#if DEBUG && 0
	// This is extremely expensive: DEBUG only!
	NSLog(@"Checking spatial database consistency");
	[self consistencyCheckRelationMembers];
	[_spatial consistencyCheckNodes:_nodes.allValues ways:_ways.allValues relations:_relations.allValues];
#endif
}

@end
