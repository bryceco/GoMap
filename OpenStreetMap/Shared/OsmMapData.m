//
//  XmlParserDelegate.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE
#import "DDXML.h"
#import "../iOS/AppDelegate.h"
#else
#import "AppDelegate.h"
#endif

#import "DLog.h"
#import "DownloadThreadPool.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "QuadMap.h"
#import "UndoManager.h"
#import "VectorMath.h"

#if 1 || DEBUG
#define USE_SQL 1
#endif

#if USE_SQL
#import "Database.h"
#import "EditorMapLayer.h"
#endif




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


-(id)init
{
	self = [super init];
	if ( self ) {
		_parserStack	= [NSMutableArray arrayWithCapacity:20];
		_nodes			= [NSMutableDictionary dictionaryWithCapacity:1000];
		_ways			= [NSMutableDictionary dictionaryWithCapacity:1000];
		_relations		= [NSMutableDictionary dictionaryWithCapacity:10];
		_region			= [QuadMap new];
		_spatial		= [QuadMap new];
		_undoManager	= [UndoManager new];

		_undoManager.delegate = self;

		[self setupPeriodicSaveTimer];
	}
	return self;
}

-(void)dealloc
{
	[_periodicSaveTimer invalidate];
}

-(void)setupPeriodicSaveTimer
{
	__weak OsmMapData * weakSelf = self;
	[_undoManager addChangeCallback:^{
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
	[self save];	// this will also set the timer to nil
}



-(OSMRect)rootRect
{
	return _spatial.rootQuad.rect;
}


-(NSSet *)tagsToAutomaticallyStrip
{
	return [NSSet setWithObjects:
				@"tiger:upload_uuid", @"tiger:tlid", @"tiger:source", @"tiger:separated",
				@"geobase:datasetName", @"geobase:uuid", @"sub_sea:type", @"odbl", @"odbl:note",
				@"yh:LINE_NAME", @"yh:LINE_NUM", @"yh:STRUCTURE", @"yh:TOTYUMONO", @"yh:TYPE", @"yh:WIDTH_RANK",
			nil];
};


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

-(NSArray *)waysContainingNode:(OsmNode *)node
{
	__block NSMutableArray * a = [NSMutableArray new];
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
			if ( [way.nodes containsObject:object] )
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
	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSString * ident,OsmNode * node,BOOL * stop){
		block( node );
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSString * ident,OsmWay * way,BOOL * stop) {
		block( way );
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSString * ident,OsmNode * node,BOOL * stop){
		block( node );
	}];
}
- (void)enumerateObjectsInRegion:(OSMRect)bbox block:(void (^)(OsmBaseObject * obj))block
{
	if ( bbox.origin.x < 180 && bbox.origin.x + bbox.size.width > 180 ) {
		OSMRect left = { bbox.origin.x, bbox.origin.y, 180-bbox.origin.x, bbox.size.height };
		OSMRect right = { -180, bbox.origin.y, bbox.origin.x + bbox.size.width - 180, bbox.size.height };
		[self enumerateObjectsInRegion:left block:block];
		[self enumerateObjectsInRegion:right block:block];
		return;
	}

	[_spatial findObjectsInArea:bbox block:^(OsmBaseObject * o){
		block( o );
	}];
}


-(NSMutableSet *)tagValuesForKey:(NSString *)key
{
	NSMutableSet * set = [NSMutableSet set];
	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSString * ident, OsmBaseObject * object, BOOL *stop) {
		NSString * value = [object.tags objectForKey:key];
		if ( value ) {
			[set addObject:value];
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSString * ident, OsmBaseObject * object, BOOL *stop) {
		NSString * value = [object.tags objectForKey:key];
		if ( value ) {
			[set addObject:value];
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSString * ident, OsmBaseObject * object, BOOL *stop) {
		NSString * value = [object.tags objectForKey:key];
		if ( value ) {
			[set addObject:value];
		}
	}];

	// special case for street names
	if ( [key isEqualToString:@"addr:street"] ) {
		[_ways enumerateKeysAndObjectsUsingBlock:^(NSString * ident, OsmBaseObject * object, BOOL *stop) {
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


-(NSArray *)userStatisticsForRegion:(OSMRect)rect
{
	NSMutableDictionary * dict = [NSMutableDictionary dictionary];

	[self enumerateObjectsInRegion:rect block:^(OsmBaseObject * base) {
		NSDate * date = [base dateForTimestamp];
		if ( base.user.length == 0 ) {
			DLog(@"Empty user name for object: object %@, uid = %d", base, base.uid);
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


#pragma mark Editing

static NSString * StringTruncatedTo255( NSString * s )
{
	if ( s.length > 255 )
		s = [s substringToIndex:256];
	while ( [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255 ) {
		s = [s substringToIndex:s.length-1];
	}
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

-(void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects
{
	[_undoManager registerUndoWithTarget:target selector:selector objects:objects];
}

-(void)setTags:(NSDictionary *)dict forObject:(OsmBaseObject *)object
{
	dict = DictWithTagsTruncatedTo255( dict );

	[_undoManager registerUndoComment:NSLocalizedString(@"set tags",nil)];
	[object setTags:dict undo:_undoManager];
}


-(OsmNode *)createNodeAtLocation:(CLLocationCoordinate2D)loc
{
	OsmNode * node = [OsmNode new];
	[node constructAsUserCreated:self.credentialsUserName];
	[node setLongitude:loc.longitude latitude:loc.latitude undo:nil];
	[node setDeleted:YES undo:nil];
	[self setConstructed:node];
	[_nodes setObject:node forKey:node.ident];
	
	[_undoManager registerUndoComment:NSLocalizedString(@"create node",nil)];
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
	[_ways setObject:way forKey:way.ident];

	[_undoManager registerUndoComment:NSLocalizedString(@"create way",nil)];
	[way setDeleted:NO undo:_undoManager];
	return way;
}

-(OsmRelation *)createRelation
{
	OsmRelation * relation = [OsmRelation new];
	[relation constructAsUserCreated:self.credentialsUserName];
	[relation setDeleted:YES undo:nil];
	[self setConstructed:relation];
	[_relations setObject:relation forKey:relation.ident];

	[_undoManager registerUndoComment:NSLocalizedString(@"create relation",nil)];
	[relation setDeleted:NO undo:_undoManager];
	return relation;
}

-(void)removeFromParentRelations:(OsmBaseObject *)object
{
	while ( object.relations.count ) {
		OsmRelation * relation = object.relations.lastObject;
		NSInteger memberIndex = 0;
		while ( memberIndex < relation.members.count ) {
			OsmMember * member = relation.members[memberIndex];
			if ( member.ref == object ) {
				[self deleteMemberInRelation:relation index:memberIndex];
			} else {
				++memberIndex;
			}
		}
	}
}


-(void)deleteNode:(OsmNode *)node
{
	assert( node.wayCount == 0 );
	[_undoManager registerUndoComment:NSLocalizedString(@"delete node",nil)];

	[self removeFromParentRelations:node];

	[node setDeleted:YES undo:_undoManager];

	[_spatial removeMember:node undo:_undoManager];
}

-(void)deleteWay:(OsmWay *)way
{
	[_undoManager registerUndoComment:NSLocalizedString(@"delete way",nil)];
	[_spatial removeMember:way undo:_undoManager];

	[self removeFromParentRelations:way];

	while ( way.nodes.count ) {
		[self deleteNodeInWay:way index:way.nodes.count-1];
	}
	[way setDeleted:YES undo:_undoManager];
}

-(void)deleteRelation:(OsmRelation *)relation
{
	[_undoManager registerUndoComment:NSLocalizedString(@"delete relation",nil)];
	[_spatial removeMember:relation undo:_undoManager];

	[self removeFromParentRelations:relation];

	while ( relation.members.count ) {
		[relation removeMemberAtIndex:relation.members.count-1 undo:_undoManager];
	}
	[relation setDeleted:YES undo:_undoManager];
}

-(void)addNode:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index
{
	[_undoManager registerUndoComment:NSLocalizedString(@"add node to way",nil)];
	OSMRect origBox = way.boundingBox;
	[way addNode:node atIndex:index undo:_undoManager];
	[_spatial updateMember:way fromBox:origBox undo:_undoManager];
}
-(void)deleteNodeInWay:(OsmWay *)way index:(NSInteger)index
{
	[_undoManager registerUndoComment:NSLocalizedString(@"delete node from way",nil)];
	OsmNode * node = way.nodes[ index ];
	assert( node.wayCount > 0 );

	OSMRect bbox = way.boundingBox;
	[way removeNodeAtIndex:index undo:_undoManager];
	// if removing the node leads to 2 identical nodes being consecutive delete one of them as well
	while ( index > 0 && index < way.nodes.count && way.nodes[index-1] == way.nodes[index] )
		[way removeNodeAtIndex:index undo:_undoManager];
	[_spatial updateMember:way fromBox:bbox undo:_undoManager];

	if ( node.wayCount == 0 ) {
		[self deleteNode:node];
	}
}
-(void)setLongitude:(double)longitude latitude:(double)latitude forNode:(OsmNode *)node inWay:(OsmWay *)way
{
	[_undoManager registerUndoComment:NSLocalizedString(@"move",nil)];

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
		[self incrementModifyCount:parent];
		[self clearCachedProperties:parent undo:_undoManager];
		[_spatial updateMember:parent fromBox:box.rect undo:_undoManager];
	}
}

-(void)clearCachedProperties:(OsmBaseObject *)object undo:(UndoManager *)undo
{
	[undo registerUndoWithTarget:self selector:@selector(clearCachedProperties:undo:) objects:@[object,undo]];
	[object clearCachedProperties];
}

-(void)addMember:(OsmMember *)member toRelation:(OsmRelation *)relation atIndex:(NSInteger)index
{
	[_undoManager registerUndoComment:NSLocalizedString(@"add object to relation",nil)];
	OSMRect bbox = relation.boundingBox;
	[relation addMember:member atIndex:index undo:_undoManager];
	[_spatial updateMember:relation fromBox:bbox undo:_undoManager];
}
-(void)deleteMemberInRelation:(OsmRelation *)relation index:(NSInteger)index
{
	[_undoManager registerUndoComment:NSLocalizedString(@"delete object from relation",nil)];
	OSMRect bbox = relation.boundingBox;
	[relation removeMemberAtIndex:index undo:_undoManager];
	[_spatial updateMember:relation fromBox:bbox undo:_undoManager];
}


-(void)incrementModifyCount:(OsmBaseObject *)object
{
	[_undoManager registerUndoWithTarget:self selector:@selector(incrementModifyCount:) objects:@[object]];
	[object incrementModifyCount:_undoManager];

}


#pragma mark Undo manager

-(void)undo
{
	[_undoManager undo];
}
-(void)redo
{
	[_undoManager redo];
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
	[_undoManager addChangeCallback:callback];
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
-(void)setUndoCommentCallback:(void(^)(BOOL,NSArray *))commentCallback
{
	_undoManager.commentCallback = commentCallback;
}
-(void(^)(BOOL,NSArray *))undoCommentCallback
{
	return _undoManager.commentCallback;
}
-(void)setUndoLocationCallback:(NSData * (^)(void))callback
{
	_undoManager.locationCallback = callback;
}

-(BOOL)undoAction:(UndoAction *)newAction duplicatesPreviousAction:(UndoAction *)prevAction
{
	if ( newAction.target != prevAction.target )
		return NO;
	if ( ![newAction.selector isEqualToString:prevAction.selector] )
		return NO;
	// same target and selector
	if ( [newAction.selector isEqualToString:@"setLongitude:latitude:undo:"] ) {
		return YES;
	}
	if ( [newAction.selector isEqualToString:@"setSelectedRelation:way:node:"] ) {
		return	newAction.objects[0] == prevAction.objects[0] &&
				newAction.objects[1] == prevAction.objects[1] &&
				newAction.objects[2] == prevAction.objects[2];
	}
	return NO;
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
			[query.quadList	addObject:q];
			rect.size.width += q.rect.size.width;
			query.rect = rect;
			continue;
		}

		rect = q.rect;
		query = [ServerQuery new];
		query.quadList = [NSMutableArray arrayWithObject:q];
		query.rect = rect;
		[queries addObject:query];
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
		DLog(@"  %@", NSStringFromRect(q.rect));
#endif

	return queries;
}

// http://wiki.openstreetmap.org/wiki/API_v0.6#Retrieving_map_data_by_bounding_box:_GET_.2Fapi.2F0.6.2Fmap
+ (void)osmDataForUrl:(NSString *)url quads:(ServerQuery *)quads completion:(void(^)(ServerQuery * quads,OsmMapData * data,NSError * error))completion
{
	[[DownloadThreadPool osmPool] streamForUrl:url callback:^(DownloadAgent * agent){

		if ( agent.stream.streamError ) {

			dispatch_async(dispatch_get_main_queue(), ^{
				completion( quads, nil, agent.stream.streamError );
			});

		} else {

			OsmMapData * mapData = [[OsmMapData alloc] init];
			NSError * error = nil;
			BOOL ok = [mapData parseXmlStream:agent.stream error:&error];
			if ( !ok ) {
				if ( agent.dataHeader.length ) {
					// probably some html-encoded error message from the server, or if cancelled then the leading portion of the xml download
					//NSString * s = [[NSString alloc] initWithBytes:agent.dataHeader.bytes length:agent.dataHeader.length encoding:NSUTF8StringEncoding];
					//error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : s }];
					error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : NSLocalizedString(@"Data not available",nil) }];
				} else if ( agent.stream.streamError ) {
					error = agent.stream.streamError;
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

- (void)updateWithBox:(OSMRect)box mapView:(MapView *)mapView completion:(void(^)(BOOL partial,NSError * error))completion
{
	__block int activeRequests = 0;

	void(^mergePartialResults)(ServerQuery * query,OsmMapData * mapData,NSError * error) = ^(ServerQuery * query,OsmMapData * mapData,NSError * error){
		[mapView progressDecrement];
		--activeRequests;
		if ( activeRequests == 0 ) {
		}
		//	DLog(@"merge %ld nodes, %ld ways", mapData.nodes.count, mapData.ways.count);
		[self merge:mapData fromDownload:YES quadList:query.quadList success:(mapData && error==nil)];
		completion( activeRequests > 0, error );
	};

	// check how much area we're trying to download, and if too large complain
	NSError * error = nil;
#if 1
	NSArray * newQuads = nil;
	double area = SurfaceArea( box );
	BOOL tooLarge = area > 10.0*1000*1000;	// square kilometer
	if ( !tooLarge ) {
		// get list of new quads to fetch
		newQuads = [_region newQuadsForRect:box];
	} else {
		error = [NSError errorWithDomain:@"Network" code:1 userInfo:@{ NSLocalizedDescriptionKey : NSLocalizedString(@"Edit download region is too large",nil) }];
		[[DownloadThreadPool osmPool] cancelAllDownloads];
	}
#else
	NSArray * newQuads = [_region newQuadsForRect:box];
#endif

	if ( newQuads.count == 0 ) {
		++activeRequests;
		[mapView progressIncrement:NO];
		mergePartialResults( nil, nil, error );
	} else {
		NSArray * queryList = [OsmMapData coalesceQuadQueries:newQuads];
		for ( ServerQuery * query in queryList ) {
			++activeRequests;
			[mapView progressIncrement:NO];
			[OsmMapData osmDataForBox:query completion:mergePartialResults];
		}
	}

	[mapView progressAnimate];
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

		[_nodes setObject:node forKey:node.ident];
		[_parserStack addObject:node];
		
	} else if ( [elementName isEqualToString:@"way"] ) {

		OsmWay * way = [OsmWay new];
		[way constructBaseAttributesFromXmlDict:attributeDict];

		[_ways setObject:way forKey:way.ident];
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

		[_relations setObject:relation forKey:relation.ident];
		[_parserStack addObject:relation];

	} else if ( [elementName isEqualToString:@"member"] ) {

		NSString *	type = [attributeDict objectForKey:@"type"];
		NSNumber *	ref  = @([[attributeDict objectForKey:@"ref"] longLongValue]);
		NSString *	role = [attributeDict objectForKey:@"role"];

		OsmMember * member = [[OsmMember alloc] initWithType:type ref:ref role:role];

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

		NSMutableArray * newNodes = [NSMutableArray new];
		NSMutableArray * newWays = [NSMutableArray new];
		NSMutableArray * newRelations = [NSMutableArray new];

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
		[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmRelation * relation,BOOL * stop){
			OSMRect bbox = relation.boundingBox;
			[relation resolveToMapData:self];
			[_spatial updateMember:relation fromBox:bbox undo:nil];
		}];


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
			[self sqlSaveNodes:newNodes saveWays:newWays saveRelations:newRelations deleteNodes:nil deleteWays:nil deleteRelations:nil isUpdate:NO];
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
	assert( object && object.ident.longLongValue == oldId );
	if ( newVersion == 0 && newId == 0 ) {
		// Delete object for real
		// When a way is deleted we delete the nodes also, but they aren't marked as deleted in the graph.
		// If nodes are still in use by another way the newId and newVersion will be set and we won't take this path.
		assert( newId == 0 && newVersion == 0 );
		if ( object.isNode ) {
			[_nodes removeObjectForKey:object.ident];
		} else if ( object.isWay ) {
			[_ways removeObjectForKey:object.ident];
		} else if ( object.isRelation ) {
			[_relations removeObjectForKey:object.ident];
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
		// replace placeholer object with new server provided identity
		assert( oldId < 0 && newId > 0 );
		[dictionary removeObjectForKey:object.ident];
		[object serverUpdateIdent:newId];
		[dictionary setObject:object forKey:object.ident];
	} else {
		assert( oldId > 0 );
	}
	[object resetModifyCount:_undoManager];
}


+(NSString *)encodeBase64:(NSString *)plainText
{
	static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	NSMutableString * output = [[NSMutableString alloc] initWithCapacity:plainText.length*3];
	const unsigned char * inputBuffer = (const unsigned char *)plainText.UTF8String;
	NSInteger length = strlen((char *)inputBuffer);

	for ( NSInteger i = 0; i < length; i += 3 ) {

		NSInteger remain = length - i;

		[output appendFormat:@"%c", alphabet[(inputBuffer[i] & 0xFC) >> 2]];
		[output appendFormat:@"%c", alphabet[((inputBuffer[i] & 0x03) << 4) | ((remain > 1) ? ((inputBuffer[i + 1] & 0xF0) >> 4): 0)]];

		if ( remain > 1 )
			[output appendFormat:@"%c", alphabet[((inputBuffer[i + 1] & 0x0F) << 2) | ((remain > 2) ? ((inputBuffer[i + 2] & 0xC0) >> 6) : 0)]];
		else
			[output appendString:@"="];

		if ( remain > 2 )
			[output appendFormat:@"%c", alphabet[inputBuffer[i + 2] & 0x3F]];
		else
			[output appendString:@"="];
	}
	return output;
}

-(void)putRequest:(NSString *)url method:(NSString *)method xml:(NSXMLDocument *)xml completion:(void(^)(NSData * data,NSString * error))completion
{
	if ( [url hasPrefix:@"http:"] ) {
		url = [@"https" stringByAppendingString:[url substringFromIndex:4]];
	}

	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	[request setHTTPMethod:method];
	if ( xml ) {
		NSData * data = [xml XMLDataWithOptions:0];
		[request setHTTPBody:data];
		[request setValue:@"application/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
	}
	[request setCachePolicy:NSURLRequestUseProtocolCachePolicy];
	// request.timeoutInterval = 15*60;

	NSString * auth = [NSString stringWithFormat:@"%@:%@", _credentialsUserName, _credentialsPassword];
	auth = [OsmMapData encodeBase64:auth];
	auth = [NSString stringWithFormat:@"Basic %@", auth];
	[request setValue:auth forHTTPHeaderField:@"Authorization"];

	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse * response, NSData * data, NSError * error) {
		if ( data && error == nil ) {
			completion(data,nil);
		} else {
			NSString * errorMessage;
			if ( data.length > 0 ) {
				errorMessage = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
			} else {
				errorMessage = error.localizedDescription;
			}
			completion(nil,errorMessage);
		}
	}];

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
	[element addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:object.ident.stringValue]];
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
		if ( node.deleted && node.ident.longLongValue > 0 ) {
			// deleted
			NSXMLElement * element = [OsmMapData elementForObject:node];
			[deleteNodeElement addChild:element];
		} else if ( node.isModified && !node.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:node];
			[element addAttribute:[NSXMLNode attributeWithName:@"lat" stringValue:@(node.lat).stringValue]];
			[element addAttribute:[NSXMLNode attributeWithName:@"lon" stringValue:@(node.lon).stringValue]];
			[OsmMapData addTagsForObject:node element:element];
			if ( node.ident.longLongValue < 0 ) {
				[createNodeElement addChild:element];
			} else {
				[modifyNodeElement addChild:element];
			}
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
		if ( way.deleted && way.ident.longLongValue > 0 ) {
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
				[refElement addAttribute:[NSXMLNode attributeWithName:@"ref" stringValue:node.ident.stringValue]];
				[element addChild:refElement];
			}
			[OsmMapData addTagsForObject:way element:element];
			if ( way.ident.longLongValue < 0 ) {
				[createWayElement addChild:element];
			} else {
				[modifyWayElement addChild:element];
			}
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		if ( relation.deleted && relation.ident.longLongValue > 0 ) {
			NSXMLElement * element = [OsmMapData elementForObject:relation];
			[deleteRelationElement addChild:element];
		} else if ( relation.isModified && !relation.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:relation];
			for ( OsmMember * member in relation.members ) {
				NSNumber * ref = nil;
				if ( [member.ref isKindOfClass:[NSNumber class]] ) {
					ref = member.ref;
				} else if ( [member.ref isKindOfClass:[OsmBaseObject class]] ) {
					ref = ((OsmBaseObject *)member.ref).ident;
				} else {
					assert(NO);
				}
				NSXMLElement * memberElement = [NSXMLElement elementWithName:@"member"];
				[memberElement addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:member.type]];
				[memberElement addAttribute:[NSXMLNode attributeWithName:@"ref" stringValue:ref.stringValue]];
				[memberElement addAttribute:[NSXMLNode attributeWithName:@"role" stringValue:member.role]];
				[element addChild:memberElement];
			}
			[OsmMapData addTagsForObject:relation element:element];
			if ( relation.ident.longLongValue < 0 ) {
				[createRelationElement addChild:element];
			} else {
				[modifyRelationElement addChild:element];
			}
		}
	}];


#if TARGET_OS_IPHONE
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
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
		if ( node.deleted && node.ident.longLongValue > 0 ) {
			// deleted
			[deleteNode addObject:node];
		} else if ( node.isModified && !node.deleted ) {
			// added/modified
			if ( node.ident.longLongValue < 0 ) {
				[createNode addObject:node];
			} else {
				[modifyNode addObject:node];
			}
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmWay * way, BOOL *stop) {
		if ( way.deleted && way.ident.longLongValue > 0 ) {
			[deleteWay addObject:way];
			for ( OsmNode * node in way.nodes ) {
				[deleteNode addObject:node];
			}
		} else if ( way.isModified && !way.deleted ) {
			// added/modified
			if ( way.ident.longLongValue < 0 ) {
				[createWay addObject:way];
			} else {
				[modifyWay addObject:way];
			}
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
		if ( relation.deleted && relation.ident.longLongValue > 0 ) {
			[deleteRelation addObject:relation];
		} else if ( relation.isModified && !relation.deleted ) {
			// added/modified
			if ( relation.ident.longLongValue < 0 ) {
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
			if ( [osmObject isKindOfClass:[DDXMLElement class]] ) {
				[osmObject addAttribute:[NSXMLNode attributeWithName:@"changeset" stringValue:changesetID]];
			}
		}
	}
}

- (void)uploadChangeset:(NSXMLDocument *)xmlChanges comment:(NSString *)comment retry:(BOOL)retry completion:(void(^)(NSString * errorMessage))completion
{
#if TARGET_OS_IPHONE
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
#else
	AppDelegate * appDelegate = [[NSApplication sharedApplication] delegate];
#endif

	NSString * creator = [NSString stringWithFormat:@"%@ %@", appDelegate.appName, appDelegate.appVersion];

	NSMutableDictionary * tags = [NSMutableDictionary dictionaryWithDictionary:@{ @"created_by" : creator }];
	if ( comment.length )
		[tags addEntriesFromDictionary:@{ @"comment" : comment }];
	NSXMLDocument * xmlCreate = [OsmMapData createXmlWithType:@"changeset" tags:tags];
	NSString * url = [OSM_API_URL stringByAppendingString:@"api/0.6/changeset/create"];

	[self putRequest:url method:@"PUT" xml:xmlCreate completion:^(NSData * putData,NSString * putErrorMessage){
		if ( putData ) {
			NSString * changesetID = [[NSString alloc] initWithBytes:putData.bytes length:putData.length encoding:NSUTF8StringEncoding];
			// DLog(@"changeset ID = %@",changesetID);

			[OsmMapData updateChangesetXml:xmlChanges withChangesetID:changesetID];

			// DLog(@"change XML = %@",xmlChanges);

			NSString * url2 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/changeset/%@/upload", changesetID];
			[self putRequest:url2 method:@"POST" xml:xmlChanges completion:^(NSData *postData,NSString * postErrorMessage) {
				NSString * response = [[NSString alloc] initWithBytes:postData.bytes length:postData.length encoding:NSUTF8StringEncoding];

				if ( retry && [response hasPrefix:@"Version mismatch"] ) {

					// update the bad element and retry
					DLog( @"Upload error: %@", response);
					uint32_t localVersion = 0, serverVersion = 0;
					OsmIdentifier objId = 0;
					char type[256] = "";
					if ( sscanf( response.UTF8String, "Version mismatch: Provided %d, server had: %d of %[a-zA-Z] %lld", &localVersion, &serverVersion, type, &objId ) == 4 ) {
						type[0] = _tolower( type[0] );
						NSString * url3 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/%s/%lld", type, objId];

						[OsmMapData osmDataForUrl:url3 quads:nil completion:^(ServerQuery *quads, OsmMapData * mapData, NSError *error) {
							[self merge:mapData fromDownload:YES quadList:nil success:YES];
							// try again:
							[self uploadChangesetWithComment:comment completion:completion];
						}];
						return;
					}
				}

				//DLog(@"upload response = %@",response);

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

				[self updateSql:sqlUpdate isUpdate:YES];

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

		} else {
			completion(putErrorMessage);
		}
	}];
}

- (void)uploadChangesetWithComment:(NSString *)comment completion:(void(^)(NSString * errorMessage))completion
{
	NSXMLDocument * xmlChanges = [self createXml];
	if ( xmlChanges == nil ) {
		completion( @"No changes to apply" );
		return;
	}
	[self uploadChangeset:xmlChanges comment:comment retry:YES completion:completion];
}

- (void)verifyUserCredentialsWithCompletion:(void(^)(NSString * errorMessage))completion
{
#if TARGET_OS_IPHONE
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
#else
	AppDelegate * appDelegate = [[NSApplication sharedApplication] delegate];
#endif

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
				errorMessage = @"Not found";
			completion(errorMessage);
		}
	}];
}



#pragma mark Pretty print changeset


-(void)updateString:(NSMutableAttributedString *)string withTag:(NSXMLElement *)tag
{
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:12];
	NSString * text = [NSString stringWithFormat:@"\t\t%@ = %@\n",
					   [tag attributeForName:@"k"].stringValue,
					   [tag attributeForName:@"v"].stringValue];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font }]];
}
-(void)updateString:(NSMutableAttributedString *)string withMember:(NSXMLElement *)tag
{
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:12];
	NSString * text = [NSString stringWithFormat:@"\t\t%@ %@: \"%@\"\n",
					   [tag attributeForName:@"type"].stringValue,
					   [tag attributeForName:@"ref"].stringValue,
					   [tag attributeForName:@"role"].stringValue];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font }]];
}

-(void)updateString:(NSMutableAttributedString *)string withNode:(NSXMLElement *)node
{
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:14];
	NSString * lat = [node attributeForName:@"lat"].stringValue;
	NSString * lon = [node attributeForName:@"lon"].stringValue;
	NSString * text = lat && lon
		? [NSString stringWithFormat:NSLocalizedString(@"\tNode %@ (%.6f,%.6f)\n",nil), [node attributeForName:@"id"].stringValue, lat.doubleValue, lon.doubleValue]
		: [NSString stringWithFormat:NSLocalizedString(@"\tNode %@\n",nil), [node attributeForName:@"id"].stringValue];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font }]];
	for ( NSXMLElement * tag in node.children ) {
		if ( [tag.name isEqualToString:@"tag"] ) {
			[self updateString:string withTag:(NSXMLElement *)tag];
		} else {
			assert(NO);
		}
	}
}
-(void)updateString:(NSMutableAttributedString *)string withWay:(NSXMLElement *)way
{
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:14];
	NSString * text = [NSString stringWithFormat:NSLocalizedString(@"\tWay %@ (%d entries)\n",nil),
					   [way attributeForName:@"id"].stringValue,
					   (int)way.childCount];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font }]];
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
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:14];
	NSString * text = [NSString stringWithFormat:NSLocalizedString(@"\tRelation %@ (%d members)\n",nil),
					   [relation attributeForName:@"id"].stringValue,
					   (int)relation.childCount];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{ NSFontAttributeName : font }]];
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
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:18];
	[string appendAttributedString:[[NSAttributedString alloc] initWithString:header attributes:@{ NSFontAttributeName : font }]];
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

-(NSString *)changesetAsHtml
{
#if TARGET_OS_IPHONE
	return nil;
#else
	NSXMLDocument * xml = [self createXmlWithChangeset:@"0"];
	if ( xml == nil )
		return nil;
	// get XSLT code
	// http://www.w3schools.com/xml/tryxslt.asp?xmlfile=simple&xsltfile=simple
	NSString *xsltPath = [[NSBundle mainBundle] pathForResource:@"changeset" ofType:@"xsl"];
	assert(xsltPath);
	NSURL * xsltUrl = [NSURL fileURLWithPath:xsltPath];
	// transform through XSLT
	NSXMLDocument * htmlDoc = (NSXMLDocument *)[xml objectByApplyingXSLTAtURL:xsltUrl arguments:nil error:nil];
	// put in WebFrame
	NSString * html = htmlDoc.XMLString;
	return html;
#endif
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
	self = [super init];
	if ( self ) {

		@try {
			_nodes			= [coder decodeObjectForKey:@"nodes"];
			_ways			= [coder decodeObjectForKey:@"ways"];
			_relations		= [coder decodeObjectForKey:@"relations"];
			_region			= [coder decodeObjectForKey:@"region"];
			_spatial		= [coder decodeObjectForKey:@"spatial"];
			_undoManager	= [coder decodeObjectForKey:@"undoManager"];

			_undoManager.delegate = self;

			[self setupPeriodicSaveTimer];

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
	[_nodes setObject:node forKey:node.ident];
}
-(void)copyWay:(OsmWay *)way
{
	[_ways setObject:way forKey:way.ident];
	for ( OsmNode * node in way.nodes ) {
		[self copyNode:node];
	}
}
-(void)copyRelation:(OsmRelation *)relation
{
	[_relations setObject:relation forKey:relation.ident];
#if USE_SQL
	// don't copy member objects
#else
	for ( OsmMember * member in relation.members ) {
		if ( [member.ref isKindOfClass:[NSNumber class]] )
			continue;
		if ( member.isNode ) {
			[self copyNode:member.ref];
		} else if ( member.isWay ) {
			[self copyWay:member.ref];
		} else if ( member.isRelation ) {
			[self copyRelation:member.ref];
		} else {
			assert(NO);
		}
	}
#endif
}
-(OsmMapData *)modifiedObjects
{
	// get modified nodes and ways
	OsmMapData * modified = [[OsmMapData alloc] init];

	[_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmNode * object, BOOL *stop) {
		if ( object.deleted ? object.ident.longLongValue > 0 : object.isModified ) {
			[modified copyNode:object];
		}
	}];
	[_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmWay * object, BOOL *stop) {
		if ( object.deleted ? object.ident.longLongValue > 0 : object.isModified ) {
			[modified copyWay:object];
		}
	}];
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmRelation * object, BOOL *stop) {
		if ( object.deleted ? object.ident.longLongValue > 0 : object.isModified ) {
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
#if USE_SQL
	Database * db = [Database new];
	[db dropTables];
#endif
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
			[dirty addObjectsFromArray:((OsmWay *)object).nodes];
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

	// purge everything
	[self purgeExceptUndo];

	// put dirty stuff back in
	for ( OsmBaseObject * object in dirty ) {

		if ( [object isKindOfClass:[OsmBaseObject class]] ) {

			if ( object.isNode ) {
				[_nodes setObject:object forKey:object.ident];
			} else if ( object.isWay ) {
				[_ways setObject:object forKey:object.ident];
			} else if ( object.isRelation ) {
				[_relations setObject:object forKey:object.ident];
			} else {
				assert(NO);
			}
			if ( !object.deleted ) {
				[_spatial addMember:object undo:nil];
			}

		} else {
			// ignore
		}
	}
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
	if ( [object isKindOfClass:[EditorMapLayer class]] ) {
		DbgAssert( g_EditorMapLayerForArchive );
		return g_EditorMapLayerForArchive;
	}
	return object;
}


-(BOOL)saveArchive
{
	NSString * path = [self pathToArchiveFile];

	NSMutableData * data = [NSMutableData data];
	NSKeyedArchiver * archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	archiver.delegate = self;
	[archiver encodeObject:self forKey:@"OsmMapData"];
	[archiver finishEncoding];
	[data writeToFile:path atomically:YES];

	BOOL ok = data  &&  [data writeToFile:path atomically:YES];
	return ok;
}

-(void)sqlSaveNodes:(NSArray *)saveNodes saveWays:(NSArray *)saveWays saveRelations:(NSArray *)saveRelations
		deleteNodes:(NSArray *)deleteNodes deleteWays:(NSArray *)deleteWays deleteRelations:(NSArray *)deleteRelations
		   isUpdate:(BOOL)isUpdate
{
#if USE_SQL
	if ( saveNodes.count == 0 && saveWays.count == 0 && deleteNodes.count == 0 && deleteWays.count == 0 )
		return;
	CFTimeInterval t = CACurrentMediaTime();
	Database * db = [Database new];
	[db createTables];
	[db saveNodes:saveNodes saveWays:saveWays saveRelations:saveRelations deleteNodes:deleteNodes deleteWays:deleteWays deleteRelations:deleteRelations isUpdate:isUpdate];
	t = CACurrentMediaTime() - t;
	DLog(@"sql save %ld nodes, %ld ways, time = %f", (long)saveNodes.count, (long)saveWays.count, t);
	[self save];
#endif
}

-(void)updateSql:(NSDictionary *)sqlUpdate isUpdate:(BOOL)isUpdate
{
	NSMutableArray * insertNode		= [NSMutableArray new];
	NSMutableArray * insertWay		= [NSMutableArray new];
	NSMutableArray * insertRelation	= [NSMutableArray new];
	NSMutableArray * deleteNode		= [NSMutableArray new];
	NSMutableArray * deleteWay		= [NSMutableArray new];
	NSMutableArray * deleteRelation	= [NSMutableArray new];
	[sqlUpdate enumerateKeysAndObjectsUsingBlock:^(OsmBaseObject * object, NSNumber * insert, BOOL *stop) {
		if ( object.isNode ) {
			if ( insert.boolValue )
				[insertNode addObject:object];
			else
				[deleteNode addObject:object];
		} else if ( object.isWay ) {
			if ( insert.boolValue )
				[insertWay addObject:object];
			else
				[deleteWay addObject:object];
		} else if ( object.isRelation ) {
			if ( insert.boolValue )
				[insertRelation addObject:object];
			else
				[deleteRelation addObject:object];
		} else {
			assert(NO);
		}
	}];
	[self sqlSaveNodes:insertNode saveWays:insertWay saveRelations:insertRelation deleteNodes:deleteNode deleteWays:deleteWay deleteRelations:deleteRelation isUpdate:isUpdate];
}


-(void)save
{
	CFTimeInterval t = CACurrentMediaTime();
#if USE_SQL
	// save dirty data and relations
	DbgAssert(g_EditorMapLayerForArchive);
	OsmMapData * modified = [self modifiedObjects];
	modified->_region = _region;
	QuadBox * root = _spatial.rootQuad;
	modified->_spatial = _spatial;
	_spatial.rootQuad = nil;
	[modified saveArchive];
	_spatial.rootQuad = root;
#else
	// First save just modified objects, which we can do very fast, in case we get killed during full save
	OsmMapData * modified = [self modifiedObjects];
	modified->_region = nil;	// don't preserve regions because we will need to reload all data
	QuadBox * root = _spatial.rootQuad;
	modified->_spatial = _spatial;
	_spatial.rootQuad = nil;
	[modified saveArchive];
	_spatial.rootQuad = root;

	// Next try to save everything. Since we save atomically this won't overwrite the fast save unless it succeeeds.
	[self saveArchive];
#endif
	t = CACurrentMediaTime() - t;
	DLog(@"archive save %ld,%ld,%ld,%ld,%ld = %f", (long)modified.nodeCount, (long)modified.wayCount, (long)modified.relationCount, (long)_undoManager.count, (long)_region.count, t);

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
	@try {
		NSKeyedUnarchiver * unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
		unarchiver.delegate = self;
		self = [unarchiver decodeObjectForKey:@"OsmMapData"];
#if USE_SQL
		if ( self ) {
			// rebuild spatial database
			_spatial.rootQuad = [QuadBox new];
			[self enumerateObjectsUsingBlock:^(OsmBaseObject *obj) {
				if ( !obj.deleted )
					[_spatial addMember:obj undo:nil];
			}];

			// merge info from SQL database
			Database * db = [Database new];
			NSMutableDictionary * newNodes		= [db querySqliteNodes];
			NSMutableDictionary * newWays		= [db querySqliteWays];
			NSMutableDictionary * newRelations	= [db querySqliteRelations];

			OsmMapData * newData = [[OsmMapData alloc] init];
			newData->_nodes = newNodes;
			newData->_ways = newWays;
			newData->_relations = newRelations;
			[self merge:newData fromDownload:NO quadList:nil success:YES];
		}
#else
		if ( self ) {
			// convert relation members from ids back into objects
			[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * ident, OsmRelation * relation, BOOL *stop) {
				[relation resolveToMapData:self];
			}];
		}
#endif
	}
	@catch (id exception) {
		self = nil;
	}

	return self;
}

@end
