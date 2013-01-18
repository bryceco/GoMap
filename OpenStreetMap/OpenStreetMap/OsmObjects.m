//
//  OsmObjects.m
//  OpenStreetMap
//
//  Created by Bryce on 10/27/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "iosapi.h"
#import "CurvedTextLayer.h"
#import "OsmObjects.h"
#import "OsmMapData.h"
#import "UndoManager.h"




BOOL OsmBooleanForValue( NSString * value )
{
	if ( [value isEqualToString:@"true"] )
		return YES;
	if ( [value isEqualToString:@"false"] )
		return NO;
	if ( [value isEqualToString:@"yes"] )
		return YES;
	if ( [value isEqualToString:@"no"] )
		return NO;
	if ( [value isEqualToString:@"1"] )
		return YES;
	if ( [value isEqualToString:@"0"] )
		return NO;
	assert(NO);
	return NO;
}
NSString * OsmValueForBoolean( BOOL b )
{
	return b ? @"true" : @"false";
}

#pragma mark OsmBaseObject


@implementation OsmBaseObject
@synthesize deleted = _deleted;
@synthesize tags = _tags;
@synthesize modifyCount = _modifyCount;
@synthesize ident = _ident;

-(BOOL)isNode
{
	return NO;
}
-(BOOL)isWay
{
	return NO;
}
-(BOOL)isRelation
{
	return NO;
}
-(OSMRect)boundingBox
{
	assert(NO);
	return OSMRectMake(0, 0, 0, 0);
}


static NSInteger _nextUnusedIdentifier = 0;

+(NSInteger)nextUnusedIdentifier
{
	if ( _nextUnusedIdentifier == 0 ) {
		_nextUnusedIdentifier = [[NSUserDefaults standardUserDefaults] integerForKey:@"nextUnusedIdentifier"];
	}
	--_nextUnusedIdentifier;
	[[NSUserDefaults standardUserDefaults] setInteger:_nextUnusedIdentifier forKey:@"nextUnusedIdentifier"];
	return _nextUnusedIdentifier;
}

#pragma mark Construction

-(void)constructBaseAttributesFromXmlDict:(NSDictionary *)attributeDict
{
	assert( !_constructed );
	_version	= (int32_t) [[attributeDict valueForKey:@"version"] integerValue];
	_changeset	= [[attributeDict valueForKey:@"changeset"] longLongValue];
	_user		= [attributeDict valueForKey:@"user"];
	_uid		= (int32_t) [[attributeDict valueForKey:@"uid"] integerValue];
	NSString * isVisible = [attributeDict valueForKey:@"visible"];
	_visible	= OsmBooleanForValue(isVisible);
	_ident		= @([[attributeDict valueForKey:@"id"] longLongValue]);
	_timestamp	= [attributeDict valueForKey:@"timestamp"];
}

-(void)constructTag:(NSString *)tag value:(NSString *)value
{
	// drop deprecated tags
	if ( [tag isEqualToString:@"created_by"] )
		return;

	assert( !_constructed );
	if ( _tags == nil ) {
		_tags = [NSMutableDictionary dictionaryWithObject:value forKey:tag];
	} else {
		[((NSMutableDictionary *)_tags) setValue:value forKey:tag];
	}
}

-(BOOL)constructed
{
	return _constructed;
}
-(void)setConstructed
{
	_constructed = YES;
	_modifyCount = 0;
}

+(NSDateFormatter *)rfc3339DateFormatter
{
	static NSDateFormatter * rfc3339DateFormatter = nil;
	if ( rfc3339DateFormatter == nil ) {
		rfc3339DateFormatter = [[NSDateFormatter alloc] init];
		assert(rfc3339DateFormatter != nil);
		NSLocale * enUSPOSIXLocale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		assert(enUSPOSIXLocale != nil);
		[rfc3339DateFormatter setLocale:enUSPOSIXLocale];
		[rfc3339DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'"];
		[rfc3339DateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	}
	return rfc3339DateFormatter;
}
-(NSDate *)dateForTimestamp
{
	NSDate * date = [[OsmBaseObject rfc3339DateFormatter] dateFromString:_timestamp];
	assert(date);
	return date;
}
-(void)setTimestamp:(NSDate *)date undo:(UndoManager *)undo
{
	if ( _constructed ) {
		assert(undo);
		[undo registerUndoWithTarget:self selector:@selector(setTimestamp:undo:) objects:@[[self dateForTimestamp],undo]];
	}
	_timestamp = [[OsmBaseObject rfc3339DateFormatter] stringFromDate:date];
	assert(_timestamp);
}

-(BOOL)isModified
{
	return _modifyCount > 0;
}
-(void)incrementModifyCount:(UndoManager *)undo
{
	assert( _modifyCount >= 0 );
	if ( _constructed ) {
		assert(undo);
		// [undo registerUndoWithTarget:self selector:@selector(incrementModifyCount:) objects:@[undo]];
	}
	if ( undo.isUndoing )
		--_modifyCount;
	else
		++_modifyCount;
	assert( _modifyCount >= 0 );
}
-(void)resetModifyCount:(UndoManager *)undo
{
	assert(undo);
	_modifyCount = 0;
}

-(void)serverUpdateVersion:(NSInteger)version
{
	_version = (int32_t)version;
}
-(void)serverUpdateIdent:(OsmIdentifier)ident
{
	assert( _ident.longLongValue < 0 && ident > 0 );
	_ident = @(ident);
}



-(BOOL)deleted
{
	return _deleted;
}
-(void)setDeleted:(BOOL)deleted undo:(UndoManager *)undo
{
	if ( _constructed ) {
		assert(undo);
		[self incrementModifyCount:undo];
		[undo registerUndoWithTarget:self selector:@selector(setDeleted:undo:) objects:@[@((BOOL)self.deleted),undo]];
	}
	_deleted = deleted;
}


-(NSDictionary *)tags
{
	return _tags;
}
-(void)setTags:(NSDictionary *)tags undo:(UndoManager *)undo
{
	if ( _constructed ) {
		assert(undo);
		[self incrementModifyCount:undo];
		[undo registerUndoWithTarget:self selector:@selector(setTags:undo:) objects:@[_tags?:[NSNull null],undo]];
	}
	_tags = tags;
	_tagInfo = nil;
}

-(NSSet *)nodeSet
{
	assert(NO);
	return nil;
}
-(BOOL)intersectsBox:(OSMRect)box
{
	assert(NO);
	return NO;
}


-(NSString *)friendlyDescription
{
	static NSArray * typeList = nil;
	if ( typeList == nil ) {
		typeList = @[	@"shop", @"amenity", @"leisure", @"tourism", @"craft",
						@"highway", @"office", @"landmark", @"building", @"emergency",
						@"man_made", @"military", @"natural", @"power", @"railway",
						@"sport", @"waterway", @"aeroway", @"landuse", @"barrier", @"boundary" ];
	}

	NSString * name = [_tags valueForKey:@"name"];
	if ( name.length )
		return name;

	for ( NSString * type in typeList ) {
		name = [_tags objectForKey:type];
		if ( name.length ) {
			NSString * type2 = [type stringByReplacingOccurrencesOfString:@"_" withString:@" "];
			if ( [name isEqualToString:@"yes"] ) {
				return type2;
			}
			if ( [name isEqualToString:@"pitch"] && [type isEqualToString:@"leisure"] ) {
				NSString * sport = [_tags valueForKey:@"sport"];
				if ( sport.length ) {
					return [NSString stringWithFormat:@"%@ %@ (leisure)", sport, name];
				}
			}
			return [NSString stringWithFormat:@"%@ (%@)", type2, name];
		}
	}

	if ( [[_tags objectForKey:@"sidewalk"] isEqualToString:@"yes"] )
		return @"sidewalk";

	name = [_tags valueForKey:@"addr:housenumber"];
	if ( name ) {
		NSString * street = [_tags objectForKey:@"addr:street"];
		NSString * unit = [_tags objectForKey:@"addr:unit"];
		if ( unit )
			name = [NSString stringWithFormat:@"%@ %@",name, unit];
		if ( street )
			name = [NSString stringWithFormat:@"%@ %@",name, street];
		return name;
	}

	if ( self.isNode && ((OsmNode *)self).wayCount > 0 )
		return @"(node in way)";

	if ( self.isNode )
		return @"(node)";

	if ( self.isWay )
		return @"(way)";

	return @"other object";
}


- (id)copyWithZone:(NSZone *)zone
{
	return self;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_ident		forKey:@"ident"];
	[coder encodeObject:_user		forKey:@"user"];
	[coder encodeObject:_timestamp	forKey:@"timestamp"];
	[coder encodeInteger:_version	forKey:@"version"];
	[coder encodeInteger:_changeset	forKey:@"changeset"];
	[coder encodeInteger:_uid		forKey:@"uid"];
	[coder encodeBool:_visible		forKey:@"visible"];
	[coder encodeObject:_tags		forKey:@"tags"];
	[coder encodeBool:_deleted		forKey:@"deleted"];
	[coder encodeInt32:_modifyCount	forKey:@"modified"];
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_ident			= [coder decodeObjectForKey:@"ident"];
		_user			= [coder decodeObjectForKey:@"user"];
		_timestamp		= [coder decodeObjectForKey:@"timestamp"];
		_version		= [coder decodeInt32ForKey:@"version"];
		_changeset		= [coder decodeIntegerForKey:@"changeset"];
		_uid			= [coder decodeInt32ForKey:@"uid"];
		_visible		= [coder decodeBoolForKey:@"visible"];
		_tags			= [coder decodeObjectForKey:@"tags"];
		_deleted		= [coder decodeBoolForKey:@"deleted"];
		_modifyCount	= [coder decodeInt32ForKey:@"modified"];
	}
	return self;
}

-(id)init
{
	self = [super init];
	if ( self ) {
	}
	return self;
}

-(void)constructAsUserCreated
{
	// newly created by user
	assert( !_constructed );
	_ident = @( [OsmBaseObject nextUnusedIdentifier] );
	_visible = YES;
	_user = @"";
	_version = 1;
	_changeset = 0;
	_uid = 0;
	_deleted = YES;
	[self setTimestamp:[NSDate date] undo:nil];
}

@end

#pragma mark OsmNode

@implementation OsmNode
@synthesize lon = _lon;
@synthesize lat = _lat;
@synthesize wayCount = _wayCount;

-(NSString *)description
{
	return [NSString stringWithFormat:@"OsmNode id=%@ constructed=%@ deleted=%@ modifyCount=%d wayCount=%d",
			_ident,
			_constructed ? @"Yes" : @"No",
			self.deleted ? @"Yes" : @"No",
			_modifyCount,
			(int32_t)_wayCount];
}

-(BOOL)isNode
{
	return YES;
}

-(OSMPoint)location
{
	return OSMPointMake(_lon, _lat);
}
-(NSSet *)nodeSet
{
	return [NSSet setWithObject:self];
}
-(OSMRect)boundingBox
{
	OSMRect rc = { _lon, _lat, 0, 0 };
	return rc;
}

-(void)setLongitude:(double)longitude latitude:(double)latitude undo:(UndoManager *)undo
{
	if ( _constructed ) {
		assert(undo);
		[self incrementModifyCount:undo];
		[undo registerUndoWithTarget:self selector:@selector(setLongitude:latitude:undo:) objects:@[@(_lon),@(_lat),undo]];
	}
	_lon = longitude;
	_lat = latitude;
}


-(BOOL)intersectsBox:(OSMRect)box
{
	OSMPoint point = { _lon, _lat };
	return OSMRectContainsPoint( box, point );
}

-(id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if ( self ) {
		_lat		= [coder decodeDoubleForKey:@"lat"];
		_lon		= [coder decodeDoubleForKey:@"lon"];
		_wayCount	= [coder decodeIntegerForKey:@"wayCount"];
		_constructed = YES;
	}
	return self;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeDouble:_lat forKey:@"lat"];
	[coder encodeDouble:_lon forKey:@"lon"];
	[coder encodeInteger:_wayCount	forKey:@"wayCount"];
}

-(NSInteger)wayCount
{
	return _wayCount;
}
-(void)setWayCount:(NSInteger)wayCount undo:(UndoManager *)undo
{
	if ( _constructed && undo ) {
		[undo registerUndoWithTarget:self selector:@selector(setWayCount:undo:) objects:@[@(_wayCount),undo]];
	}
	_wayCount = wayCount;
}

@end

#pragma mark OsmWay

@implementation OsmWay

-(NSString *)description
{
	return [NSString stringWithFormat:@"OsmWay id=%@",self.ident];
}


-(void)constructNode:(NSNumber *)node
{
	assert( !_constructed );
	if ( _nodes == nil ) {
		_nodes = [NSMutableArray arrayWithObject:node];
	} else {
		[_nodes addObject:node];
	}
}


-(BOOL)isWay
{
	return YES;
}

-(void)resolveToMapData:(OsmMapData *)mapData
{
	for ( NSInteger i = 0, e = _nodes.count; i < e; ++i ) {
		NSNumber * ref = _nodes[i];
		if ( ![ref isKindOfClass:[NSNumber class]] )
			continue;
		OsmNode * node = [mapData nodeForRef:ref];
		assert(node);
		_nodes[i] = node;
		[node setWayCount:node.wayCount+1 undo:nil];
	}
}

-(void)removeNodeAtIndex:(NSInteger)index undo:(UndoManager *)undo
{
	assert(undo);
	OsmNode * node = _nodes[index];
	[self incrementModifyCount:undo];
	[undo registerUndoWithTarget:self selector:@selector(addNode:atIndex:undo:) objects:@[node,@(index),undo]];
	[_nodes removeObjectAtIndex:index];
	[node setWayCount:node.wayCount-1 undo:nil];
}
-(void)addNode:(OsmNode *)node atIndex:(NSInteger)index undo:(UndoManager *)undo
{
	if ( _constructed ) {
		assert(undo);
		[self incrementModifyCount:undo];
		[undo registerUndoWithTarget:self selector:@selector(removeNodeAtIndex:undo:) objects:@[@(index),undo]];
	}
	if ( _nodes == nil ) {
		_nodes = [NSMutableArray new];
	}
	[_nodes insertObject:node atIndex:index];
	[node setWayCount:node.wayCount+1 undo:nil];
}

-(BOOL)isArea
{
	if ( _nodes.count > 2 && _nodes[0] == _nodes.lastObject )
		return YES;
	NSString * value = [_tags valueForKey:@"area"];
	return value && OsmBooleanForValue( value );
}

-(BOOL)isClosed
{
	return _nodes.count > 2 && _nodes[0] == _nodes.lastObject;
}

-(double)wayArea
{
	assert(NO);
	return 0;
}

// return the point on the way closest to the supplied point
-(OSMPoint)pointOnWayForPoint:(OSMPoint)point
{
	switch ( _nodes.count ) {
		case 0:
			return point;
		case 1:
			return [((OsmNode *)_nodes.lastObject) location];
	}
	OSMPoint	bestPoint = { 0, 0 };
	double		bestDist = 360 * 360;
	for ( NSInteger i = 1; i < _nodes.count; ++i ) {
		OSMPoint p1 = [((OsmNode *)_nodes[i-1]) location];
		OSMPoint p2 = [((OsmNode *)_nodes[ i ]) location];
		OSMPoint linePoint = ClosestPointOnLineToPoint( p1, p2, point );
		double dist = MagSquared( Sub( linePoint, point ) );
		if ( dist < bestDist ) {
			bestDist = dist;
			bestPoint = linePoint;
		}
	}
	return bestPoint;
}


-(NSSet *)nodeSet
{
	return [NSSet setWithArray:_nodes];
}
-(BOOL)intersectsBox:(OSMRect)box
{
#if 1
	return OSMRectIntersectsRect(box, self.boundingBox);
#else
	BOOL first = YES;
	int prevRow, prevCol;

	if ( nodes.count >= 3 && nodes[0] == nodes.lastObject ) {
		// area
		return CGRectIntersectsRect(self.boundingBox, box);
	}
	for ( OsmNode * node in nodes ) {
		int row = node->lat < box.origin.y ? -1 : node->lat > box.origin.y+box.size.height ? 1 : 0;
		int col = node->lon < box.origin.x ? -1 : node->lon > box.origin.x+box.size.width  ? 1 : 0;
		if ( row == 0  &&  col == 0 )
			return YES;
		if ( !first ) {
			if ( row == prevRow ) {
				if ( row == 0  &&  col != prevCol )
					return YES;
			} else {
				if ( col != prevCol )
					return YES;
			}
			if ( col == prevCol ) {
				if ( col == 0  &&  row != prevRow )
					return YES;
			} else {
				if ( row != prevRow )
					return YES;
			}
		}
		first = NO;
		prevRow = row;
		prevCol = col;
	}
	return NO;
#endif
}
-(OSMRect)boundingBox
{
	double minX, maxX, minY, maxY;
	BOOL first = YES;
	for ( OsmNode * node in _nodes ) {
		OSMPoint loc = node.location;
		if ( first ) {
			first = NO;
			minX = maxX = loc.x;
			minY = maxY = loc.y;
		} else {
			if ( loc.y < minY )		minY = loc.y;
			if ( loc.x < minX )		minX = loc.x;
			if ( loc.y > maxY )		maxY = loc.y;
			if ( loc.x > maxX )		maxX = loc.x;
		}
	}
	if ( first ) {
		return OSMRectMake(0, 0, 0, 0);
	}
	return OSMRectMake(minX, minY, maxX-minX, maxY-minY);
}
-(OSMPoint)centerPointWithArea:(double *)area
{
	// compute centroid
	if ( _nodes.count > 2)  {
		CGFloat sum = 0;
		CGFloat sumX = 0;
		CGFloat sumY = 0;
		BOOL first = YES;
		OSMPoint offset = { 0, 0 };
		OSMPoint previous;
		for ( OsmNode * node in _nodes )  {
			if ( first ) {
				offset.x = node.lon;
				offset.y = node.lat;
				previous.x = 0;
				previous.y = 0;
				first = NO;
			} else {
				OSMPoint current = { node.lon - offset.x, node.lat - offset.y };
				CGFloat partialSum = previous.x*current.y - previous.y*current.x;
				sum += partialSum;
				sumX += (previous.x + current.x) * partialSum;
				sumY += (previous.y + current.y) * partialSum;
				previous = current;
			}
		}
		*area = sum/2;
		OSMPoint point = { sumX/6/ *area, sumY/6/ *area };
		point.x += offset.x;
		point.y += offset.y;
		return point;
	} else if ( _nodes.count == 2 ) {
		*area = 0;
		OsmNode * n1 = _nodes[0];
		OsmNode * n2 = _nodes[1];
		return OSMPointMake( (n1.lon+n2.lon)/2, (n1.lat+n2.lat)/2);
	} else if ( _nodes.count == 1 ) {
		*area = 0;
		OsmNode * node = _nodes.lastObject;
		return OSMPointMake(node.lon, node.lat);
	} else {
		*area = 0;
		OSMPoint pt = { 0, 0 };
		return pt;
	}
}
-(OSMPoint)centerPoint
{
	double area;
	return [self centerPointWithArea:&area];
}


-(id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if ( self ) {
		_nodes	= [coder decodeObjectForKey:@"nodes"];
		_constructed = YES;
	}
	return self;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeObject:_nodes forKey:@"nodes"];
}

@end

#pragma mark OsmRelation

@implementation OsmRelation

-(void)constructMember:(OsmMember *)member
{
	assert( !_constructed );
	if ( _members == nil ) {
		_members = [NSMutableArray arrayWithObject:member];
	} else {
		[_members addObject:member];
	}
}

-(BOOL)isRelation
{
	return YES;
}

-(void)resolveToMapData:(OsmMapData *)mapData
{
	for ( NSInteger i = 0, e = _members.count; i < e; ++i ) {
		OsmMember * member = _members[i];
		id ref = member.ref;
		if ( ![ref isKindOfClass:[NSNumber class]] )
			continue;

		if ( member.isWay ) {
			OsmWay * way = [mapData wayForRef:ref];
			if ( way ) {
				[member resolveRefToObject:way];
			} else {
				// way is not in current view
			}
		} else if ( member.isNode ) {
			OsmNode * node = [mapData nodeForRef:ref];
			if ( node ) {
				[member resolveRefToObject:node];
			} else {
				// node is not in current view
			}
		} else if ( member.isRelation ) {
			OsmRelation * rel = [mapData relationForRef:ref];
			if ( rel ) {
				[member resolveRefToObject:rel];
			} else {
				// relation is not in current view
			}
		} else {
			assert(NO);
		}
	}
}

-(OSMRect)boundingBox
{
	BOOL first = YES;
	OSMRect box = { 0, 0, 0, 0 };
	for ( OsmMember * member in _members ) {
		OsmBaseObject * obj = member.ref;
		if ( [obj isKindOfClass:[OsmBaseObject class]] ) {
			OSMRect rc = obj.boundingBox;
			if ( first ) {
				box = rc;
			} else {
				box = OSMRectUnion(box,rc);
			}
		}
	}
	return box;
}

-(BOOL)intersectsBox:(OSMRect)box
{
	for ( OsmMember * member in _members ) {
		if ( [member.ref isKindOfClass:[NSNumber class]] )
			continue;	// unresolved reference

		if ( member.isNode ) {
			OsmNode * node = member.ref;
			if ( OSMRectContainsPoint( box, node.location ) )
				return YES;
		} else if ( member.isWay ) {
			OsmWay * way = member.ref;
			if ( OSMRectIntersectsRect( way.boundingBox, box ) )
				return YES;
		} else if ( member.isRelation ) {
			OsmRelation * relation = member.ref;
			if ( [relation intersectsBox:box] )
				return YES;
		} else {
			assert(NO);
		}
	}
	return NO;
}

-(NSSet *)nodeSet
{
	NSMutableSet * set = [NSMutableSet set];
	for ( OsmMember * member in _members ) {
		if ( [member.ref isKindOfClass:[NSNumber class]] )
			continue;	// unresolved reference

		if ( member.isNode ) {
			OsmNode * node = member.ref;
			[set addObject:node];
		} else if ( member.isWay ) {
			OsmWay * way = member.ref;
			[set addObjectsFromArray:way.nodes];
		} else if ( member.isRelation ) {
			OsmRelation * relation = member.ref;
			for ( OsmNode * node in [relation nodeSet] ) {
				[set addObject:node];
			}
		} else {
			assert(NO);
		}
	}
	return set;
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeObject:_members forKey:@"members"];
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if ( self ) {
		_members	= [coder decodeObjectForKey:@"members"];
		_constructed = YES;
	}
	return self;
}

@end

#pragma mark OsmMember

@implementation OsmMember

-(id)initWithType:(NSString *)type ref:(NSNumber *)ref role:(NSString *)role
{
	self = [super init];
	if ( self ) {
		_type = type;
		_ref = ref;
		_role = role;
	}
	return self;
}

-(void)resolveRefToObject:(OsmBaseObject *)object
{
	assert( [_ref isKindOfClass:[NSNumber class]] );
	_ref = object;
}


-(BOOL)isNode
{
	return [_type isEqualToString:@"node"];
}
-(BOOL)isWay
{
	return [_type isEqualToString:@"way"];
}
-(BOOL)isRelation
{
	return [_type isEqualToString:@"relation"];
}

-(void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_type forKey:@"type"];
	[coder encodeObject:_ref forKey:@"ref"];
	[coder encodeObject:_role forKey:@"role"];
}
-(id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( self ) {
		_type	= [coder decodeObjectForKey:@"type"];
		_ref	= [coder decodeObjectForKey:@"ref"];
		_role	= [coder decodeObjectForKey:@"role"];
	}
	return self;
}

@end
