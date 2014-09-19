//
//  OsmMapLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <sys/utsname.h>
#import <CoreText/CoreText.h>

#import "NSMutableArray+PartialSort.h"

#import "iosapi.h"
#import "BingMapsGeometry.h"
#import "CurvedTextLayer.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "MapCSS.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmMapData+Orthogonalize.h"
#import "OsmMapData+Straighten.h"
#import "OsmObjects.h"
#import "PathUtil.h"
#import "QuadMap.h"
#import "SpeechBalloonLayer.h"
#import "TagInfo.h"
#import "VectorMath.h"


enum {
	SUBPART_AREA = 1,
	SUBPART_WAY = 2,
};

@interface ObjectSubpart : NSObject
@property (strong,nonatomic)	OsmBaseObject	*	object;
@property (strong,nonatomic)	NSString		*	subpart;
@property (strong,nonatomic)	NSDictionary	*	properties;
@property (assign,nonatomic)	CGFloat				zIndex;
@end
@implementation ObjectSubpart
@end


@implementation EditorMapLayer

@synthesize mapView				= _mapView;
@synthesize textColor			= _textColor;
@synthesize selectedNode		= _selectedNode;
@synthesize selectedWay			= _selectedWay;
@synthesize selectedRelation	= _selectedRelation;
@synthesize mapData				= _mapData;


const CGFloat WayHitTestRadius   = 10.0;
const CGFloat WayHighlightRadius = 6.0;


-(id)initWithMapView:(MapView *)mapView
{
	self = [super init];
	if ( self ) {
		_mapView = mapView;

		self.textColor = NSColor.whiteColor;

		// observe changes to geometry
		[_mapView addObserver:self forKeyPath:@"mapTransform" options:0 context:NULL];

		NSDate * startDate = [NSDate date];
		_mapData = [[OsmMapData alloc] initWithCachedData:self];
		double delta = [[NSDate date] timeIntervalSinceDate:startDate];
		//DLog(@"Load time = %f seconds",delta);
#if TARGET_OS_IPHONE
		if ( _mapData && delta > 5.0 ) {
			NSString * text = NSLocalizedString(@"Your OSM data cache is getting large, which may lead to slow startup and shutdown times. You may want to clear the cache (under Settings) to improve performance.",nil);
			UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cache size warning",nil) message:text delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
			[alertView show];
		}
#endif
		if ( _mapData == nil ) {
			_mapData = [[OsmMapData alloc] init];
		}

		__weak EditorMapLayer * weakSelf = self;
		[_mapData setUndoLocationCallback:^NSData *{
			OSMTransform trans = [weakSelf.mapView mapTransform];
			NSData * data = [NSData dataWithBytes:&trans length:sizeof trans];
			return data;
		}];

		self.actions = @{
						  @"onOrderIn"	: [NSNull null],
						  @"onOrderOut" : [NSNull null],
						  @"sublayers"	: [NSNull null],
						  @"contents"	: [NSNull null],
						  @"bounds"		: [NSNull null],
						  @"position"	: [NSNull null],
						  @"transform"	: [NSNull null],
		};

		[self setNeedsDisplay];
	}
	return self;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"mapTransform"] )  {
		[self updateMapLocation];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
	[self updateMapLocation];
}


- (void)save
{
	_mapData.editorMapLayerForArchive = self;
	[_mapData save];
}

- (id < CAAction >)actionForKey:(NSString *)key
{
	if ( [key isEqualToString:@"transform"] )
		return nil;
	if ( [key isEqualToString:@"bounds"] )
		return nil;
	if ( [key isEqualToString:@"position"] )
		return nil;
//	DLog(@"actionForKey: %@",key);
	return [super actionForKey:key];
}

#pragma mark Map data

const double MinIconSizeInPixels = 24;
const double MinIconSizeInMeters = 2.0;

- (void)updateIconSize
{
	double metersPerPixel = [_mapView metersPerPixel];
	if ( MinIconSizeInPixels * metersPerPixel < MinIconSizeInMeters ) {
		_iconSize.width  = round(MinIconSizeInMeters / metersPerPixel);
		_iconSize.height = round(MinIconSizeInMeters / metersPerPixel);
	} else {
		_iconSize.width	 = MinIconSizeInPixels;
		_iconSize.height = MinIconSizeInPixels;
	}

#if 1
	_highwayScale = 2.0;
#else
	const double laneWidth = 1.0; // meters per lane
	double scale = laneWidth / metersPerPixel;
	if ( scale < 1 )
		scale = 1;
	_highwayScale = scale;
#endif
}


- (void)purgeCachedDataHard:(BOOL)hard
{
	self.selectedNode	= nil;
	self.selectedWay	= nil;
	_highlightObject	= nil;
	if ( hard ) {
		[_mapData purgeHard];
	} else {
		[_mapData purgeSoft];
	}

	_speechBalloon.hidden = YES;
	[self setNeedsDisplay];
	[self updateMapLocation];
}


- (void)updateMapLocation
{
	if ( self.hidden )
		return;

	OSMRect box = [_mapView viewportLongitudeLatitude];
	if ( box.size.height <= 0 || box.size.width <= 0 )
		return;

	[self updateIconSize];

	[_mapData updateWithBox:box mapView:_mapView completion:^(BOOL partial,NSError * error) {
		if ( error ) {
			dispatch_async(dispatch_get_main_queue(), ^{
				// present error asynchrounously so we don't interrupt the current UI action
				if ( !self.hidden ) {	// if we've been hidden don't bother displaying errors
					[_mapView presentError:error flash:YES];
				}
			});
		} else {
			[self setNeedsDisplay];
		}
	}];

	[self setNeedsDisplay];
}

-(void)didReceiveMemoryWarning
{
	[self purgeCachedDataHard:NO];
	[self save];
}

#pragma mark Draw Ocean

static void AppendNodes( NSMutableArray * list, OsmWay * way, BOOL addToBack, BOOL reverseNodes )
{
	NSEnumerator * nodes = reverseNodes ? [way.nodes reverseObjectEnumerator] : [way.nodes objectEnumerator];
	if ( addToBack ) {
		// insert at back of list
		BOOL first = YES;
		for ( OsmNode * node in nodes ) {
			if ( first )
				first = NO;
			else
				[list addObject:node];
		}
	} else {
		// insert at front of list
		NSMutableArray * a = [NSMutableArray arrayWithCapacity:way.nodes.count];
		for ( OsmNode * node in nodes ) {
			[a addObject:node];
		}
		[a removeLastObject];
		NSIndexSet * loc = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,a.count)];
		[list insertObjects:a atIndexes:loc];
	}
}

static inline BOOL IsPointInRect( OSMPoint pt, OSMRect rect )
{
	double delta = 0.0001;
	if ( pt.x < rect.origin.x - delta )
		return NO;
	if ( pt.x > rect.origin.x+rect.size.width + delta )
		return NO;
	if ( pt.y < rect.origin.y - delta )
		return NO;
	if ( pt.y > rect.origin.y+rect.size.height + delta )
		return NO;
	return YES;
}

typedef enum _SIDE { SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM } SIDE;
static SIDE WallForPoint( OSMPoint pt, OSMRect rect )
{
	CGFloat delta = 0.01;
	if ( fabs(pt.x - rect.origin.x) < delta )
		return SIDE_LEFT;
	if ( fabs(pt.y - rect.origin.y) < delta )
		return SIDE_TOP;
	if ( fabs( pt.x - rect.origin.x-rect.size.width) < delta )
		return SIDE_RIGHT;
	if ( fabs( pt.y - rect.origin.y-rect.size.height) < delta )
		return SIDE_BOTTOM;
	assert(NO);
	return -1;
}


static BOOL IsClockwisePolygon( NSArray * points )
{
	assert( points[0] == points.lastObject );
	assert( points.count >= 4 );	// first and last repeat
	double area = 0;
	BOOL first = YES;
	OSMPoint offset;
	OSMPoint previous;
	for ( OSMPointBoxed * value in points )  {
		OSMPoint point = value.point;
		if ( first ) {
			offset = point;
			previous.x = previous.y = 0;
			first = NO;
		} else {
			OSMPoint current = { point.x - offset.x, point.y - offset.y };
			area += previous.x*current.y - previous.y*current.x;
			previous = current;
		}
	}
	area *= 0.5;
	return area >= 0;
}

static BOOL IsClockwiseWay( OsmWay * way )
{
	if ( !way.isClosed )
		return NO;
	if ( way.nodes.count < 4 )
		return NO;
	CGFloat sum = 0;
	BOOL first = YES;
	OSMPoint offset;
	OSMPoint previous;
	for ( OsmNode * node in way.nodes )  {
		OSMPoint point = node.location;
		if ( first ) {
			offset = point;
			previous.x = previous.y = 0;
			first = NO;
		} else {
			OSMPoint current = { point.x - offset.x, point.y - offset.y };
			sum += previous.x*current.y - previous.y*current.x;
			previous = current;
		}
	}
	return sum >= 0;
}



static BOOL RotateLoop( NSMutableArray * loop, OSMRect viewRect )
{
	assert( loop[0] == loop.lastObject );
	assert( loop.count >= 4 );
	[loop removeLastObject];
	NSInteger index = 0;
	for ( OSMPointBoxed * value in loop ) {
		if ( !OSMRectContainsPoint( viewRect, value.point ) )
			break;
		if ( ++index >= loop.count ) {
			index = -1;
			break;
		}
	}
	if ( index > 0 ) {
		NSIndexSet * set = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,index)];
		NSArray * a = [loop objectsAtIndexes:set];
		[loop removeObjectsAtIndexes:set];
		[loop addObjectsFromArray:a];
	}
	[loop addObject:loop[0]];
	return index >= 0;
}

static inline void Sort4( double p[] )
{
	if ( p[0] > p[1] ) { double t = p[1]; p[1] = p[0]; p[0] = t; }
	if ( p[2] > p[3] ) { double t = p[3]; p[3] = p[2]; p[2] = t; }
	if ( p[0] > p[2] ) { double t = p[2]; p[2] = p[0]; p[0] = t; }
	if ( p[1] > p[3] ) { double t = p[3]; p[3] = p[1]; p[1] = t; }
	if ( p[1] > p[2] ) { double t = p[2]; p[2] = p[1]; p[1] = t; }
}
static inline void Sort3( double p[] )
{
	if ( p[0] > p[1] ) { double t = p[1]; p[1] = p[0]; p[0] = t; }
	if ( p[0] > p[2] ) { double t = p[2]; p[2] = p[0]; p[0] = t; }
	if ( p[1] > p[2] ) { double t = p[2]; p[2] = p[1]; p[1] = t; }
}
static inline void Sort2( double p[] )
{
	if ( p[0] > p[1] ) { double t = p[1]; p[1] = p[0]; p[0] = t; }
}

static NSInteger ClipLineToRect( OSMPoint p1, OSMPoint p2, OSMRect rect, OSMPoint * pts )
{
	double top		= rect.origin.y;
	double bottom	= rect.origin.y + rect.size.height;
	double left		= rect.origin.x;
	double right	= rect.origin.x + rect.size.width;

	double dx = p2.x - p1.x;
	double dy = p2.y - p1.y;

	// get distances in terms of 0..1
	// we compute crossings for not only the rectangles walls but also the projections of the walls outside the rectangle,
	// so 4 possible interesection points
	double		cross[ 4 ]	= { 0 };
	NSInteger	crossSrc	= 0;
	if ( dx ) {
		CGFloat	vLeft	= (left   - p1.x) / dx;
		CGFloat vRight	= (right  - p1.x) / dx;
		if ( vLeft >= 0 && vLeft <= 1 )
			cross[ crossSrc++ ] = vLeft;
		if ( vRight >= 0 && vRight <= 1 )
			cross[ crossSrc++ ] = vRight;
	}
	if ( dy ) {
		CGFloat vTop	= (top    - p1.y) / dy;
		CGFloat vBottom	= (bottom - p1.y) / dy;
		if ( vTop >= 0 && vTop <= 1 )
			cross[ crossSrc++ ] = vTop;
		if ( vBottom >= 0 && vBottom <= 1 )
			cross[ crossSrc++ ] = vBottom;
	}

	// sort crossings according to distance from p1
	switch ( crossSrc ) {
		case 2: Sort2( cross );	break;
		case 3:	Sort3( cross ); break;
		case 4:	Sort4( cross );	break;
	}

	// get the points that are actually inside the rect (max 2)
	NSInteger crossCnt = 0;
	for ( NSInteger i = 0; i < crossSrc; ++i ) {
		OSMPoint pt = { p1.x + cross[i]*dx, p1.y + cross[i]*dy };
		if ( IsPointInRect( pt, rect ) ) {
			pts[ crossCnt++ ] = pt;
		}
	}

#if DEBUG
	assert( crossCnt <= 2 );
	for ( NSInteger i = 0; i < crossCnt; ++i ) {
		assert( IsPointInRect(pts[i], rect) );
	}
#endif

	return crossCnt;
}

// input is an array of OsmWay
// output is an array of arrays of OsmNode
// take a list of ways and return a new list of ways with contiguous ways joined together.
-(NSMutableArray *)joinConnectedWays:(NSMutableArray *)origList
{
	// connect ways together forming congiguous runs
	NSMutableArray * newList = [NSMutableArray new];
	while ( origList.count ) {
		// find all connected segments
		OsmWay * way = origList.lastObject;
		[origList removeObject:way];

		OsmNode * firstNode = way.nodes[0];
		OsmNode * lastNode = way.nodes.lastObject;
		NSMutableArray * nodeList = [NSMutableArray arrayWithObject:firstNode];
		AppendNodes( nodeList, way, YES, NO );
		while ( nodeList[0] != nodeList.lastObject ) {
			// find a way adjacent to current list
			for ( way in origList ) {
				if ( lastNode == way.nodes[0] ) {
					AppendNodes( nodeList, way, YES, NO );
					lastNode = nodeList.lastObject;
					break;
				}
				if ( lastNode == way.nodes.lastObject ) {
					AppendNodes( nodeList, way, YES, YES );
					lastNode = nodeList.lastObject;
					break;
				}
				if ( firstNode == way.nodes.lastObject ) {
					AppendNodes( nodeList, way, NO, NO );
					firstNode = nodeList[0];
					break;
				}
				if ( firstNode == way.nodes[0] ) {
					AppendNodes( nodeList, way, NO, YES );
					firstNode = nodeList[0];
					break;
				}
			}
			if ( way == nil )
				break;	// didn't find anything to connect to
			[origList removeObject:way];
		}
		[newList addObject:nodeList];
	}
	return newList;
}

-(void)convertNodesToPoints:(NSMutableArray *)nodeList
{
	if ( nodeList.count == 0 )
		return;
	BOOL isLoop = nodeList.count > 1 && nodeList[0] == nodeList.lastObject;
	for ( NSInteger index = 0, count = nodeList.count; index < count; ++index ) {
		if ( isLoop && index == count-1 ) {
			nodeList[index] = nodeList[0];
		} else {
			OsmNode * node = nodeList[index];
			OSMPoint pt = [self pointForLat:node.lat lon:node.lon];
			nodeList[index] = [OSMPointBoxed pointWithPoint:pt];
		}
	}
}


-(NSMutableArray *)visibleSegmentsOfWay:(NSMutableArray *)way inView:(OSMRect)viewRect
{
	// trim nodes in outlines to only internal paths
	NSMutableArray * newWays = [NSMutableArray new];

	BOOL first = YES;
	BOOL prevInside;
	BOOL isLoop = way[0] == way.lastObject;
	OSMPoint prevPoint;
	NSInteger index = 0;
	NSInteger lastEntry = -1;
	NSMutableArray * trimmedSegment = nil;

	if ( isLoop ) {
		// rotate loop to ensure start/end point is outside viewRect
		BOOL ok = RotateLoop(way, viewRect);
		if ( !ok ) {
			// entire loop is inside view
			[newWays addObject:way];
			return newWays;
		}
	}

	for ( OSMPointBoxed * value in way ) {
		OSMPoint pt = value.point;
		BOOL isInside = OSMRectContainsPoint( viewRect, pt );
		if ( first ) {
			first = NO;
		} else {

			BOOL isEntry = NO;
			BOOL isExit = NO;
			if ( prevInside ) {
				if ( isInside ) {
					// still inside
				} else {
					// moved to outside
					isExit = YES;
				}
			} else {
				if ( isInside ) {
					// moved inside
					isEntry = YES;
				} else {
					// if previous and current are both outside maybe we intersected
					if ( LineSegmentIntersectsRectangle( prevPoint, pt, viewRect ) ) {
						isEntry = YES;
						isExit = YES;
					} else {
						// still outside
					}
				}
			}

			OSMPoint pts[ 2 ];
			NSInteger crossCnt = (isEntry || isExit) ? ClipLineToRect( prevPoint, pt, viewRect, pts ) : 0;
			if ( isEntry ) {
				// start tracking trimmed segment
				assert( crossCnt >= 1 );
				OSMPointBoxed * v = [OSMPointBoxed pointWithPoint:pts[0] ];
				trimmedSegment = [NSMutableArray arrayWithObject:v];
				[newWays addObject:trimmedSegment];
				lastEntry = index-1;
			}
			if ( isExit ) {
				// end of trimmed segment. If the way began inside the viewrect then trimmedSegment is nil and gets ignored
				assert( crossCnt >= 1 );
				OSMPointBoxed * v = [OSMPointBoxed pointWithPoint:pts[crossCnt-1]];
				[trimmedSegment addObject:v];
				trimmedSegment = nil;
			} else if ( isInside ) {
				// internal node for trimmed segment
				[trimmedSegment addObject:value];
			}
		}
		prevInside = isInside;
		prevPoint = pt;
		++index;
	}
	if ( lastEntry < 0 ) {
		// never intersects screen
	} else if ( trimmedSegment ) {
		// entered but never exited
		[newWays removeLastObject];
	}
	return newWays;
}


-(void)addPointList:(NSArray *)list toContextPath:(CGContextRef)ctx
{
	BOOL first = YES;
	for ( OSMPointBoxed * point in list ) {
		OSMPoint p = point.point;
		if ( first ) {
			first = NO;
			CGContextMoveToPoint(ctx, p.x, p.y );
		} else {
			CGContextAddLineToPoint(ctx, p.x, p.y);
		}
	}
}

-(void)drawOceans:(NSArray *)objectList context:(CGContextRef)ctx
{
	// get all coastline ways
	NSMutableArray * outerSegments = [NSMutableArray new];
	NSMutableArray * innerSegments = [NSMutableArray new];
	for ( id obj in objectList ) {
		OsmBaseObject * object = obj;
		if ( [object isKindOfClass:[ObjectSubpart class]] )
			object = [(ObjectSubpart *)object object];
		if ( object.isWay.isClosed && [object.tags[@"natural"] isEqualToString:@"water"] ) {
			continue;	// lakes are not a concern of this function
		}
		if ( object.isCoastline ) {
			if ( object.isWay ) {
				[outerSegments addObject:object];
			} else if ( object.isRelation ) {
				for ( OsmMember * mem in object.isRelation.members ) {
					if ( [mem.ref isKindOfClass:[OsmWay class]] ) {
						if ( [mem.role isEqualToString:@"outer"] ) {
							[outerSegments addObject:mem.ref];
						} else if ( [mem.role isEqualToString:@"inner"] ) {
							[innerSegments addObject:mem.ref];
						} else {
							// skip
						}
					}
				}
			}
		}
	}
	if ( outerSegments.count == 0 )
		return;

	// connect ways together forming congiguous runs
	outerSegments = [self joinConnectedWays:outerSegments];
	innerSegments = [self joinConnectedWays:innerSegments];

	// convert lists of nodes to screen points
	for ( NSMutableArray * a in outerSegments )
		[self convertNodesToPoints:a];
	for ( NSMutableArray * a in innerSegments )
		[self convertNodesToPoints:a];

	CGRect cgViewRect = self.bounds;
	OSMRect viewRect = { cgViewRect.origin.x, cgViewRect.origin.y, cgViewRect.size.width, cgViewRect.size.height };
	CGPoint viewCenter = { viewRect.origin.x+viewRect.size.width/2, viewRect.origin.y+viewRect.size.height/2 };

#if 0
	// discard any segments that begin or end inside the view rectangle
	NSArray * innerInvalid = [innerSegments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * way, NSDictionary *bindings) {
		return way[0] != way.lastObject && (OSMRectContainsPoint(viewRect, [way[0] point]) || OSMRectContainsPoint(viewRect, [(OsmWay *)way.lastObject point]) );
	}]];
	NSArray * outerInvalid = [innerSegments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * way, NSDictionary *bindings) {
		return way[0] != way.lastObject && (OSMRectContainsPoint(viewRect, [way[0] point]) || OSMRectContainsPoint(viewRect, [way.lastObject point]) );
	}]];
	[innerSegments removeObjectsInArray:innerInvalid];
	[outerSegments removeObjectsInArray:outerInvalid];
#endif

	// ensure that outer ways are clockwise and inner ways are counterclockwise
	for ( NSMutableArray * way in outerSegments ) {
		if ( way[0] == way.lastObject ) {
			if ( !IsClockwisePolygon( way ) ) {
				// reverse points
				for ( NSInteger i = 0, j = way.count-1; i < j; ++i, --j ) {
					[way exchangeObjectAtIndex:i withObjectAtIndex:j];
				}
			}
		}
	}
	for ( NSMutableArray * way in innerSegments ) {
		if ( way[0] == way.lastObject ) {
			if ( IsClockwisePolygon( way ) ) {
				// reverse points
				for ( NSInteger i = 0, j = way.count-1; i < j; ++i, --j ) {
					[way exchangeObjectAtIndex:i withObjectAtIndex:j];
				}
			}
		}
	}

	// trim nodes in segments to only visible paths
	NSMutableArray * visibleSegments = [NSMutableArray new];
	for ( NSMutableArray * way in outerSegments ) {
		NSArray * other = [self visibleSegmentsOfWay:way inView:viewRect];
		[visibleSegments addObjectsFromArray:other];
	}
	for ( NSMutableArray * way in innerSegments ) {
		[visibleSegments addObjectsFromArray:[self visibleSegmentsOfWay:way inView:viewRect]];
	}

	if ( visibleSegments.count == 0 ) {
		// nothing is on screen
		return;
	}

	// pull islands into a separate list
	NSArray * islands = [visibleSegments filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * way, NSDictionary *bindings) {
		return way[0] == way.lastObject;
	}]];
	[visibleSegments removeObjectsInArray:islands];

	// get list of all external points
	NSMutableSet * pointSet = [NSMutableSet new];
	NSMutableDictionary * entryDict = [NSMutableDictionary new];
	for ( NSArray * way in visibleSegments ) {
		[pointSet addObject:way[0]];
		[pointSet addObject:way.lastObject];
		[entryDict setObject:way forKey:way[0]];
	}

	// sort points clockwise
	NSMutableArray * points = [[pointSet allObjects] mutableCopy];
	[points sortUsingComparator:^NSComparisonResult(OSMPointBoxed * v1, OSMPointBoxed * v2) {
		OSMPoint pt1 = v1.point;
		OSMPoint pt2 = v2.point;
		double ang1 = atan2( pt1.y - viewCenter.y, pt1.x - viewCenter.x );
		double ang2 = atan2( pt2.y - viewCenter.y, pt2.x - viewCenter.x );
		double angle = ang1 - ang2;
		NSComparisonResult result = angle < 0 ? NSOrderedAscending : angle > 0 ? NSOrderedDescending : NSOrderedSame;
		return result;
	}];


#if 0
	// drawing green/red entry/exit segments
	for ( NSArray * outline in visibleSegments ) {
		OSMPoint p1 = [outline[0] point];
		OSMPoint p2 = [outline[1] point];
		CGContextBeginPath(ctx);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextMoveToPoint(ctx, p1.x, p1.y);
		CGContextAddLineToPoint(ctx, p2.x, p2.y);
		CGContextSetLineWidth(ctx, 6);
		CGContextSetRGBStrokeColor(ctx, 0, 1, 0, 1);	// green
		CGContextStrokePath(ctx);
		//
		p1 = [outline.lastObject point];
		p2 = [outline[outline.count-2] point];
		CGContextBeginPath(ctx);
		CGContextMoveToPoint(ctx, p1.x, p1.y);
		CGContextAddLineToPoint(ctx, p2.x, p2.y);
		CGContextSetLineWidth(ctx, 6);
		CGContextSetRGBStrokeColor(ctx, 1, 0, 0, 1);	// red
		CGContextStrokePath(ctx);
	}
#endif

	// now have a set of discontiguous arrays of coastline nodes. Draw segments adding points at screen corners to connect them
	BOOL haveCoastline = NO;
	CGContextBeginPath(ctx);
	while ( visibleSegments.count ) {

		NSArray * firstOutline = visibleSegments.lastObject;
		OSMPointBoxed * exit  = firstOutline.lastObject;
		[visibleSegments removeObject:firstOutline];

		[self addPointList:firstOutline toContextPath:ctx];

		for (;;) {
			// find next point following exit point
			NSArray * nextOutline = [entryDict objectForKey:exit];	// check if exit point is also entry point
			if ( nextOutline == nil ) {	// find next entry point following exit point
				NSInteger exitIndex = [points indexOfObject:exit];
				NSInteger entryIndex = (exitIndex+1) % points.count;
				nextOutline = [entryDict objectForKey:points[entryIndex]];
			}
			if ( nextOutline == nil )
				return;
			OSMPointBoxed * entry = nextOutline[0];

			// connect exit point to entry point following clockwise borders
			{
				OSMPoint point1 = exit.point;
				OSMPoint point2 = entry.point;
				NSInteger wall1 = WallForPoint(point1, viewRect);
				NSInteger wall2 = WallForPoint(point2, viewRect);

				switch ( wall1 ) {
						for (;;) {
						case SIDE_LEFT:
							if ( wall2 == 0 && point1.y > point2.y )
								break;
							point1 = OSMPointMake(viewRect.origin.x, viewRect.origin.y);
							CGContextAddLineToPoint( ctx, point1.x, point1.y );
						case SIDE_TOP:
							if ( wall2 == 1 && point1.x < point2.x )
								break;
							point1 = OSMPointMake(viewRect.origin.x+viewRect.size.width, viewRect.origin.y );
							CGContextAddLineToPoint( ctx, point1.x, point1.y );
						case SIDE_RIGHT:
							if ( wall2 == 2 && point1.y < point2.y )
								break;
							point1 = OSMPointMake(viewRect.origin.x+viewRect.size.width, viewRect.origin.y+viewRect.size.height);
							CGContextAddLineToPoint( ctx, point1.x, point1.y );
						case SIDE_BOTTOM:
							if ( wall2 == 3 && point1.x > point2.x )
								break;
							point1 = OSMPointMake(viewRect.origin.x, viewRect.origin.y+viewRect.size.height);
							CGContextAddLineToPoint( ctx, point1.x, point1.y );
						}
				}
			}

			haveCoastline = YES;
			if ( nextOutline == firstOutline ) {
				break;
			}
			if ( ![visibleSegments containsObject:nextOutline] ) {
				return;
			}
			for ( OSMPointBoxed * value in nextOutline ) {
				OSMPoint pt = value.point;
				CGContextAddLineToPoint( ctx, pt.x, pt.y );
			}

			exit = nextOutline.lastObject;
			[visibleSegments removeObject:nextOutline];
		}
	}

	// draw islands
	for ( NSArray * island in islands ) {
		[self addPointList:island toContextPath:ctx];

		if ( !haveCoastline && IsClockwisePolygon(island) ) {
			// this will still fail if we have an island with a lake in it
			haveCoastline = YES;
		}
	}

	// if no coastline then draw water everywhere
	if ( !haveCoastline ) {
		CGContextMoveToPoint(ctx, viewRect.origin.x, viewRect.origin.y);
		CGContextAddLineToPoint(ctx, viewRect.origin.x+viewRect.size.width, viewRect.origin.y);
		CGContextAddLineToPoint(ctx, viewRect.origin.x+viewRect.size.width, viewRect.origin.y+viewRect.size.height);
		CGContextAddLineToPoint(ctx, viewRect.origin.x, viewRect.origin.y+viewRect.size.height);
		CGContextClosePath(ctx);
	}
	CGContextSetRGBFillColor(ctx, 0, 0, 1, 0.3);
	CGContextFillPath(ctx);
}

#pragma mark Drawing

-(BOOL)hasFastGraphics
{
	static BOOL isFast = YES;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		struct utsname systemInfo = { 0 };
		uname(&systemInfo);
		NSString * name = [[NSString alloc] initWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
		NSDictionary * dict = @{
							  @"i386"      :@"Simulator",
							  @"iPod1,1"   :@"iPod Touch",      // (Original)
							  @"iPod2,1"   :@"iPod Touch",      // (Second Generation)
							  @"iPod3,1"   :@"iPod Touch",      // (Third Generation)
							  @"iPod4,1"   :@"iPod Touch",      // (Fourth Generation)
							  @"iPhone1,1" :@"iPhone",          // (Original)
							  @"iPhone1,2" :@"iPhone",          // (3G)
							  @"iPhone2,1" :@"iPhone",          // (3GS)
							  @"iPad1,1"   :@"iPad",            // (Original)
							  @"iPad2,1"   :@"iPad 2",          //
							  @"iPad3,1"   :@"iPad",            // (3rd Generation)
							  @"iPhone3,1" :@"iPhone 4",        //
							  @"iPhone4,1" :@"iPhone 4S",       //
//							  @"iPhone5,1" :@"iPhone 5",        // (model A1428, AT&T/Canada)
//							  @"iPhone5,2" :@"iPhone 5",        // (model A1429, everything else)
							  @"iPad3,3"   :@"iPad",            // (3rd Generation)
//							  @"iPad3,4"   :@"iPad",            // (4th Generation)
							  @"iPad2,5"   :@"iPad Mini",       // (Original)
//							  @"iPhone5,3" :@"iPhone 5c",       // (model A1456, A1532 | GSM)
//							  @"iPhone5,4" :@"iPhone 5c",       // (model A1507, A1516, A1526 (China), A1529 | Global)
//							  @"iPhone6,1" :@"iPhone 5s",       // (model A1433, A1533 | GSM)
//							  @"iPhone6,2" :@"iPhone 5s",       // (model A1457, A1518, A1528 (China), A1530 | Global)
//							  @"iPad4,1"   :@"iPad Air",        // 5th Generation iPad (iPad Air) - Wifi
//							  @"iPad4,2"   :@"iPad Air",        // 5th Generation iPad (iPad Air) - Cellular
//							  @"iPad4,4"   :@"iPad Mini",       // (2nd Generation iPad Mini - Wifi)
//							  @"iPad4,5"   :@"iPad Mini"        // (2nd Generation iPad Mini - Cellular)
				};
		NSString * value = [dict objectForKey:name];
		if ( value.length > 0 ) {
			isFast = NO;
		}
	});
	return isFast;
}


-(BOOL)enableMapCss
{
	return _mapCss != nil;
}
-(void)setEnableMapCss:(BOOL)enableMapCss
{
	if ( enableMapCss != (_mapCss != nil) ) {
		[self willChangeValueForKey:@"enableMapCss"];
		if ( enableMapCss ) {
			_mapCss = [MapCSS sharedInstance];
		} else {
			_mapCss = nil;
		}
		[self didChangeValueForKey:@"enableMapCss"];
		[self setNeedsDisplay];
	}
}


-(OSMPoint)pointForLat:(double)lat lon:(double)lon
{
	OSMPoint pt = [MapView mapPointForLatitude:lat longitude:lon];
	OSMTransform transform = _mapView.mapTransform;
#if 1
	OSMPoint p2 = { pt.x - 128, pt.y - 128 };
	p2 = OSMPointApplyAffineTransform( p2, transform );
	pt.x = p2.x;
	pt.y = p2.y;
#else
	pt.x = (pt.x-128)*transform.a + transform.tx;
	pt.y = (pt.y-128)*transform.a + transform.ty;
#endif

	// modulus
	double denom = 256*transform.a;
	if ( pt.x > denom/2 )
		pt.x -= denom;
	else if ( pt.x < -denom/2 )
		pt.x += denom;

	return pt;
}


-(CGPathRef)pathForWay:(OsmWay *)way CF_RETURNS_RETAINED
{
	CGMutablePathRef path = CGPathCreateMutable();
	BOOL first = YES;
	for ( OsmNode * node in way.nodes ) {
		OSMPoint pt = [self pointForLat:node.lat lon:node.lon];
		if ( first ) {
			CGPathMoveToPoint(path, NULL, pt.x, pt.y);
			first = NO;
		} else {
			CGPathAddLineToPoint(path, NULL, pt.x, pt.y);
		}
	}
	return path;
}

-(NSInteger)zoomLevel
{
	return (NSInteger)floor( log2( _mapView.mapTransform.a ) );
}

typedef struct RGBAColor {
	CGFloat	red;
	CGFloat	green;
	CGFloat	blue;
	CGFloat	alpha;
} RGBAColor;
static const RGBAColor RGBAColorBlack		= { 0, 0, 0, 1 };
static const RGBAColor RGBAColorTransparent = { 0, 0, 0, 0 };

static inline uint8_t CharHexValue( char ch )
{
	if ( ch >= '0' && ch <= '9' )
		return ch -= '0';
	if ( ch >= 'A' && ch <= 'F' )
		return ch - ('A' - 10);
	if ( ch >= 'a' && ch <= 'f' )
		return ch - ('a' - 10);
	assert(NO);
	return 0;
}
static RGBAColor RGBFromString( NSString * text )
{
	if ( [text characterAtIndex:0] == '#' ) {
		CFStringEncoding encoding = CFStringGetFastestEncoding( (__bridge CFStringRef)text );
		if ( encoding != kCFStringEncodingMacRoman && encoding != kCFStringEncodingUTF8 )
			encoding = kCFStringEncodingMacRoman;
		UInt8 buffer[ 6 ] = { 0 };
		CFRange range = { 1, sizeof buffer };
		CFStringGetBytes( (__bridge CFStringRef)text, range, encoding, '?', NO, buffer, sizeof buffer, NULL );
		RGBAColor color;
		color.red	= (16 * CharHexValue( buffer[0] ) + CharHexValue( buffer[1] )) / 255.0;
		color.green = (16 * CharHexValue( buffer[2] ) + CharHexValue( buffer[3] )) / 255.0;
		color.blue	= (16 * CharHexValue( buffer[4] ) + CharHexValue( buffer[5] )) / 255.0;
		color.alpha = 1.0;
		return color;
	} else {
		static struct {
			RGBAColor		color;
			const char	*	name;
		} ColorList[] = {
			240/255.0, 248/255.0, 255/255.0, 1.0f, "aliceblue"           ,
			250/255.0, 235/255.0, 215/255.0, 1.0f, "antiquewhite"        ,
			  0/255.0, 255/255.0, 255/255.0, 1.0f, "aqua"                ,
			127/255.0, 255/255.0, 212/255.0, 1.0f, "aquamarine"          ,
			240/255.0, 255/255.0, 255/255.0, 1.0f, "azure"               ,
			245/255.0, 245/255.0, 220/255.0, 1.0f, "beige"               ,
			255/255.0, 228/255.0, 196/255.0, 1.0f, "bisque"              ,
			  0/255.0,   0/255.0,   0/255.0, 1.0f, "black"               ,
			255/255.0, 235/255.0, 205/255.0, 1.0f, "blanchedalmond"      ,
			  0/255.0,   0/255.0, 255/255.0, 1.0f, "blue"                ,
			138/255.0,  43/255.0, 226/255.0, 1.0f, "blueviolet"          ,
			165/255.0,  42/255.0,  42/255.0, 1.0f, "brown"               ,
			222/255.0, 184/255.0, 135/255.0, 1.0f, "burlywood"           ,
			 95/255.0, 158/255.0, 160/255.0, 1.0f, "cadetblue"           ,
			127/255.0, 255/255.0,   0/255.0, 1.0f, "chartreuse"          ,
			210/255.0, 105/255.0,  30/255.0, 1.0f, "chocolate"           ,
			255/255.0, 127/255.0,  80/255.0, 1.0f, "coral"               ,
			100/255.0, 149/255.0, 237/255.0, 1.0f, "cornflowerblue"      ,
			255/255.0, 248/255.0, 220/255.0, 1.0f, "cornsilk"            ,
			220/255.0,  20/255.0,  60/255.0, 1.0f, "crimson"             ,
			  0/255.0, 255/255.0, 255/255.0, 1.0f, "cyan"                ,
			  0/255.0,   0/255.0, 139/255.0, 1.0f, "darkblue"            ,
			  0/255.0, 139/255.0, 139/255.0, 1.0f, "darkcyan"            ,
			184/255.0, 134/255.0,  11/255.0, 1.0f, "darkgoldenrod"       ,
			169/255.0, 169/255.0, 169/255.0, 1.0f, "darkgray"            ,
			  0/255.0, 100/255.0,   0/255.0, 1.0f, "darkgreen"           ,
			169/255.0, 169/255.0, 169/255.0, 1.0f, "darkgrey"            ,
			189/255.0, 183/255.0, 107/255.0, 1.0f, "darkkhaki"           ,
			139/255.0,   0/255.0, 139/255.0, 1.0f, "darkmagenta"         ,
			 85/255.0, 107/255.0,  47/255.0, 1.0f, "darkolivegreen"      ,
			255/255.0, 140/255.0,   0/255.0, 1.0f, "darkorange"          ,
			153/255.0,  50/255.0, 204/255.0, 1.0f, "darkorchid"          ,
			139/255.0,   0/255.0,   0/255.0, 1.0f, "darkred"             ,
			233/255.0, 150/255.0, 122/255.0, 1.0f, "darksalmon"          ,
			143/255.0, 188/255.0, 143/255.0, 1.0f, "darkseagreen"        ,
			 72/255.0,  61/255.0, 139/255.0, 1.0f, "darkslateblue"       ,
			 47/255.0,  79/255.0,  79/255.0, 1.0f, "darkslategray"       ,
			 47/255.0,  79/255.0,  79/255.0, 1.0f, "darkslategrey"       ,
			  0/255.0, 206/255.0, 209/255.0, 1.0f, "darkturquoise"       ,
			148/255.0,   0/255.0, 211/255.0, 1.0f, "darkviolet"          ,
			255/255.0,  20/255.0, 147/255.0, 1.0f, "deeppink"            ,
			  0/255.0, 191/255.0, 255/255.0, 1.0f, "deepskyblue"         ,
			105/255.0, 105/255.0, 105/255.0, 1.0f, "dimgray"             ,
			105/255.0, 105/255.0, 105/255.0, 1.0f, "dimgrey"             ,
			 30/255.0, 144/255.0, 255/255.0, 1.0f, "dodgerblue"          ,
			178/255.0,  34/255.0,  34/255.0, 1.0f, "firebrick"           ,
			255/255.0, 250/255.0, 240/255.0, 1.0f, "floralwhite"         ,
			 34/255.0, 139/255.0,  34/255.0, 1.0f, "forestgreen"         ,
			255/255.0,   0/255.0, 255/255.0, 1.0f, "fuchsia"             ,
			220/255.0, 220/255.0, 220/255.0, 1.0f, "gainsboro"           ,
			248/255.0, 248/255.0, 255/255.0, 1.0f, "ghostwhite"          ,
			255/255.0, 215/255.0,   0/255.0, 1.0f, "gold"                ,
			218/255.0, 165/255.0,  32/255.0, 1.0f, "goldenrod"           ,
			128/255.0, 128/255.0, 128/255.0, 1.0f, "gray"                ,
			  0/255.0, 128/255.0,   0/255.0, 1.0f, "green"               ,
			173/255.0, 255/255.0,  47/255.0, 1.0f, "greenyellow"         ,
			128/255.0, 128/255.0, 128/255.0, 1.0f, "grey"                ,
			240/255.0, 255/255.0, 240/255.0, 1.0f, "honeydew"            ,
			255/255.0, 105/255.0, 180/255.0, 1.0f, "hotpink"             ,
			205/255.0,  92/255.0,  92/255.0, 1.0f, "indianred"           ,
			 75/255.0,   0/255.0, 130/255.0, 1.0f, "indigo"              ,
			255/255.0, 255/255.0, 240/255.0, 1.0f, "ivory"               ,
			240/255.0, 230/255.0, 140/255.0, 1.0f, "khaki"               ,
			230/255.0, 230/255.0, 250/255.0, 1.0f, "lavender"            ,
			255/255.0, 240/255.0, 245/255.0, 1.0f, "lavenderblush"       ,
			124/255.0, 252/255.0,   0/255.0, 1.0f, "lawngreen"           ,
			255/255.0, 250/255.0, 205/255.0, 1.0f, "lemonchiffon"        ,
			173/255.0, 216/255.0, 230/255.0, 1.0f, "lightblue"           ,
			240/255.0, 128/255.0, 128/255.0, 1.0f, "lightcyan"           ,
			224/255.0, 255/255.0, 255/255.0, 1.0f, "lightcoral"          ,
			250/255.0, 250/255.0, 210/255.0, 1.0f, "lightgoldenrodyellow",
			211/255.0, 211/255.0, 211/255.0, 1.0f, "lightgray"           ,
			144/255.0, 238/255.0, 144/255.0, 1.0f, "lightgreen"          ,
			211/255.0, 211/255.0, 211/255.0, 1.0f, "lightgrey"           ,
			255/255.0, 182/255.0, 193/255.0, 1.0f, "lightpink"           ,
			255/255.0, 160/255.0, 122/255.0, 1.0f, "lightsalmon"         ,
			 32/255.0, 178/255.0, 170/255.0, 1.0f, "lightseagreen"       ,
			135/255.0, 206/255.0, 250/255.0, 1.0f, "lightskyblue"        ,
			119/255.0, 136/255.0, 153/255.0, 1.0f, "lightslategray"      ,
			119/255.0, 136/255.0, 153/255.0, 1.0f, "lightslategrey"      ,
			176/255.0, 196/255.0, 222/255.0, 1.0f, "lightsteelblue"      ,
			255/255.0, 255/255.0, 224/255.0, 1.0f, "lightyellow"         ,
			  0/255.0, 255/255.0,   0/255.0, 1.0f, "lime"                ,
			 50/255.0, 205/255.0,  50/255.0, 1.0f, "limegreen"           ,
			250/255.0, 240/255.0, 230/255.0, 1.0f, "linen"               ,
			255/255.0,   0/255.0, 255/255.0, 1.0f, "magenta"             ,
			128/255.0,   0/255.0,   0/255.0, 1.0f, "maroon"              ,
			102/255.0, 205/255.0, 170/255.0, 1.0f, "mediumaquamarine"    ,
			  0/255.0,   0/255.0, 205/255.0, 1.0f, "mediumblue"          ,
			186/255.0,  85/255.0, 211/255.0, 1.0f, "mediumorchid"        ,
			147/255.0, 112/255.0, 219/255.0, 1.0f, "mediumpurple"        ,
			 60/255.0, 179/255.0, 113/255.0, 1.0f, "mediumseagreen"      ,
			123/255.0, 104/255.0, 238/255.0, 1.0f, "mediumslateblue"     ,
			  0/255.0, 250/255.0, 154/255.0, 1.0f, "mediumspringgreen"   ,
			 72/255.0, 209/255.0, 204/255.0, 1.0f, "mediumturquoise"     ,
			199/255.0,  21/255.0, 133/255.0, 1.0f, "mediumvioletred"     ,
			 25/255.0,  25/255.0, 112/255.0, 1.0f, "midnightblue"        ,
			245/255.0, 255/255.0, 250/255.0, 1.0f, "mintcream"           ,
			255/255.0, 228/255.0, 225/255.0, 1.0f, "mistyrose"           ,
			255/255.0, 228/255.0, 181/255.0, 1.0f, "moccasin"            ,
			255/255.0, 222/255.0, 173/255.0, 1.0f, "navajowhite"         ,
			  0/255.0,   0/255.0, 128/255.0, 1.0f, "navy"                ,
			253/255.0, 245/255.0, 230/255.0, 1.0f, "oldlace"             ,
			128/255.0, 128/255.0,   0/255.0, 1.0f, "olive"               ,
			107/255.0, 142/255.0,  35/255.0, 1.0f, "olivedrab"           ,
			255/255.0, 165/255.0,   0/255.0, 1.0f, "orange"              ,
			255/255.0,  69/255.0,   0/255.0, 1.0f, "orangered"           ,
			218/255.0, 112/255.0, 214/255.0, 1.0f, "orchid"              ,
			238/255.0, 232/255.0, 170/255.0, 1.0f, "palegoldenrod"       ,
			152/255.0, 251/255.0, 152/255.0, 1.0f, "palegreen"           ,
			175/255.0, 238/255.0, 238/255.0, 1.0f, "paleturquoise"       ,
			219/255.0, 112/255.0, 147/255.0, 1.0f, "palevioletred"       ,
			255/255.0, 239/255.0, 213/255.0, 1.0f, "papayawhip"          ,
			255/255.0, 218/255.0, 185/255.0, 1.0f, "peachpuff"           ,
			205/255.0, 133/255.0,  63/255.0, 1.0f, "peru"                ,
			255/255.0, 192/255.0, 203/255.0, 1.0f, "pink"                ,
			221/255.0, 160/255.0, 221/255.0, 1.0f, "plum"                ,
			176/255.0, 224/255.0, 230/255.0, 1.0f, "powderblue"          ,
			128/255.0,   0/255.0, 128/255.0, 1.0f, "purple"              ,
			255/255.0,   0/255.0,   0/255.0, 1.0f, "red"                 ,
			188/255.0, 143/255.0, 143/255.0, 1.0f, "rosybrown"           ,
			 65/255.0, 105/255.0, 225/255.0, 1.0f, "royalblue"           ,
			139/255.0,  69/255.0,  19/255.0, 1.0f, "saddlebrown"         ,
			250/255.0, 128/255.0, 114/255.0, 1.0f, "salmon"              ,
			244/255.0, 164/255.0,  96/255.0, 1.0f, "sandybrown"          ,
			 46/255.0, 139/255.0,  87/255.0, 1.0f, "seagreen"            ,
			255/255.0, 245/255.0, 238/255.0, 1.0f, "seashell"            ,
			160/255.0,  82/255.0,  45/255.0, 1.0f, "sienna"              ,
			192/255.0, 192/255.0, 192/255.0, 1.0f, "silver"              ,
			135/255.0, 206/255.0, 235/255.0, 1.0f, "skyblue"             ,
			106/255.0,  90/255.0, 205/255.0, 1.0f, "slateblue"           ,
			112/255.0, 128/255.0, 144/255.0, 1.0f, "slategray"           ,
			112/255.0, 128/255.0, 144/255.0, 1.0f, "slategrey"           ,
			255/255.0, 250/255.0, 250/255.0, 1.0f, "snow"                ,
			  0/255.0, 255/255.0, 127/255.0, 1.0f, "springgreen"         ,
			 70/255.0, 130/255.0, 180/255.0, 1.0f, "steelblue"           ,
			210/255.0, 180/255.0, 140/255.0, 1.0f, "tan"                 ,
			  0/255.0, 128/255.0, 128/255.0, 1.0f, "teal"                ,
			216/255.0, 191/255.0, 216/255.0, 1.0f, "thistle"             ,
			255/255.0,  99/255.0,  71/255.0, 1.0f, "tomato"              ,
			 64/255.0, 224/255.0, 208/255.0, 1.0f, "turquoise"           ,
			238/255.0, 130/255.0, 238/255.0, 1.0f, "violet"              ,
			245/255.0, 222/255.0, 179/255.0, 1.0f, "wheat"               ,
			255/255.0, 255/255.0, 255/255.0, 1.0f, "white"               ,
			245/255.0, 245/255.0, 245/255.0, 1.0f, "whitesmoke"          ,
			255/255.0, 255/255.0,   0/255.0, 1.0f, "yellow"              ,
			154/255.0, 205/255.0,  50/255.0, 1.0f, "yellowgreen"         ,
		};
		static NSDictionary * colorDict = nil;
		if ( colorDict == nil ) {
			NSMutableDictionary * dict = [NSMutableDictionary new];
			for ( int i = 0; i < sizeof ColorList/sizeof ColorList[0]; ++i ) {
				[dict setObject:@(i) forKey:@(ColorList[i].name)];
			}
			colorDict = [NSDictionary dictionaryWithDictionary:dict];
		}
		NSNumber * index = [colorDict valueForKey:text];
		if ( index ) {
			return ColorList[ index.integerValue ].color;
		}
		assert(NO);
		return RGBAColorTransparent;
	}
}
static BOOL DictRGB( NSDictionary * dict, RGBAColor * color, NSString * key )
{
	NSString * text = [dict objectForKey:key];
	if ( text == nil )
		return NO;
	*color = RGBFromString(text);
	return YES;
}
static BOOL DictFloat( NSDictionary * dict, CGFloat * value, NSString * key )
{
	NSString * text = [dict objectForKey:key];
	if ( text == nil )
		return NO;
	*value = text.doubleValue;
	return YES;
}
static BOOL DictLineCap( NSDictionary * dict, CGLineCap * lineCap, NSString * key )
{
	NSString * text = [dict objectForKey:key];
	if ( text == nil )
		return NO;
	if ( [text isEqualToString:@"round"] ) {
		*lineCap = kCGLineCapRound;
		return YES;
	}
	if ( [text isEqualToString:@"square"] ) {
		*lineCap = kCGLineCapSquare;
		return YES;
	}
	if ( [text isEqualToString:@"none"] ) {
		*lineCap = kCGLineCapButt;
		return YES;
	}
	assert(NO);
	return NO;
}
static BOOL DictLineJoin( NSDictionary * dict, CGLineJoin * lineJoin, NSString * key )
{
	NSString * text = [dict objectForKey:key];
	if ( text == nil )
		return NO;
	if ( [text isEqualToString:@"round"] ) {
		*lineJoin = kCGLineJoinRound;
		return YES;
	}
	if ( [text isEqualToString:@"miter"] ) {
		*lineJoin = kCGLineJoinMiter;
		return YES;
	}
	if ( [text isEqualToString:@"bevel"] ) {
		*lineJoin = kCGLineJoinBevel;
		return YES;
	}
	assert(NO);
	return NO;
}
static NSInteger DictDashes( NSDictionary * dict, CGFloat ** dashList, NSString * key )
{
	NSString * dashes = [dict objectForKey:@"dashes"];
	if ( dashes == nil ) {
		return 0;
	}
	NSArray * a = [dashes componentsSeparatedByString:@","];
	assert( a.count > 0 && a.count % 2 == 0 );
	*dashList = malloc( a.count * sizeof dashList[0][0] );
	NSInteger index = 0;
	for ( NSString * s in a ) {
		(*dashList)[index] = [s doubleValue];
		++index;
	}
	return a.count;
}



-(void)drawMapCssCoastline:(ObjectSubpart *)subpart context:(CGContextRef)ctx
{
	if ( subpart.object.isCoastline && subpart.object.isWay) {
		RGBAColor	lineColor = { 0, 0, 1, 1.0 };
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextSetLineJoin(ctx, kCGLineJoinRound);
		CGPathRef path = [self pathForWay:((OsmWay *)subpart.object)];
		CGContextBeginPath(ctx);
		CGContextAddPath(ctx, path);
		CGContextSetRGBStrokeColor( ctx, lineColor.red, lineColor.green, lineColor.blue, lineColor.alpha);
		CGContextSetLineWidth( ctx, 2.0 );
		CGContextStrokePath(ctx);
		CGPathRelease(path);
	}
}

-(BOOL)drawMapCssArea:(ObjectSubpart *)subpart context:(CGContextRef)ctx
{
	if ( !subpart.object.isWay )
		return NO;
	OsmWay * way = (id)subpart.object;
	if ( !way.isArea )
		return NO;

	NSDictionary * cssDict	= subpart.properties;
	RGBAColor	fillColor;
	BOOL fill = DictRGB( cssDict, &fillColor,	@"fill-color" );
	if ( !fill )
		return NO;
	DictFloat( cssDict, &fillColor.alpha,	@"fill-opacity" );
	CGPathRef path = [self pathForWay:way];
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);
	CGContextSetRGBFillColor(ctx, fillColor.red, fillColor.green, fillColor.blue, fillColor.alpha);
	CGContextFillPath(ctx);
	CGPathRelease(path);
	return YES;
}

-(NSArray *)wayListForMultipolygonRelation:(OsmRelation *)relation
{
	NSMutableArray * a = [NSMutableArray arrayWithCapacity:relation.members.count];
	for ( OsmMember * mem in relation.members ) {
		if ( [mem.role isEqualToString:@"outer"] || [mem.role isEqualToString:@"inner"] ) {
			if ( [mem.ref isKindOfClass:[OsmWay class]] ) {
				[a addObject:mem.ref];
			}
		}
	}
	return a;
}

-(BOOL)drawArea:(OsmBaseObject *)object context:(CGContextRef)ctx
{
	OsmWay * way = object.isWay;
	OsmRelation * relation = object.isRelation;

	if ( way && !way.isArea )
		return NO;

	TagInfo * tagInfo = object.tagInfo;
	if ( tagInfo.areaColor == nil )
		return NO;

	if ( object.isCoastline )
		return NO;	// already handled during ocean drawing


	NSMutableArray * outer = way ? [NSMutableArray arrayWithObject:way] : [NSMutableArray arrayWithCapacity:relation.members.count];
	NSMutableArray * inner = way ? nil : [NSMutableArray arrayWithCapacity:relation.members.count];
	for ( OsmMember * mem in relation.members ) {
		if ( [mem.ref isKindOfClass:[OsmWay class]] ) {
			if ( [mem.role isEqualToString:@"outer"] )
				[outer addObject:mem.ref];
			else if ( [mem.role isEqualToString:@"inner"] ) {
				[inner addObject:mem.ref];
			}
		}
	}

	// join connected nodes together
	outer = [self joinConnectedWays:outer];
	inner = [self joinConnectedWays:inner];

	// convert from nodes to screen points
	for ( NSMutableArray * a in outer )
		[self convertNodesToPoints:a];
	for ( NSMutableArray * a in inner )
		[self convertNodesToPoints:a];

	// draw
	CGContextBeginPath(ctx);
	for ( NSArray * w in outer ) {
		[self addPointList:w toContextPath:ctx];
	}
	for ( NSArray * w in inner ) {
		[self addPointList:w toContextPath:ctx];
	}
	RGBAColor	fillColor;
	[tagInfo.areaColor getRed:&fillColor.red green:&fillColor.green blue:&fillColor.blue alpha:&fillColor.alpha];
	CGContextSetRGBFillColor(ctx, fillColor.red, fillColor.green, fillColor.blue, 0.25);
	CGContextFillPath(ctx);

	return YES;
}

static inline NSColor * ShadowColorForColor( CGFloat r, CGFloat g, CGFloat b )
{
	return r+g+b > 1.5 ? UIColor.blackColor : UIColor.whiteColor;
}
static inline NSColor * ShadowColorForColor2( NSColor * color )
{
	CGFloat r, g, b, a;
	[color getRed:&r green:&g blue:&b alpha:&a];
	return ShadowColorForColor(r, g, b);
}

-(BOOL)drawWayCasing:(OsmBaseObject *)object context:(CGContextRef)ctx
{
	if ( ![object isKindOfClass:[OsmBaseObject class]] )
		// could be ObjectSubpart
		return NO;

	TagInfo * tagInfo = object.tagInfo;
	if ( tagInfo.lineWidth == 0 )
		return NO;

	OsmWay * way = object.isWay;
	OsmRelation * relation = object.isRelation;

	if ( way && way.isArea )
		return NO;

	NSArray * wayList = way ? @[ way ] : [self wayListForMultipolygonRelation:relation];

	CGContextBeginPath(ctx);
	for ( OsmWay * w in wayList ) {
		CGPathRef path = [self pathForWay:w];
		CGContextAddPath(ctx, path);
		CGPathRelease(path);
	}
	CGFloat red = 0.2, green = 0.2, blue = 0.2, alpha = 1.0;
	CGContextSetRGBStrokeColor(ctx, red, green, blue, alpha);
	CGContextSetLineWidth(ctx, (1+tagInfo.lineWidth)*_highwayScale);
	CGContextStrokePath(ctx);

	return YES;
}

-(void)drawSelectedWayHighlight:(CGPathRef)path width:(CGFloat)lineWidth wayColor:(RGBAColor)wayColor nodes:(NSSet *)nodes context:(CGContextRef)ctx
{
	if ( lineWidth == 0 )
		lineWidth = 1;
	lineWidth += 2;	// since we're drawing highlight 2-wide we don't want it to intrude inward on way
	CGPathRef selectionPath = CGPathCreateCopyByStrokingPath(path, NULL, lineWidth, kCGLineCapRound,  kCGLineJoinRound, 1.0);
	CGContextSetRGBStrokeColor(ctx, wayColor.red, wayColor.green, wayColor.blue, wayColor.alpha);
	CGContextSetLineWidth(ctx, 2);
	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 2.0, ShadowColorForColor( wayColor.red, wayColor.green, wayColor.blue).CGColor );
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, selectionPath);
	CGContextStrokePath(ctx);
	CGPathRelease(selectionPath);

	if ( nodes ) {
		// draw nodes of way
		for ( OsmNode * node in nodes ) {
			OSMPoint pt = [self pointForLat:node.lat lon:node.lon];
			if ( node == _selectedNode ) {
				CGContextSetRGBStrokeColor(ctx, 1,0,0, 1);	// red
			} else {
				CGContextSetRGBStrokeColor(ctx, 0,1,0, 1);	// green
			}
			CGContextBeginPath(ctx);
			CGContextSetLineWidth(ctx, 2);
			CGRect rect = CGRectMake(pt.x - WayHighlightRadius, pt.y - WayHighlightRadius, 2*WayHighlightRadius, 2*WayHighlightRadius);
			CGContextAddEllipseInRect(ctx, rect);
			CGContextStrokePath(ctx);
		}
	}
	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );
}

-(void)drawMapCssWay:(ObjectSubpart *)subpart context:(CGContextRef)ctx
{
	if ( !subpart.object.isWay )
		return;
	OsmWay * way = (id)subpart.object;

	NSDictionary * cssDict	= subpart.properties;
	RGBAColor	lineColor;
	BOOL line = DictRGB( cssDict, &lineColor,	@"color");
	if ( !line )
		return;
	CGFloat		width		= 1.0;
	CGLineJoin	lineJoin	= kCGLineJoinRound;
	CGLineCap	lineCap		= kCGLineCapRound;
	DictFloat(		cssDict, &width,			@"width" );
	DictLineCap(	cssDict, &lineCap,			@"linecap" );
	DictLineJoin(	cssDict, &lineJoin,			@"linejoin" );
	CGFloat		*	dashList = NULL;
	NSInteger dashCount = DictDashes(cssDict, &dashList, @"dashes" );
	if ( dashCount || dashList ) {
		CGContextSetLineDash(ctx, 0.0f, dashList, dashCount);
		free( dashList );
	}
	CGContextSetLineCap(ctx, lineCap);
	CGContextSetLineJoin(ctx, lineJoin);
	CGPathRef path = [self pathForWay:way];
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);
	CGContextSetRGBStrokeColor( ctx, lineColor.red, lineColor.green, lineColor.blue, lineColor.alpha);
	CGContextSetLineWidth( ctx, width );
	CGContextStrokePath(ctx);
	CGPathRelease(path);

	CGContextSetLineDash(ctx, 0.0f, NULL, 0);
}

-(void)drawArrowsForPath:(CGPathRef)path context:(CGContextRef)ctx
{
	BOOL solid = YES;
	double interval = 100;
	CGContextBeginPath(ctx);
	CGContextSetLineWidth(ctx, 1);
	if ( solid )
		CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
	else
		CGContextSetRGBStrokeColor(ctx, 0, 0, 0, 1);

	InvokeBlockAlongPath( path, interval/2, interval, ^(OSMPoint loc, OSMPoint dir){
		// draw direction arrow at loc/dir
		double len = 15;
		double width = 5;
		OSMPoint p1 = { loc.x - dir.x*len + dir.y*width, loc.y - dir.y*len - dir.x*width };
		OSMPoint p2 = { loc.x - dir.x*len - dir.y*width, loc.y - dir.y*len + dir.x*width };
		CGContextMoveToPoint(ctx, p1.x, p1.y);
		CGContextAddLineToPoint(ctx, loc.x, loc.y);
		CGContextAddLineToPoint(ctx, p2.x, p2.y);
		if ( solid ) {
			CGContextAddLineToPoint(ctx, loc.x-dir.x*len*0.5, loc.y-dir.y*len*0.5);
			CGContextClosePath(ctx);
		}
	});
	if ( solid )
		CGContextFillPath(ctx);
	else
		CGContextStrokePath(ctx);
}

-(BOOL)drawWay:(OsmBaseObject *)object context:(CGContextRef)ctx
{
	TagInfo * tagInfo = object.tagInfo;

	OsmWay * way = object.isWay ? (id)object : nil;
	OsmRelation * relation = object.isRelation ? (id)object : nil;

	NSArray * wayList = way ? @[ way ] : [self wayListForMultipolygonRelation:relation];

	CGFloat red = 0, green = 0, blue = 0, alpha = 1;
	[tagInfo.lineColor getRed:&red green:&green blue:&blue alpha:&alpha];
	CGFloat lineWidth = tagInfo.lineWidth*_highwayScale;
	if ( lineWidth == 0 )
		lineWidth = 1;

	for ( OsmWay * w in wayList ) {
		CGContextBeginPath(ctx);
		CGPathRef path = [self pathForWay:w];
		CGContextAddPath(ctx, path);
		CGContextSetRGBStrokeColor(ctx, red, green, blue, alpha);
		CGContextSetLineWidth(ctx, lineWidth);

		CGContextStrokePath(ctx);

		if ( way && way.isOneWay ) {
			[self drawArrowsForPath:path context:ctx];
		}
		CGPathRelease(path);
	}

	return YES;
}

-(void)drawMapCssName:(ObjectSubpart *)subpart context:(CGContextRef)ctx
{
	NSDictionary * cssDict	= subpart.properties;
	NSString * textKey = [cssDict objectForKey:@"text"];
	if ( textKey == nil )
		return;
	if ( [textKey characterAtIndex:0] == '"' )
		textKey = [textKey substringWithRange:NSMakeRange(1, textKey.length-2)];
	NSString * name = [subpart.object.tags valueForKey:textKey];
	if ( name == nil )
		return;
	// don't draw the same name twice
	if ( [_nameDrawSet containsObject:name] )
		return;
	[_nameDrawSet addObject:name];

	CGFloat fontSize = 10.0;
	DictFloat( cssDict, &fontSize, @"font-size" );
	RGBAColor textColor = RGBAColorBlack;
	DictRGB( cssDict, &textColor, @"text-color" );
#if TARGET_OS_IPHONE
	UIColor * color = [UIColor colorWithRed:textColor.red green:textColor.green blue:textColor.blue alpha:textColor.alpha];
#else
	NSColor * color = [NSColor colorWithCalibratedRed:textColor.red green:textColor.green blue:textColor.blue alpha:textColor.alpha];
#endif

#if 0
	CGFloat haloRadius = 1.0;
	DictFloat( cssDict, &haloRadius, @"text-halo-radius" );
	NSString * font = [cssDict objectForKey:@"font-family"];
	NSString * textPosition = [cssDict objectForKey:@"text-position"];
	CGFloat textSpacing = 400;
	DictFloat( cssDict, &textSpacing, @"text-spacing" );
#endif

	NSColor * shadowColor = ShadowColorForColor(textColor.red, textColor.green, textColor.blue);

	OsmWay * way = subpart.object.isWay ? (id)subpart.object : nil;

	BOOL area = way && way.isArea;
	if ( way && !area ) {
		// it is a line
		CGPathRef path = [self pathForWay:way];
		CGContextBeginPath(ctx);
		CGContextAddPath(ctx, path);
		[CurvedTextLayer drawString:name alongPath:path offset:5.0 color:color shadowColor:shadowColor context:ctx];
		CGPathRelease(path);
	} else {
		// it is a node or area
		OSMPoint point = [way centerPoint];
		point = [self pointForLat:point.y lon:point.x];
		CGPoint cgPoint = CGPointFromOSMPoint(point);

		[CurvedTextLayer drawString:name centeredOnPoint:cgPoint width:0 font:nil color:self.textColor shadowColor:ShadowColorForColor2(self.textColor) context:ctx];
	}
}

-(CGPathRef)pathClippedToViewRect:(OsmWay *)way length:(double *)pLength CF_RETURNS_RETAINED
{
	CGMutablePathRef	path = NULL;
	double				length = 0.0;
	OSMRect				viewRect = OSMRectFromCGRect( self.bounds );
	BOOL				prevInside;
	OSMPoint			prev = { 0 };
	BOOL				first = YES;
	OSMPoint			firstPoint = { 0 };
	OSMPoint			lastPoint = { 0 };

	for ( OsmNode * node in way.nodes ) {

		OSMPoint pt = [self pointForLat:node.lat lon:node.lon];
		BOOL inside = OSMRectContainsPoint( viewRect, pt );

		if ( first ) {
			first = NO;
			goto next;
		}
		OSMPoint cross[ 2 ];
		NSInteger crossCnt = 0;
		if ( !(prevInside && inside) ) {
			crossCnt = ClipLineToRect( prev, pt, viewRect, cross );
			if ( crossCnt == 0 ) {
				// both are outside and didn't cross
				goto next;
			}
		}

		OSMPoint p1 = prevInside ? prev : cross[0];
		OSMPoint p2 = inside	 ? pt   : cross[ crossCnt-1 ];
		if ( path == NULL ) {
			path = CGPathCreateMutable();
			CGPathMoveToPoint( path, NULL, p1.x, p1.y );
			firstPoint = prev;
		}
		CGPathAddLineToPoint( path, NULL, p2.x, p2.y );
		lastPoint = pt;
		length += hypot( p1.x - p2.x, p1.y - p2.y );
		if ( !inside )
			break;

	next:
		prev = pt;
		prevInside = inside;
	}
	if ( path ) {
		// orient path so text draws right-side up
		double dx = lastPoint.x - firstPoint.x;
		if ( dx < 0 ) {
			// reverse path
			CGMutablePathRef path2 = PathReversed( path );
			CGPathRelease(path);
			path = path2;
		}
	}
	*pLength = length;
	return path;
}


static NSString * DrawNodeAsHouseNumber( NSDictionary * tags )
{
	NSString * houseNumber = [tags objectForKey:@"addr:housenumber"];
	return houseNumber;
}


-(BOOL)drawWayName:(OsmBaseObject *)object context:(CGContextRef)ctx
{
	const CGFloat Pixels_Per_Character = 8.0;

	// add street names
	NSString * name = [object.tags valueForKey:@"name"];
	if ( name == nil )
		name = DrawNodeAsHouseNumber( object.tags );
	if ( name == nil )
		return NO;

	// don't draw the same name twice
	if ( [_nameDrawSet containsObject:name] )
		return NO;
	[_nameDrawSet addObject:name];

	OsmWay * way = object.isWay ? (id)object : nil;
	OsmRelation * relation = object.isRelation ? (id)object : nil;

	BOOL isHighway = way && !way.isClosed;
	if ( isHighway ) {

		double length = 0.0;
		CGPathRef path = [self pathClippedToViewRect:way length:&length];
		double offset = (length - name.length * Pixels_Per_Character) / 2;
		if ( offset < 0 ) {
			CGPathRelease( path );
			return NO;
		}
		[CurvedTextLayer drawString:name alongPath:path offset:offset color:self.textColor shadowColor:ShadowColorForColor2(self.textColor) context:ctx];
		CGPathRelease(path);

	} else {

		// don't draw names on objects too narrow for the label
		OSMRect bbox = object.boundingBox;
		double pixelWidth = bbox.size.width * MetersPerDegree( bbox.origin.y ) / _mapView.metersPerPixel;
		const NSInteger MaxLines = 3;
		pixelWidth = pixelWidth * 0.9;
		if ( name.length * Pixels_Per_Character > pixelWidth * MaxLines )
			return NO;
		
		OSMPoint point = way ? way.centerPoint : relation.centerPoint;
		point = [self pointForLat:point.y lon:point.x];
		CGPoint cgPoint = CGPointFromOSMPoint(point);
		UIFont * font = [UIFont systemFontOfSize:11];
		UIColor * shadowColor = ShadowColorForColor2(self.textColor);
		[CurvedTextLayer drawString:name centeredOnPoint:cgPoint width:pixelWidth font:font color:self.textColor shadowColor:shadowColor context:ctx];
	}
	return YES;
}


-(BOOL)drawNode:(OsmNode *)node context:(CGContextRef)ctx
{
	if ( _mapCss ) {
		ObjectSubpart * subpart = (id)node;
		OsmBaseObject * object = subpart.object;
		if ( !object.isNode && !object.isWay.isArea )
			return NO;
		NSDictionary * cssDict	= subpart.properties;
		NSString * iconName = [cssDict objectForKey:@"icon-image"];
		if ( iconName == nil ) {
			return NO;
		}
		node = (id)object;
	}

	OSMPoint pt;
	if ( node.isNode ) {
		pt = [self pointForLat:node.lat lon:node.lon];
	} else if ( node.isWay ) {
		// this path is taken when MapCSS is drawing an icon in the center of an area, such as a parking lot
		pt = [node.isWay centerPoint];
		pt = [self pointForLat:pt.y lon:pt.x];
	} else {
		assert(NO);
		return NO;
	}
#if DEBUG
	assert( CGRectContainsPoint(self.bounds,CGPointMake(pt.x, pt.y)) );
#endif
	pt.x = round(pt.x);	// performance optimization when drawing
	pt.y = round(pt.y);

	BOOL untagged = NO;
	TagInfo * tagInfo = node.tagInfo;
	if ( tagInfo.icon ) {

		UIImage * icon = tagInfo.icon;
		if ( _iconSize.height == MinIconSizeInPixels ) {
			if ( tagInfo.scaledIcon == nil ) {
				UIGraphicsBeginImageContext( _iconSize );
				[icon drawInRect:CGRectMake(0,0,_iconSize.width,_iconSize.height)];
				tagInfo.scaledIcon = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();
			}
			icon = tagInfo.scaledIcon;
		}

		// draw with icon
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, pt.y+_iconSize.height);
		CGContextScaleCTM(ctx, 1.0, -1.0);
		CGRect rect = CGRectMake(pt.x-round(_iconSize.width/2), round(_iconSize.height/2), _iconSize.width, _iconSize.height);
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, NSColor.whiteColor.CGColor );
		CGContextDrawImage( ctx, rect, icon.CGImage );
		CGContextRestoreGState(ctx);

	} else {

		// draw generic box
		CGFloat red, green, blue;
		if ( node.tags[@"shop"] ) {
			red = 0xAC/255.0;
			green = 0x39/255.0;
			blue = 0xAC/255.0;
		} else if ( node.tags[@"amenity"] || node.tags[@"building"] || node.tags[@"leisure"] ) {
			red = 0x73/255.0;
			green = 0x4A/255.0;
			blue = 0x08/255.0;
		} else if ( node.tags[@"tourism"] || node.tags[@"transport"] ) {
			red = 0x00/255.0;
			green = 0x92/255.0;
			blue = 0xDA/255.0;
		} else if ( node.tags[@"medical"] ) {
			red = 0xDA/255.0;
			green = 0x00/255.0;
			blue = 0x92/255.0;
		} else if ( node.tags[@"name"] ) {
			// blue for generic interesting nodes
			red = 0;
			green = 0;
			blue = 1;
		} else {
			// gray for untagged nodes
			untagged = YES;
			red = green = blue = 0.5;
		}
		CGContextSetRGBStrokeColor(ctx, red, green, blue, 1.0);

		NSString * houseNumber = untagged ? DrawNodeAsHouseNumber( node.tags ) : nil;
		if ( houseNumber ) {

			UIColor * shadowColor = ShadowColorForColor2(self.textColor);
			CGPoint point = CGPointFromOSMPoint(pt);
			[CurvedTextLayer drawString:houseNumber	centeredOnPoint:point width:0 font:nil color:self.textColor shadowColor:shadowColor context:ctx];

		} else {

			CGContextSetLineWidth(ctx, 2.0);
			CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, ShadowColorForColor(red, green, blue).CGColor );
			CGRect rect = CGRectMake(pt.x - round(_iconSize.width/4), pt.y - round(_iconSize.height/4), round(_iconSize.width/2), round(_iconSize.height/2));
			CGContextBeginPath(ctx);
			CGContextAddRect(ctx, rect);
			CGContextStrokePath(ctx);
		}
	}

	// if zoomed in very close then provide targeting lines
	if ( _iconSize.width > 64 ) {
		CGContextSetStrokeColorWithColor( ctx, NSColor.blackColor.CGColor );
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, NSColor.whiteColor.CGColor );
		CGContextSetLineWidth( ctx, 1.0 );
		CGContextBeginPath(ctx);
		CGPoint line1[2] = { pt.x - 10, pt.y, pt.x+10, pt.y };
		CGPoint line2[2] = { pt.x, pt.y - 10, pt.x, pt.y + 10 };
		CGContextAddLines( ctx, line1, 2 );
		CGContextAddLines( ctx, line2, 2 );
		CGContextStrokePath(ctx);
	}

	return YES;
}

-(void)drawHighlighedObjects:(CGContextRef)ctx
{
	NSInteger zoom = [self zoomLevel];

	NSMutableArray * highlights = [NSMutableArray arrayWithArray:self.extraSelections];
	if ( _selectedNode ) {
		[highlights addObject:_selectedNode];
	}
	if ( _selectedWay ) {
		[highlights addObject:_selectedWay];
	}
	if ( _selectedRelation ) {
		NSSet * members = [_selectedRelation allMemberObjects];
		[highlights addObjectsFromArray:members.allObjects];
	}
	if ( _highlightObject ) {
		[highlights addObject:_highlightObject];
	}
	for ( OsmBaseObject * object in highlights ) {
		BOOL selected = object == _selectedNode || object == _selectedWay || [self.extraSelections containsObject:object];

		if ( object.isWay ) {
			OsmWay * way = (id)object;
			CGFloat width = MaxSubpartWidthForWay( way, @(zoom) );
			CGPathRef path = [self pathForWay:way];
			RGBAColor color = { 1, 1, !selected, 1 };
			NSSet * nodes = way == _selectedWay ? way.nodeSet : nil;
			[self drawSelectedWayHighlight:path width:width wayColor:color nodes:nodes context:ctx];
			CGPathRelease(path);
		} else if ( object.isNode ) {
			OsmNode * node = (id)object;
			OSMPoint pt = [self pointForLat:node.lat lon:node.lon];

			CGContextBeginPath(ctx);
			if ( selected )
				CGContextSetRGBStrokeColor(ctx, 1,1,0, 1);	// yellow
			else
				CGContextSetRGBStrokeColor(ctx, 1,1,1, 1);	// white
			CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, NSColor.blackColor.CGColor );
			CGContextSetLineWidth(ctx, 2);
			CGRect rect = CGRectMake(pt.x - _iconSize.width/2, pt.y - _iconSize.width/2, _iconSize.width, _iconSize.width);
			CGContextAddRect(ctx, rect);
			CGContextStrokePath(ctx);
		}
	}
}


static BOOL inline ShouldDisplayNodeInWay( NSDictionary * tags )
{
	NSInteger tagCount = tags.count;
	if ( tagCount == 0 )
		return NO;
	if ( [tags objectForKey:@"source"] )
		--tagCount;
	return tagCount > 0;
}

-(NSMutableArray *)getVisibleObjects
{
	OSMRect box = [_mapView viewportLongitudeLatitude];
	NSMutableArray * a = [NSMutableArray arrayWithCapacity:_mapData.wayCount];
	NSMutableSet * relations = [NSMutableSet new];
	[_mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
		if ( !obj.deleted ) {
			if ( obj.relations ) {
				[relations addObjectsFromArray:obj.relations];
			}
			if ( obj.isNode ) {
				if ( ((OsmNode *)obj).wayCount == 0 ) {
					[a addObject:obj];
				}
			} else if ( obj.isWay ) {
				[a addObject:obj];
				for ( OsmNode * node in ((OsmWay *)obj).nodes ) {
					if ( [node overlapsBox:box] && ShouldDisplayNodeInWay( node.tags ) ) {
						[a addObject:node];
					}
				}
			} else if ( obj.isRelation ) {
				[relations addObject:obj];
			}
		}
	}];

	for ( OsmRelation * r in relations ) {
		[a addObject:r];
	}
	return a;
}

static CGFloat MaxSubpartWidthForWay( OsmWay * way, NSNumber * zoom )
{
	CGFloat width = 1.0;
	NSMutableDictionary * zoomDict = way.renderProperties;
	NSArray * objectSubparts = [zoomDict objectForKey:zoom];
	for ( ObjectSubpart * subpart in objectSubparts ) {
		NSDictionary * cssDict	= subpart.properties;
		CGFloat	w;
		if ( DictFloat( cssDict, &w, @"width" ) && w > width )
			width = w;
	}
	return width;
}
/*
To render OSM nicely using Painter's algorithm you need to:
- render background
- render coaslines as polygons
- render all the backgrounds (like forests, grass, different kinds of landuse=, ...)
- render hillshading (optionally, of course)

then, for each layer= tag in order from lowest to highest:
- render casings in order of z-index-es
- render *both* polygons and lines that represent foreground features (buildings, roads) in order of z-indexes

then, render icons and labels in order that is backward for z-indexes (if renderer can detect collisions) 
or in order of z-indexes (if renderer can detect collisions).
*/
- (void) drawMapCssInContext:(CGContextRef)ctx
{
	_shownObjects = [self getVisibleObjects];
	
	NSMutableArray * a = [NSMutableArray arrayWithCapacity:_shownObjects.count];
	NSNumber * zoom = @( [self zoomLevel] );
	for ( OsmBaseObject * object in _shownObjects ) {
		// maps subpart ID to propery dictionary for this object
		NSMutableDictionary * zoomDict = object.renderProperties;
		if ( zoomDict == nil ) {
			zoomDict = [NSMutableDictionary new];
			object.renderProperties = zoomDict;
		}
		NSArray * subparts = [zoomDict objectForKey:zoom];
		if ( subparts == nil ) {
			NSDictionary * dict = [_mapCss matchObject:object zoom:zoom.integerValue];
			NSMutableArray * subs = [NSMutableArray arrayWithCapacity:dict.count];
			[dict enumerateKeysAndObjectsUsingBlock:^(NSString * subpartID, NSDictionary * props, BOOL *stop) {
				ObjectSubpart * subpart = [ObjectSubpart new];
				subpart.object		= object;
				subpart.subpart		= subpartID;
				subpart.properties	= props;
				subpart.zIndex		= [[props valueForKey:@"z-index"] doubleValue];
				[subs addObject:subpart];
			}];
			subparts = subs;
			[zoomDict setObject:subparts forKey:zoom];
		}
		[a addObjectsFromArray:subparts];
	}
	[a sortUsingComparator:^NSComparisonResult(ObjectSubpart * obj1, ObjectSubpart * obj2) {
		CGFloat z1 = obj1.zIndex;
		CGFloat z2 = obj2.zIndex;
		NSComparisonResult result = z1 < z2 ? NSOrderedAscending : z1 > z2 ? NSOrderedDescending : NSOrderedSame;
		return result;
	}];

	_shownObjects = a;

	// draw coastline
	[self drawOceans:a context:ctx];
	for ( ObjectSubpart * obj in a ) {
		[self drawMapCssCoastline:obj context:ctx];
	}
	// draw areas
	for ( ObjectSubpart * obj in a ) {
		[self drawMapCssArea:obj context:ctx];
	}
	// draw ways
	for ( ObjectSubpart * obj in a ) {
		[self drawMapCssWay:obj context:ctx];
	}
	// draw nodes
	for ( ObjectSubpart * obj in a ) {
		[self drawNode:(OsmNode *)obj context:ctx];
	}
	// draw names
	for ( ObjectSubpart * obj in a ) {
		[self drawMapCssName:obj context:ctx];
	}
	// draw highlights
	[self drawHighlighedObjects:ctx];
}


static BOOL VisibleSizeLess( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	NSInteger diff = obj1.renderPriorityCached - obj2.renderPriorityCached;
	return diff > 0;	// sort descending
}
static BOOL VisibleSizeLessStrict( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	long long diff = obj1.renderPriorityCached - obj2.renderPriorityCached;
	if ( diff == 0 )
		diff = obj1.ident.longLongValue - obj2.ident.longLongValue;	// older objects are bigger
	return diff > 0;	// sort descending
}


- (void)drawInContext:(CGContextRef)ctx
{
	_nameDrawSet = [NSMutableSet new];

	if ( _mapCss ) {
		[self drawMapCssInContext:ctx];
		return;
	}

#if TARGET_OS_IPHONE
	NSInteger objectLimit	= [self hasFastGraphics] ? 100 : 50;
	NSInteger nameLimit		= [self hasFastGraphics] ? 10 : 5;
#else
	NSInteger objectLimit = 500;
	NSInteger nameLimit = 100;
#endif

	double metersPerPixel = [_mapView metersPerPixel];
	if ( metersPerPixel < 0.05 ) {
		// we're zoomed in very far, so show everything
		objectLimit = 1000000;
	}


	CFTimeInterval totalTime = CACurrentMediaTime();

	// get objects in visible rect
	_shownObjects = [self getVisibleObjects];

	// get taginfo for objects
	for ( OsmBaseObject * object in _shownObjects ) {
		if ( object.tagInfo == nil ) {
			object.tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForObject:object];
		}
		if ( object.renderPriorityCached == 0 ) {
			if ( object.modifyCount ) {
				object.renderPriorityCached = 1000000;
			} else {
				object.renderPriorityCached = [object.tagInfo renderSize:object];
			}
		}
	}

	// sort from big to small objects
	[_shownObjects partialSortK:2*objectLimit+1 compare:VisibleSizeLessStrict];

	// adjust the list of objects so that we get all or none of the same type
	if ( _shownObjects.count > objectLimit ) {
		// We have more objects available than we want to display. If some of the objects are the same size as the last visible object then include those too.
		NSInteger lastIndex = objectLimit;
		OsmBaseObject * last = _shownObjects[ objectLimit-1 ];
		NSInteger lastRenderPriority = last.renderPriorityCached;
		for ( NSInteger i = objectLimit, e = MIN(_shownObjects.count,2*objectLimit); i < e; ++i ) {
			OsmBaseObject * o = _shownObjects[ i ];
			if ( o.renderPriorityCached == lastRenderPriority ) {
				lastIndex++;
			} else {
				break;
			}
		}
		if ( lastIndex >= 2*objectLimit ) {
			// we doubled the number of objects, so back off instead
			NSInteger removeCount = 0;
			for ( NSInteger i = objectLimit-1; i >= 0; --i ) {
				OsmBaseObject * o = _shownObjects[ i ];
				if ( o.renderPriorityCached == lastRenderPriority ) {
					++removeCount;
				} else {
					break;
				}
			}
			if ( removeCount < objectLimit ) {
				lastIndex = objectLimit - removeCount;
			}
		}
		// DLog( @"added %ld same", (long)lastIndex - objectLimit);
		objectLimit = lastIndex;

		// remove unwanted objects
		NSIndexSet * range = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(objectLimit,_shownObjects.count-objectLimit)];
		[_shownObjects removeObjectsAtIndexes:range];
	}

	int areaCount = 0;
	int casingCount = 0;
	int wayCount = 0;
	int nodeCount = 0;
	int nameCount = 0;

	// draw oceans
	[self drawOceans:_shownObjects context:ctx];

	// draw areas
	CFTimeInterval areaTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isWay ) {
			areaCount += [self drawArea:(id)obj context:ctx];
		} else if ( obj.isRelation.isMultipolygon ) {
			areaCount += [self drawArea:(id)obj context:ctx];
		}
	}
	areaTime = CACurrentMediaTime() - areaTime;

	// draw casings
	CFTimeInterval casingTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isWay ) {
			casingCount += [self drawWayCasing:obj context:ctx];
		} else if ( obj.isRelation.isMultipolygon ) {
			casingCount += [self drawWayCasing:obj context:ctx];
		}
	}
	casingTime = CACurrentMediaTime() - casingTime;

	// draw ways
	CFTimeInterval wayTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isWay ) {
			wayCount += [self drawWay:obj context:ctx];
		} else if ( obj.isRelation.isMultipolygon ) {
			wayCount += [self drawWay:obj context:ctx];
		}
	}
	wayTime = CACurrentMediaTime() - wayTime;

	// draw nodes
	CFTimeInterval nodeTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isNode ) {
			nodeCount += [self drawNode:(id)obj context:ctx];
		}
	}
	nodeTime = CACurrentMediaTime() - nodeTime;

	// draw names
	CFTimeInterval nameTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {

		if ( obj.isWay || obj.isRelation.isMultipolygon ) {
			BOOL drawn = [self drawWayName:obj context:ctx];
			nameCount += drawn;
			nameLimit -= drawn;
			if ( nameLimit <= 0 )
				break;
		}
	}
	nameTime = CACurrentMediaTime() - nameTime;

	// draw highlights
	[self drawHighlighedObjects:ctx];

	totalTime = CACurrentMediaTime() - totalTime;

#if 0
	DLog( @"%.2f: area %d (%.2f), casing %d (%.2f), way %d (%.2f), node %d (%.2f) name %d (%.2f)",
		 totalTime*1000,
		 areaCount, areaTime*1000,
		 casingCount, casingTime*1000,
		 wayCount, wayTime*1000,
		 nodeCount, nodeTime*1000,
		 nameCount, nameTime*1000 );
#endif
}

#pragma mark Hit Testing


inline static CGFloat HitTestLineSegment(CLLocationCoordinate2D point, OSMSize maxDegrees, CLLocationCoordinate2D coord1, CLLocationCoordinate2D coord2)
{
	OSMPoint line1 = { coord1.longitude - point.longitude, coord1.latitude - point.latitude };
	OSMPoint line2 = { coord2.longitude - point.longitude, coord2.latitude - point.latitude };
	OSMPoint pt = { 0, 0 };

	// adjust scale
	line1.x /= maxDegrees.width;
	line1.y /= maxDegrees.height;
	line2.x /= maxDegrees.width;
	line2.y /= maxDegrees.height;

	CGFloat dist = DistanceFromPointToLineSegment( pt, line1, line2 );
	return dist;
}

+ (CGFloat)osmHitTest:(CLLocationCoordinate2D)location maxDegrees:(OSMSize)maxDegrees forWay:(OsmWay *)way segment:(NSInteger *)segment
{
	CLLocationCoordinate2D previous;
	NSInteger seg = -1;
	CGFloat bestDist = 1000000;
	for ( OsmNode * node in way.nodes ) {
		if ( seg >= 0 ) {
			CLLocationCoordinate2D coord = { node.lat, node.lon };
			CGFloat dist = HitTestLineSegment( location, maxDegrees, coord, previous );
			if ( dist < bestDist ) {
				bestDist = dist;
				*segment = seg;
			}
		}
		++seg;
		previous.latitude = node.lat;
		previous.longitude = node.lon;
	}
	return bestDist;
}
+ (CGFloat)osmHitTest:(CLLocationCoordinate2D)location maxDegrees:(OSMSize)maxDegrees forNode:(OsmNode *)node
{
	OSMPoint delta = {
		fabs(location.longitude - node.lon),
		fabs(location.latitude - node.lat)
	};
	if ( delta.x > maxDegrees.width || delta.y > maxDegrees.height )
		return 1000000;
	delta.x /= maxDegrees.width;
	delta.y /= maxDegrees.height;
	CGFloat dist = hypot(delta.x, delta.y);
	return dist;
}

// distance is in units of the hit test radius (WayHitTestRadius)
+ (void)osmHitTestEnumerate:(CGPoint)point mapView:(MapView *)mapView objects:(NSArray *)objects testNodes:(BOOL)testNodes
				 ignoreList:(NSArray *)ignoreList block:(void(^)(OsmBaseObject * obj,CGFloat dist,NSInteger segment))block
{
	CLLocationCoordinate2D location = [mapView longitudeLatitudeForViewPoint:point];
	OSMRect viewCoord = [mapView viewportLongitudeLatitude];
	OSMSize pixelsPerDegree = { mapView.bounds.size.width / viewCoord.size.width, mapView.bounds.size.height / viewCoord.size.height };

	OSMSize maxDegrees = { WayHitTestRadius / pixelsPerDegree.width, WayHitTestRadius / pixelsPerDegree.height };

	for ( OsmBaseObject * object in objects ) {
		if ( object.deleted )
			continue;
		if ( object.isNode ) {
			OsmNode * node = (id)object;
			if ( ![ignoreList containsObject:node] ) {
				if ( testNodes || node.wayCount == 0 ) {
					CGFloat dist = [self osmHitTest:location maxDegrees:maxDegrees forNode:node];
					if ( dist <= 1.0 ) {
						block( node, dist, 0 );
					}
				}
			}
		} else if ( object.isWay ) {
			OsmWay * way = (id)object;
			if ( ![ignoreList containsObject:way] ) {
				NSInteger seg;
				CGFloat dist = [self osmHitTest:location maxDegrees:maxDegrees forWay:way segment:&seg];
				if ( dist <= 1.0 ) {
					block( object, dist, seg );
				}
			}
			if ( testNodes ) {
				for ( OsmNode * node in way.nodes ) {
					if ( [ignoreList containsObject:node] )
						continue;
					CGFloat dist = [self osmHitTest:location maxDegrees:maxDegrees forNode:node];
					if ( dist < 1.0 ) {
						block( node, dist, 0 );
					}
				}
			}
		}
	}
}

+ (OsmBaseObject *)osmHitTest:(CGPoint)point mapView:(MapView *)mapView objects:(NSArray *)objects testNodes:(BOOL)testNodes
				   ignoreList:(NSArray *)ignoreList segment:(NSInteger *)pSegment
{
	__block __unsafe_unretained id hit = nil;
	__block NSInteger hitSegment = 0;
	__block CGFloat bestDist = 1000000;
	[EditorMapLayer osmHitTestEnumerate:point mapView:mapView objects:objects testNodes:testNodes ignoreList:ignoreList block:^(OsmBaseObject * obj,CGFloat dist,NSInteger segment){
		if ( dist < bestDist ) {
			if ( dist < bestDist ) {
				bestDist = dist;
				hit = obj;
				hitSegment = segment;
			}
		}
	}];
	if ( bestDist <= 1.0 ) {
		if ( pSegment )
			*pSegment = hitSegment;
		return hit;
	}
	return nil;
}


-(NSArray *)shownObjects
{
	return _shownObjects;
}

- (OsmBaseObject *)osmHitTest:(CGPoint)point segment:(NSInteger *)segment ignoreList:(NSArray *)ignoreList
{
	if ( self.hidden )
		return nil;

	OsmBaseObject * hit = [EditorMapLayer osmHitTest:point mapView:_mapView objects:_shownObjects testNodes:NO ignoreList:ignoreList segment:segment];
	return hit;
}
- (OsmBaseObject *)osmHitTest:(CGPoint)point
{
	return [self osmHitTest:point segment:NULL ignoreList:nil];
}

// return close objects sorted by distance
- (NSArray *)osmHitTestMultiple:(CGPoint)point
{
	NSMutableSet * objectSet = [NSMutableSet new];
	[EditorMapLayer osmHitTestEnumerate:point mapView:self.mapView objects:_shownObjects testNodes:YES ignoreList:nil block:^(OsmBaseObject *obj, CGFloat dist, NSInteger segment) {
		[objectSet addObject:obj];
	}];
	NSMutableArray * objects = [objectSet.allObjects mutableCopy];
	[objects sortUsingComparator:^NSComparisonResult(OsmBaseObject * o1, OsmBaseObject * o2) {
		int diff = (o1.isNode?YES:NO) - (o2.isNode?YES:NO);
		if ( diff )
			return diff < 0 ? NSOrderedAscending : NSOrderedDescending;
		int64_t diff2 = o1.ident.longLongValue - o2.ident.longLongValue;
		return diff2 < 0 ? NSOrderedAscending : diff2 > 0 ? NSOrderedDescending : NSOrderedSame;
	}];
	return objects;
}


- (OsmBaseObject *)osmHitTestSelection:(CGPoint)point segment:(NSInteger *)segment
{
	if ( self.hidden )
		return nil;
	if ( _selectedWay ) {
		return [EditorMapLayer osmHitTest:point mapView:_mapView objects:@[_selectedWay] testNodes:NO ignoreList:nil segment:segment];
	}
	if ( _selectedNode ) {
		return [EditorMapLayer osmHitTest:point mapView:_mapView objects:@[_selectedNode] testNodes:YES ignoreList:nil segment:segment];
	}
	return nil;
}

- (OsmBaseObject *)osmHitTestSelection:(CGPoint)point
{
	return [self osmHitTestSelection:point segment:NULL];

}

-(OsmNode *)osmHitTestNodeInSelection:(CGPoint)point
{
	if ( _selectedWay == nil && _selectedNode == nil )
		return nil;
	NSMutableArray * list = [NSMutableArray new];
	for ( OsmNode * node in _selectedWay.nodeSet ) {
		[list addObject:node];
	}
	if ( _selectedNode ) {
		[list addObject:_selectedNode];
	}
	NSInteger segment;
	return (id) [EditorMapLayer osmHitTest:point mapView:_mapView objects:list testNodes:YES ignoreList:nil segment:&segment];
}

#pragma mark Copy/Paste

- (BOOL)copyTags:(OsmBaseObject *)object
{
	[[NSUserDefaults standardUserDefaults] setObject:object.tags forKey:@"copyPasteTags"];
	return object.tags.count > 0;
}
- (BOOL)canPasteTags
{
	NSDictionary * copyPasteTags = [[NSUserDefaults standardUserDefaults] objectForKey:@"copyPasteTags"];
	return copyPasteTags.count > 0;

}
- (BOOL)pasteTags:(OsmBaseObject *)object
{
	NSDictionary * copyPasteTags = [[NSUserDefaults standardUserDefaults] objectForKey:@"copyPasteTags"];
	if ( copyPasteTags.count == 0 )
		return NO;
	NSDictionary * newTags = MergeTags(object.tags, copyPasteTags);
	[self.mapData setTags:newTags forObject:object];
	return YES;
}



#pragma mark Editing

- (void)setSelectedRelation:(OsmRelation *)relation way:(OsmWay *)way node:(OsmNode *)node
{
	[self saveSelection];
	self.selectedWay  = way;
	self.selectedNode = node;
	self.selectedRelation = relation;
	[_mapView updateEditControl];
}
- (void)saveSelection
{
	id way		= _selectedWay  ?: [NSNull null];
	id node		= _selectedNode ?: [NSNull null];
	id relation = _selectedRelation ?: [NSNull null];
	[_mapData registerUndoWithTarget:self selector:@selector(setSelectedRelation:way:node:) objects:@[relation,way,node]];
}

- (void)adjustNode:(OsmNode *)node byDistance:(CGPoint)delta
{
	[self saveSelection];

	CGPoint pt = [_mapView viewPointForLatitude:node.lat longitude:node.lon];
	pt.x += delta.x;
	pt.y -= delta.y;
	CLLocationCoordinate2D loc = [_mapView longitudeLatitudeForViewPoint:pt];
	[_mapData setLongitude:loc.longitude latitude:loc.latitude forNode:node inWay:_selectedWay];

	[self setNeedsDisplay];
}


-(OsmNode *)createNodeAtPoint:(CGPoint)point
{
	[self saveSelection];

	CLLocationCoordinate2D loc = [_mapView longitudeLatitudeForViewPoint:point];
	OsmNode * node = [_mapData createNodeAtLocation:loc];
	[self setNeedsDisplay];
	return node;
}

-(OsmWay *)createWayWithNode:(OsmNode *)node
{
	[self saveSelection];

	OsmWay * way = [_mapData createWay];
	[_mapData addNode:node toWay:way atIndex:0];
	[self setNeedsDisplay];
	return way;
}

-(void)addNode:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index
{
	[self saveSelection];

	[_mapData addNode:node toWay:way atIndex:index];
	[self setNeedsDisplay];
}

-(void)deleteNode:(OsmNode *)node fromWay:(OsmWay *)way allowDegenerate:(BOOL)allowDegenerate
{
	[self saveSelection];

	BOOL needAreaFixup = way.nodes.lastObject == node  &&  way.nodes[0] == node;
	for ( NSInteger index = 0; index < way.nodes.count; ++index ) {
		if ( way.nodes[index] == node ) {
			[_mapData deleteNodeInWay:way index:index];
			--index;
		}
	}
	if ( way.nodes.count < 2 && !allowDegenerate ) {
		[_mapData deleteWay:way];
		[self setSelectedWay:nil];
	} else if ( needAreaFixup ) {
		// special case where deleted node is first & last node of an area
		[_mapData addNode:way.nodes[0] toWay:way atIndex:way.nodes.count];
	}
}
-(void)deleteNode:(OsmNode *)node fromWay:(OsmWay *)way
{
	[self saveSelection];

	[self deleteNode:node fromWay:way allowDegenerate:NO];
}

-(void)deleteSelectedObject
{
	[self saveSelection];

	if ( _selectedNode ) {

		// delete node from selected way
		if ( _selectedWay ) {
			[self deleteNode:_selectedNode fromWay:_selectedWay];
		} else {
			[_mapData deleteNode:_selectedNode];
		}
		
		// deselect node after we've removed it from ways
		[self setSelectedNode:nil];

	} else if ( _selectedWay ) {

		// delete way
		[_mapData deleteWay:_selectedWay];
		[self setSelectedWay:nil];
		[self setSelectedNode:nil];

	}
	for ( OsmBaseObject * object in _extraSelections ) {
		if ( object.isNode ) {
			[_mapData deleteNode:(id)object];
		} else if ( object.isWay ) {
			[_mapData deleteWay:(id)object];
		} else {
			assert(NO);
		}
	}
	[self clearExtraSelections];

	if ( _highlightObject.deleted ) {
		_highlightObject = nil;
	}

	[_speechBalloon removeFromSuperlayer];
	_speechBalloon = nil;

	[self setNeedsDisplay];
}

-(void)cancelOperation
{
	self.addNodeInProgress = NO;
	self.addWayInProgress = NO;
}


#pragma mark Highlighting and Selection

- (void)setSelectionChangeCallback:(void (^)(void))callback
{
	if ( _selectionChangeCallbacks == nil )
		_selectionChangeCallbacks = [NSMutableArray arrayWithObject:callback];
	else
		[_selectionChangeCallbacks addObject:callback];
}

-(void)setNeedsDisplayForObject:(OsmBaseObject *)object
{
#if 1
	[self setNeedsDisplay];
#else
	if ( object == nil ) {
		[self setNeedsDisplay];
		return;
	}
	if ( object.isWay ) {
		OSMRect box = [((OsmWay *)object) boundingBox];
		OSMPoint pt1 = [_mapView viewPointForLatitude:box.origin.y longitude:box.origin.x];
		OSMPoint pt2 = [_mapView viewPointForLatitude:box.origin.y+box.size.height longitude:box.origin.x+box.size.width];
		box.origin = pt1;
		box.size.width = pt2.x - pt1.x;
		box.size.height = pt1.y - pt2.y;
		box = NSInsetRect(box, -10, -10);
		box = NSOffsetRect(box, self.bounds.origin.x, self.bounds.origin.y);
		[self setNeedsDisplayInRect:box];
	} else {
		[self setNeedsDisplay];
	}
#endif
}

-(void)doSelectionChangeCallbacks
{
	for ( void (^callback)() in _selectionChangeCallbacks ) {
		callback();
	}
}
+ (NSSet *)keyPathsForValuesAffectingSelectedPrimary
{
	return [NSSet setWithObjects:@"selectedNode", @"selectedWay", nil];
}
-(OsmBaseObject *)selectedPrimary
{
	return _selectedNode ? _selectedNode : _selectedWay ? _selectedWay : _selectedRelation;
}
-(OsmNode *)selectedNode
{
	return _selectedNode;
}
-(OsmWay *)selectedWay
{
	return _selectedWay;
}
-(OsmRelation *)selectedRelation
{
	return _selectedRelation;
}
-(void)setSelectedNode:(OsmNode *)selectedNode
{
	assert( selectedNode == nil || selectedNode.isNode );
	if ( selectedNode != _selectedNode ) {
		_selectedNode = selectedNode;
		[self setNeedsDisplayForObject:selectedNode];
		[self doSelectionChangeCallbacks];
		[_mapView updateEditControl];
	}
}
-(void)setSelectedWay:(OsmWay *)selectedWay
{
	assert( selectedWay == nil || selectedWay.isWay );
	if ( selectedWay != _selectedWay ) {
		_selectedWay = selectedWay;
		[self setNeedsDisplayForObject:selectedWay];
		[self doSelectionChangeCallbacks];
		[_mapView updateEditControl];
	}
}
-(void)setSelectedRelation:(OsmRelation *)selectedRelation
{
	assert( selectedRelation == nil || selectedRelation.isRelation );
	if ( selectedRelation != _selectedRelation ) {
		_selectedRelation = selectedRelation;
		[self setNeedsDisplayForObject:selectedRelation];
		[self doSelectionChangeCallbacks];
		[_mapView updateEditControl];
	}
}

- (void)toggleExtraSelection:(OsmBaseObject *)object
{
	if ( [_extraSelections containsObject:object] ) {
		[_extraSelections removeObject:object];
	} else {
		if ( _extraSelections == nil )
			_extraSelections = [NSMutableArray arrayWithObject:object];
		else
			[_extraSelections addObject:object];
	}
	[self setNeedsDisplay];
	[self doSelectionChangeCallbacks];
}
- (void)clearExtraSelections
{
	if ( _extraSelections ) {
		_extraSelections = nil;
		[self setNeedsDisplay];
		[self doSelectionChangeCallbacks];
	}
}
- (NSArray *)extraSelections
{
	return _extraSelections ? [NSArray arrayWithArray:_extraSelections] : nil;
}


-(void)osmHighlightObject:(OsmBaseObject *)object mousePoint:(CGPoint)mousePoint
{
	if ( object != _highlightObject ) {
		_highlightObject = object;
		[self setNeedsDisplay];
	}
	NSString * name = [_highlightObject friendlyDescription];
	if ( name ) {
		if ( _speechBalloon == nil ) {
			_speechBalloon = [SpeechBalloonLayer new];
			[self addSublayer:_speechBalloon];
		}
		if ( _highlightObject.isNode ) {
			OsmNode * n = (id)_highlightObject;
			mousePoint = CGPointFromOSMPoint( [self pointForLat:n.lat lon:n.lon] );
		} else {
			mousePoint = [self convertPoint:mousePoint fromLayer:_mapView.layer];
		}
		[CATransaction begin];
		[CATransaction setAnimationDuration:0.0];
		_speechBalloon.position = mousePoint;
		_speechBalloon.text = name;
		[CATransaction commit];

		_speechBalloon.hidden = NO;
	} else {
		_speechBalloon.hidden = YES;
	}
}

#pragma mark Properties

-(void)setHidden:(BOOL)hidden
{
	BOOL wasHidden = self.hidden;
	[super setHidden:hidden];

	if ( wasHidden && !hidden ) {
		[self updateMapLocation];
	}
}

-(NSColor *)textColor
{
	return _textColor;
}
-(void)setTextColor:(NSColor *)textColor
{
	if ( ! [_textColor isEqual:textColor] ) {
#if TARGET_OS_IPHONE
		CGFloat r,g,b,a;
		if ( ![textColor getRed:&r green:&g blue:&b alpha:&a] ) {
			if ( [textColor getWhite:&r alpha:&a] ) {
				g = b = r;
			}
		}
		_textColor = [UIColor colorWithRed:r green:g blue:b alpha:a];
#else
		_textColor = [textColor colorUsingColorSpaceName:NSDeviceRGBColorSpace];
#endif
		[self setNeedsDisplay];
	}
}

@end
