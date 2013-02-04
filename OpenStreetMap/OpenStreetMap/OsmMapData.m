//
//  XmlParserDelegate.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <sqlite3.h>

#if TARGET_OS_IPHONE
#import "DDXML.h"
#import "../OSMiOS/OSMiOS/AppDelegate.h"
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


static const OSMRect MAP_RECT = { -180, -90, 360, 180 };


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

-(id)init
{
	self = [super init];
	if ( self ) {
		_parserStack	= [NSMutableArray arrayWithCapacity:20];
		_nodes			= [NSMutableDictionary dictionaryWithCapacity:1000];
		_ways			= [NSMutableDictionary dictionaryWithCapacity:1000];
		_relations		= [NSMutableDictionary dictionaryWithCapacity:10];
		_region			= [[QuadMap alloc] initWithRect:MAP_RECT];
		_spatial		= [[QuadBox alloc] initWithRect:MAP_RECT parent:nil];
		_undoManager	= [UndoManager new];
	}
	return self;
}


-(OSMRect)rootRect
{
	return _spatial.rect;
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
	[_spatial findObjectsInArea:bbox block:^(NSArray * a){
		for ( OsmBaseObject * o in a ) {
			if ( [o intersectsBox:bbox] ) {
				block( o );
			}
		}
	}];
}


-(NSArray *)relationsForObject:(OsmBaseObject *)object
{
	__block NSMutableArray * a = nil;
	[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key, OsmRelation * relation, BOOL *stop) {
		for ( OsmMember * member in relation.members ) {
			if ( member.ref == object ) {
				if ( a == nil )
					a = [NSMutableArray arrayWithObject:relation];
				else
					[a addObject:relation];
				return;
			}
#if 1
			if ( [member.ref isKindOfClass:[NSNumber class]] ) {
				NSNumber * ident = member.ref;
				if ( ident.longLongValue == object.ident.longLongValue ) {
					assert(NO);
				}
			}
#endif
		}
	}];
	return a;
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
	return set;
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

	[_undoManager registerUndoComment:@"set tags"];
	[object setTags:dict undo:_undoManager];
}

-(OsmNode *)createNodeAtLocation:(CLLocationCoordinate2D)loc
{
	OsmNode * node = [OsmNode new];
	[node constructAsUserCreated];
	[node setLongitude:loc.longitude latitude:loc.latitude undo:nil];
	[node setDeleted:YES undo:nil];
	[self setConstructed:node];
	[_nodes setObject:node forKey:node.ident];
	
	[_undoManager registerUndoComment:@"create node"];
	[node setDeleted:NO undo:_undoManager];
	[_spatial addMember:node undo:_undoManager];
	return node;
}

-(OsmWay *)createWay
{
	OsmWay * way = [OsmWay new];
	[way constructAsUserCreated];
	[way setDeleted:YES undo:nil];
	[self setConstructed:way];
	[_ways setObject:way forKey:way.ident];

	[_undoManager registerUndoComment:@"create way"];
	[way setDeleted:NO undo:_undoManager];
	[_spatial addMember:way undo:_undoManager];
	return way;
}


-(void)deleteNode:(OsmNode *)node
{
	assert( node.wayCount == 0 );
	[_undoManager registerUndoComment:@"delete node"];
	[node setDeleted:YES undo:_undoManager];
	[_spatial removeMember:node undo:_undoManager];
}

-(void)deleteWay:(OsmWay *)way
{
	[_undoManager registerUndoComment:@"delete way"];
#if 1
	while ( way.nodes.count ) {
		[self deleteNodeInWay:way index:0];
	}
#endif
	[way setDeleted:YES undo:_undoManager];
	[_spatial removeMember:way undo:_undoManager];
}

-(void)addNode:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index
{
	[_undoManager registerUndoComment:@"add node to way"];
	[_spatial removeMember:way undo:_undoManager];
	[way addNode:node atIndex:index undo:_undoManager];
	[_spatial addMember:way undo:_undoManager];
}
-(void)deleteNodeInWay:(OsmWay *)way index:(NSInteger)index
{
	[_undoManager registerUndoComment:@"delete node from way"];
	OsmNode * node = way.nodes[ index ];
	assert( node.wayCount > 0 );

	[_spatial removeMember:way undo:_undoManager];
	[way removeNodeAtIndex:index undo:_undoManager];
	[_spatial addMember:way undo:_undoManager];

	if ( node.wayCount == 0 ) {
		[self deleteNode:node];
	}
}
-(void)setLongitude:(double)longitude latitude:(double)latitude forNode:(OsmNode *)node inWay:(OsmWay *)way
{
	[_undoManager registerUndoComment:@"move"];
	[_spatial removeMember:node undo:_undoManager];
	if ( way ) {
		[self incrementModifyCount:way];
	}
	[node setLongitude:longitude latitude:latitude undo:_undoManager];
	[_spatial addMember:node undo:_undoManager];
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
+ (void)osmDataForBox:(ServerQuery *)query completion:(void(^)(ServerQuery * query,OsmMapData * data,NSError * error))completion
{
	OSMRect box = query.rect;
	NSMutableString * url = [NSMutableString stringWithString:OSM_API_URL];
	[url appendFormat:@"api/0.6/map?bbox=%f,%f,%f,%f", box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height];

	[[DownloadThreadPool osmPool] streamForUrl:url callback:^(DownloadAgent * agent){

		if ( agent.stream.streamError ) {

			dispatch_async(dispatch_get_main_queue(), ^{
				completion( query, nil, agent.stream.streamError );
			});

		} else {
			OsmMapData * mapData = [[OsmMapData alloc] init];
			NSError * error = nil;
			BOOL ok = [mapData parseXmlStream:agent.stream error:&error];
			if ( !ok ) {
				if ( agent.dataHeader.length ) {
					// probably some html-encoded error message from the server
					NSString * s = [[NSString alloc] initWithBytes:agent.dataHeader.bytes length:agent.dataHeader.length encoding:NSUTF8StringEncoding];
					error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : s }];
				} else if ( agent.stream.streamError ) {
					error = agent.stream.streamError;
				} else if ( error ) {
					// use the parser's reported error
				} else {
					error = [[NSError alloc] initWithDomain:@"parser" code:100 userInfo:@{ NSLocalizedDescriptionKey : @"Parse error" }];
				}
			}
			if ( error ) {
				mapData = nil;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				completion( query, mapData, error );
			});
		}
	}];
}

- (void)updateWithBox:(OSMRect)box mapView:(MapView *)mapView completion:(void(^)(BOOL partial,NSError * error))completion
{
	__block int activeRequests = 0;

	void(^mergePartialResults)(ServerQuery * query,OsmMapData * mapData,NSError * error) = ^(ServerQuery * query,OsmMapData * mapData,NSError * error){
		[mapView progressDecrement];
		--activeRequests;
		//	DLog(@"merge %ld nodes, %ld ways", mapData.nodes.count, mapData.ways.count);
		[self merge:mapData quadList:query.quadList success:(mapData && error==nil)];
		completion( activeRequests > 0, error );
	};

	// get list of new quads to fetch
	NSArray * newQuads = [_region newQuadsForRect:box];

	// check how much area we're trying to download, and if too large complain
	NSError * error = nil;
	double area = 0.0;
	for ( QuadBox * box in newQuads ) {
		area += box.rect.size.width * box.rect.size.height;
	}
	if ( area > 0.25 ) {
		error = [NSError errorWithDomain:@"Network" code:1 userInfo:@{ NSLocalizedDescriptionKey : @"The area for which you are attempting to download data is too large. Please zoom in or hide the Editor layer under Settings" }];
		newQuads = nil;
	}

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

		double lat	= [[attributeDict valueForKey:@"lat"] doubleValue];
		double lon	= [[attributeDict valueForKey:@"lon"] doubleValue];
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
		
		NSString * key		= [attributeDict valueForKey:@"k"];
		NSString * value	= [attributeDict valueForKey:@"v"];
		assert( key && value );
		OsmBaseObject * object = _parserStack.lastObject;
		[object constructTag:key value:value];
		[_parserStack addObject:@"tag"];
		
	} else if ( [elementName isEqualToString:@"nd"] ) {

		OsmWay * way = [_parserStack lastObject];
		NSString * ref = [attributeDict valueForKey:@"ref"];
		assert( ref );
		[way constructNode:@(ref.longLongValue)];
		[_parserStack addObject:@"nd"];

	} else if ( [elementName isEqualToString:@"relation"] ) {

		OsmRelation * relation = [OsmRelation new];
		[relation constructBaseAttributesFromXmlDict:attributeDict];

		[_relations setObject:relation forKey:relation.ident];
		[_parserStack addObject:relation];

	} else if ( [elementName isEqualToString:@"member"] ) {

		NSString *	type = [attributeDict valueForKey:@"type"];
		NSNumber *	ref  = @([[attributeDict valueForKey:@"ref"] longLongValue]);
		NSString *	role = [attributeDict valueForKey:@"role"];

		OsmMember * member = [[OsmMember alloc] initWithType:type ref:ref role:role];

		OsmRelation * relation = [_parserStack lastObject];
		[relation constructMember:member];
		[_parserStack addObject:member];

	} else if ( [elementName isEqualToString:@"osm"] ) {

		// osm header
		NSString * version		= [attributeDict valueForKey:@"version"];
#if 0
		NSString * generator	= [attributeDict valueForKey:@"generator"];
		NSString * copyright	= [attributeDict valueForKey:@"copyright"];
		NSString * attribution	= [attributeDict valueForKey:@"attribution"];
		NSString * license		= [attributeDict valueForKey:@"license"];
		assert( version && generator && copyright && attribution && license);
#endif
		assert( [version isEqualToString:@"0.6"] );
		[_parserStack addObject:@"osm"];

	} else if ( [elementName isEqualToString:@"bounds"] ) {
#if 0
		double minLat = [[attributeDict valueForKey:@"minlat"] doubleValue];
		double minLon = [[attributeDict valueForKey:@"minlon"] doubleValue];
		double maxLat = [[attributeDict valueForKey:@"maxlat"] doubleValue];
		double maxLon = [[attributeDict valueForKey:@"maxlon"] doubleValue];
#endif
		[_parserStack addObject:@"bounds"];
		
	} else {

		DLog(@"OSM parser: Unknown tag '%@'", elementName);
		_parseError = [[NSError alloc] initWithDomain:@"Parser" code:102 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"OSM parser: Unknown tag '%@'", elementName]}];
		[parser abortParsing];
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
	assert( _parserStack.count == 0 );
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
	}

	return ok;
}


- (void)merge:(OsmMapData *)newData quadList:(NSArray *)quadList success:(BOOL)success
{
	if ( newData ) {
		[newData->_nodes enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmNode * node,BOOL * stop){
			if ( [_nodes objectForKey:key] == nil ) {
				[_nodes setObject:node forKey:key];
				[_spatial addMember:node undo:nil];
			}
		}];
		[newData->_ways enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmWay * way,BOOL * stop){
			if ( [_ways objectForKey:key] == nil ) {
				[_ways setObject:way forKey:key];
				[way resolveToMapData:self];
				[_spatial addMember:way undo:nil];
			}
		}];
		[newData->_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmRelation * relation,BOOL * stop){
			if ( [_relations objectForKey:key] == nil ) {
				[_relations setObject:relation forKey:key];
				[_spatial addMember:relation undo:nil];
			}
		}];
		// all relations, including old ones, need to be resolved against new objects
		[_relations enumerateKeysAndObjectsUsingBlock:^(NSNumber * key,OsmRelation * relation,BOOL * stop){
			[relation resolveToMapData:self];
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
	}

	for ( QuadBox * q in quadList ) {
		[_region makeWhole:q success:success];
	}
}

#pragma mark Upload

-(void) updateObjectDictionary:(NSMutableDictionary *)dictionary oldId:(OsmIdentifier)oldId  newId:(OsmIdentifier)newId version:(NSInteger)newVersion
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
		return;
	}

	assert( newVersion > 0 );
	[object serverUpdateVersion:newVersion];

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
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]];
	[request setHTTPMethod:method];
	if ( xml ) {
		NSData * data = [xml XMLDataWithOptions:0];
		[request setHTTPBody:data];
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


+(NSXMLElement *)elementForObject:(OsmBaseObject *)object changeset:(NSString *)changeset
{
	NSString * type =	object.isNode		? @"node" :
						object.isWay		? @"way" :
						object.isRelation	? @"relation" :
						nil;
	assert(type);

	NSXMLElement * element = [NSXMLNode elementWithName:type];
	[element addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:object.ident.stringValue]];
	[element addAttribute:[NSXMLNode attributeWithName:@"timestamp" stringValue:object.timestamp]];
	if ( changeset.length )
		[element addAttribute:[NSXMLNode attributeWithName:@"changeset" stringValue:changeset]];
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

- (NSXMLDocument *)createXmlWithChangeset:(NSString *)changeset
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
			NSXMLElement * element = [OsmMapData elementForObject:node changeset:changeset];
			[deleteNodeElement addChild:element];
		} else if ( node.isModified && !node.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:node changeset:changeset];
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
			NSXMLElement * element = [OsmMapData elementForObject:way changeset:changeset];
			[deleteWayElement addChild:element];
			for ( OsmNode * node in way.nodes ) {
				NSXMLElement * element = [OsmMapData elementForObject:node changeset:changeset];
				[deleteWayElement addChild:element];
			}
		} else if ( way.isModified && !way.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:way changeset:changeset];
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
			NSXMLElement * element = [OsmMapData elementForObject:relation changeset:changeset];
			[deleteRelationElement addChild:element];
		} else if ( relation.isModified && !relation.deleted ) {
			// added/modified
			NSXMLElement * element = [OsmMapData elementForObject:relation changeset:changeset];
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


- (void)uploadChangeset:(NSString *)comment completion:(void(^)(NSString * errorMessage))completion
{
#if TARGET_OS_IPHONE
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
#else
	AppDelegate * appDelegate = [[NSApplication sharedApplication] delegate];
#endif

	NSString * creator = [NSString stringWithFormat:@"%@ %@", appDelegate.appName, appDelegate.appVersion];
	
	NSXMLDocument * xmlCreate = [OsmMapData createXmlWithType:@"changeset" tags:@{
									@"created_by" : creator,
									@"comment" : comment
								 }];
	NSString * url = [OSM_API_URL stringByAppendingString:@"api/0.6/changeset/create"];

	[self putRequest:url method:@"PUT" xml:xmlCreate completion:^(NSData * data,NSString * errorMessage){
		if ( data ) {
			NSString * changesetID = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
			DLog(@"changeset ID = %@",changesetID);

			NSXMLDocument * xmlChanges = [self createXmlWithChangeset:changesetID];
			DLog(@"change XML = %@",xmlChanges);
			if ( xmlChanges == nil ) {
				completion( @"No changes to apply" );
				return;
			}

			NSString * url2 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/changeset/%@/upload", changesetID];
			[self putRequest:url2 method:@"POST" xml:xmlChanges completion:^(NSData *data,NSString * errorMessage) {
				NSString * response = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
				DLog(@"upload response = %@",response);

				if ( ![response hasPrefix:@"<?xml"] ) {
					completion( errorMessage ?: response );
					return;
				}

				NSError * error = nil;
				NSXMLDocument * diffDoc = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
				if ( error ) {
					completion( error.localizedDescription );
					return;
				}

				for ( NSXMLElement * element in diffDoc.rootElement.children ) {
					NSString * name			= element.name;
					NSString * oldId		= [element attributeForName:@"old_id"].stringValue;
					NSString * newId		= [element attributeForName:@"new_id"].stringValue;
					NSString * newVersion	= [element attributeForName:@"new_version"].stringValue;
					if ( [name isEqualToString:@"node"] ) {
						[self updateObjectDictionary:_nodes oldId:oldId.longLongValue newId:newId.longLongValue version:newVersion.integerValue];
					} else if ( [name isEqualToString:@"way"] ) {
						[self updateObjectDictionary:_ways oldId:oldId.longLongValue newId:newId.longLongValue version:newVersion.integerValue];
					} else if ( [name isEqualToString:@"relation"] ) {
						[self updateObjectDictionary:_relations oldId:oldId.longLongValue newId:newId.longLongValue version:newVersion.integerValue];
					} else {
						assert(NO);
					}
				}

				NSString * url3 = [OSM_API_URL stringByAppendingFormat:@"api/0.6/changeset/%@/close", changesetID];
				[self putRequest:url3 method:@"PUT" xml:nil completion:^(NSData *data,NSString * errorMessage) {
					if ( errorMessage )
						errorMessage = [errorMessage stringByAppendingString:@" (ignored, changes already committed)"];
					completion(errorMessage);
					DLog(@"changeset closed");
				}];

				// reset undo stack after upload so user can't accidently undo a commit (wouldn't work anyhow because we don't undo version numbers on objects)
				[_undoManager removeAllActions];
			}];

		} else {
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

-(void)updateString:(NSMutableAttributedString *)string withNode:(NSXMLElement *)node
{
	NSFont * font = [NSFont fontWithName:@"Helvetica" size:14];
	NSString * lat = [node attributeForName:@"lat"].stringValue;
	NSString * lon = [node attributeForName:@"lon"].stringValue;
	NSString * text = lat && lon
	? [NSString stringWithFormat:@"\tNode %@ (%.6f,%.6f)\n", [node attributeForName:@"id"].stringValue, lat.doubleValue, lon.doubleValue]
	: [NSString stringWithFormat:@"\tNode %@\n", [node attributeForName:@"id"].stringValue];
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
	NSString * text = [NSString stringWithFormat:@"\tWay %@ (%d entries)\n",
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
		} else {
			assert(NO);
		}
	}
}

-(NSAttributedString *)changesetAsAttributedString
{
	NSXMLDocument * doc = [self createXmlWithChangeset:@"0"];
	if ( doc == nil )
		return nil;
	NSMutableAttributedString * string = [NSMutableAttributedString new];
	NSXMLElement * root = [doc rootElement];

	NSArray * deletes = [root elementsForName:@"delete"];
	NSArray * creates = [root elementsForName:@"create"];
	NSArray * modifys = [root elementsForName:@"modify"];
	for ( NSXMLElement * delete in deletes ) {
		[self updateString:string withHeader:@"Delete\n" objects:delete.children];
	}
	for ( NSXMLElement * create in creates ) {
		[self updateString:string withHeader:@"Create\n" objects:create.children];
	}
	for ( NSXMLElement * modify in modifys ) {
		[self updateString:string withHeader:@"Modify\n" objects:modify.children];
	}
	return string;
}

- (NSString *)changesetAsXml
{
	NSXMLDocument * xml = [self createXmlWithChangeset:@""];
	if ( xml == nil )
		return nil;
	return xml.XMLString;
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
#if 0
	DLog(@"%ld nodes", (long)_nodes.count);
	DLog(@"%ld ways", (long)_ways.count);
	DLog(@"%ld relations", (long)_relations.count);
	DLog(@"%ld regions", (long)_region.count);
	DLog(@"%ld spatial quads", (long)_spatial.quadCount);
	DLog(@"%ld spatial members", (long)_spatial.memberCount);
#endif

	if ( [coder allowsKeyedCoding] ) {
		[coder encodeObject:_nodes			forKey:@"nodes"];
		[coder encodeObject:_ways			forKey:@"ways"];
		[coder encodeObject:_relations		forKey:@"relations"];
		[coder encodeObject:_region			forKey:@"region"];
		[coder encodeObject:_spatial		forKey:@"spatial"];
		[coder encodeObject:_undoManager	forKey:@"undoManager"];
	} else {
		[coder encodeObject:_nodes];
		[coder encodeObject:_ways];
		[coder encodeObject:_relations];
		[coder encodeObject:_region];
		[coder encodeObject:_spatial];
		[coder encodeObject:_undoManager];
	}
#if 0
	DLog(@"nodes     = %f", [s2 timeIntervalSinceDate:s1]);
	DLog(@"ways      = %f", [s3 timeIntervalSinceDate:s2]);
	DLog(@"relations = %f", [s4 timeIntervalSinceDate:s3]);
	DLog(@"regions   = %f", [s5 timeIntervalSinceDate:s4]);
	DLog(@"spatial   = %f", [s6 timeIntervalSinceDate:s5]);
	DLog(@"undo      = %f", [s7 timeIntervalSinceDate:s6]);
#endif
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {

		@try {
			if ( [coder allowsKeyedCoding] ) {
				_nodes			= [coder decodeObjectForKey:@"nodes"];
				_ways			= [coder decodeObjectForKey:@"ways"];
				_relations		= [coder decodeObjectForKey:@"relations"];
				_region			= [coder decodeObjectForKey:@"region"];
				_spatial		= [coder decodeObjectForKey:@"spatial"];
				_undoManager	= [coder decodeObjectForKey:@"undoManager"];
			} else {
				_nodes			= [coder decodeObject];
				_ways			= [coder decodeObject];
				_relations		= [coder decodeObject];
				_region			= [coder decodeObject];
				_spatial		= [coder decodeObject];
				_undoManager	= [coder decodeObject];
			}
			if ( (_nodes.count == 0 && _ways.count == 0 && _relations.count == 0) || _undoManager == nil ) {
				self = nil;
			} else {
				if ( _region == nil ) {
					_region	= [[QuadMap alloc] initWithRect:MAP_RECT];

					// didn't save spatial, so add everything back into it
					[_nodes enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * object, BOOL *stop) {
						[_spatial addMember:object undo:nil];
					}];
					[_ways enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * object, BOOL *stop) {
						[_spatial addMember:object undo:nil];
					}];
					[_relations enumerateKeysAndObjectsUsingBlock:^(id key, OsmBaseObject * object, BOOL *stop) {
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
}
-(OsmMapData *)modifiedObjects
{
	// get modified nodes and ways
	OsmMapData * modified = [[OsmMapData alloc] init];
	// we don't preserve any regions
	modified->_region = nil;

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
			[self copyRelation:object];
		}
	}];
	NSArray * undoObjects = [_undoManager objectRefs];
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
	[_spatial reset];
	_region  = [[QuadMap alloc] initWithRect:MAP_RECT];
}

-(void)purgeHard
{
	[self purgeExceptUndo];
	[_undoManager removeAllActions];
}

-(void)purgeSoft
{
	// get a list of all dirty objects
	NSMutableArray * dirty = [NSMutableArray new];
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
	NSArray * undoRefs = [_undoManager objectRefs];
	[dirty addObjectsFromArray:undoRefs];

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
			[_spatial addMember:object undo:nil];

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

- (id)archiver:(NSKeyedArchiver *)archiver willEncodeObject:(id)object
{
	// when saving a copy of modification the undo manager will try to save _spatial, but we need to save our (empty) copy instead
	if ( _substSpatialOnSave && [object isKindOfClass:[QuadBox class]] ) {
		return _spatial;
	}
	return object;
}

-(BOOL)saveSubstitutingSpatial:(BOOL)substituteSpatial
{
	_substSpatialOnSave = substituteSpatial;

	NSDate * startDate = [NSDate date];
	NSString * path = [self pathToArchiveFile];

	NSMutableData * data = [NSMutableData data];
	NSKeyedArchiver * archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
	archiver.delegate = self;
	[archiver encodeObject:self forKey:@"OsmMapData"];
	[archiver finishEncoding];
	[data writeToFile:path atomically:YES];

	DLog( @"%f seconds to archive", [[NSDate date] timeIntervalSinceDate:startDate] );
	DLog( @"%f MB", data.length * 1e-6);
	startDate = [NSDate date];
	BOOL ok = data  &&  [data writeToFile:path atomically:YES];
	DLog( @"%f seconds to write", [[NSDate date] timeIntervalSinceDate:startDate] );
	DLog(@"map data = %f MB", (double)data.length/(1024*1024));
	return ok;
}
-(id)initWithCachedData
{
	NSString * path = [self pathToArchiveFile];
	NSData * data = [NSData dataWithContentsOfFile:path];
	NSKeyedUnarchiver * unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
	self = [unarchiver decodeObjectForKey:@"OsmMapData"];
	return self;
}



#if 0
-(BOOL)saveSqlite
{
	NSString * path = @"data.sqlite3";
	sqlite3 * db = NULL;
	int rc = sqlite3_open_v2( path.UTF8String, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL );
	if ( rc ) {
		return NO;
	}

    sqlite3_stmt *statement;
	rc = sqlite3_prepare_v2( db, "SELECT k,v,line_color,line_width,area_color FROM josm_style_rules", -1, &statement, nil );
    assert(rc == SQLITE_OK);
	while ( sqlite3_step(statement) == SQLITE_ROW )  {
		const char * szKey			= (char *)sqlite3_column_text(statement, 0);
		const char * szValue		= (char *)sqlite3_column_text(statement, 1);
		const char * szLineColor	= (char *)sqlite3_column_text(statement, 2);
		const char * szLineWidth	= (char *)sqlite3_column_text(statement, 3);
		const char * szAreaColor	= (char *)sqlite3_column_text(statement, 4);
	}
	sqlite3_finalize(statement);
	sqlite3_close(db);
}
#endif


-(NSArray *)userStatisticsForRegion:(OSMRect)rect
{
	NSMutableDictionary * dict = [NSMutableDictionary dictionary];

	[self enumerateObjectsInRegion:rect block:^(OsmBaseObject * base) {
		NSDate * date = [base dateForTimestamp];
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


#if 0

+(BOOL)splitWay:(OsmWay	*)selectedWay node:(NSInteger)nodeIndex
{
	OsmWay *	newWay = nil;

	// we reverse the list, which is already sorted by position. This way positions aren't affected
	// for previous inserts when all the inserts are eventually executed
	for ( OsmRelation * o in selectedWay.memberships.reverse() ) {

		// don't add a turn restriction to the relation if it's no longer relevant
		if ( o.relation.tagIs('type','restriction')) {
			NSArray * vias = o.relation.findMembersByRole('via');
			if ( vias.count && [vias[0] isKindOfClass:[OsmNode class] ) {
				if (newWay.indexOfNode(Node(vias[0]))==-1) {
					continue;
				}
			}
								}

								// newWay should be added immediately after the selectedWay, unless the setup
								// is arse-backwards. By that I mean either:
								// a) The first node (0) of selectedWay is in the subsequentWay, or
								// b) The last node (N) of selectedWay is in the preceedingWay
								// Note that the code above means newWay is the tail of selectedWay S-->.-->N
								// i.e. preceedingWay x--x--x--x                             P-1   ↓
								//      selectedWay            N<--.<--S<--.<--0             P     ↓ relation members list
								//      subsequentWay                           x--x--x--x   P+1   ↓
								// There are some edge cases:
								// 1) If the immediately adjacent member isn't a way - handled fine
								// 2) If the selectedWay shares first/last node with non-adjacent ways - phooey

								BOOL backwards = NO;
								// note that backwards is actually a ternary of 'true', 'false', and 'itdoesntmatter' (== 'false')

								NSInteger offset = 1; //work from o.position outwards along the length of the relationmembers
								while ((o.position - offset) >= 0 || (o.position + offset < o.relation.length)) {
									if ((o.position - offset >= 0) && o.relation.getMember(o.position - offset).entity is Way)  {
										var preceedingWay:Way = o.relation.getMember(o.position - offset).entity as Way;
										if ( preceedingWay.indexOfNode(selectedWay.getLastNode()) >= 0) {
											backwards = true;
										}
									}
									if ((o.position + offset < o.relation.length) && o.relation.getMember(o.position + offset).entity is Way) {
										OsmWay * subsequentWay = (id) o.relation.getMember(o.position + offset).entity;
										if ( subsequentWay.indexOfNode(selectedWay.getNode(0)) >= 0) {
											backwards = true;
										}
									}
									offset++;
								}
								if (backwards) {
									o.relation.insertMember(o.position, new RelationMember(newWay, o.role), push); //insert newWay before selectedWay
								} else {
									o.relation.insertMember(o.position + 1, new RelationMember(newWay, o.role), push); // insert after
								}
								}

								// now that we're done with the selectedWay, remove the nodes
								selectedWay.deleteNodesFrom(nodeIndex+1, push);

								// and remove from any turn restrictions that aren't relevant
								for ( OsmRelation * r in selectedWay.findParentRelationsOfType('restriction')) {
									NSArray * vias = r.findMembersByRole('via');
									if ( vias.count && vias[0] is Node ) {
										if (selectedWay.indexOfNode(Node(vias[0]))==-1) {
											r.removeMember(selectedWay,push);
										}
									}
								}
								
								return YES;
								}
#endif


@end
