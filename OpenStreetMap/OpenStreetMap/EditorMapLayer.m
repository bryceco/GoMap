//
//  OsmMapLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

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
		_mapData = [[OsmMapData alloc] initWithCachedData];
		double delta = [[NSDate date] timeIntervalSinceDate:startDate];
		DLog(@"Load time = %f seconds",delta);
#if TARGET_OS_IPHONE
		if ( _mapData && delta > 5.0 ) {
			NSString * text = @"Your OSM data cache is getting large, which may lead to slow startup and shutdown times. You may want to clear the cache (under Settings) to improve performance.";
			UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Cache size warning" message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
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
	// First save just modified objects, which we can do very fast, in case we get killed during full save
	OsmMapData * modified = [_mapData modifiedObjects];

	// save modified data first, in case full save fails
	[modified saveSubstitutingSpatial:YES];

	// Next try to save everything. Since we save atomically this won't overwrite the fast save unless it succeeeds.
	[_mapData saveSubstitutingSpatial:NO];
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

- (void)updateIconSize
{
	const double minIconSizeInPixels = 24;
	const double minIconSizeInMeters = 4.0;
	double metersPerPixel = [_mapView metersPerPixel];
	if ( minIconSizeInPixels * metersPerPixel < minIconSizeInMeters ) {
		_iconSize.width  = minIconSizeInMeters / metersPerPixel;
		_iconSize.height = minIconSizeInMeters / metersPerPixel;
	} else {
		_iconSize.width	 = minIconSizeInPixels;
		_iconSize.height = minIconSizeInPixels;
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
			[_mapView presentError:error];
		} else {
			[self setNeedsDisplay];
		}
	}];
}

-(void)didReceiveMemoryWarning
{
	[self purgeCachedDataHard:NO];
	[self save];
}

#pragma mark Draw Ocean

static void AppendNodes( NSMutableArray * list, OsmWay * way, BOOL back )
{
	if ( back ) {
		BOOL first = YES;
		for ( OsmNode * node in way.nodes ) {
			if ( first )
				first = NO;
			else
				[list addObject:node];
		}
	} else {
		NSMutableArray * a = [NSMutableArray arrayWithCapacity:way.nodes.count];
		for ( OsmNode * node in way.nodes ) {
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
	CGFloat sum = 0;
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

	assert( crossCnt <= 2 );
	for ( NSInteger i = 0; i < crossCnt; ++i ) {
		assert( IsPointInRect(pts[i], rect) );
	}
	return crossCnt;
}


-(void)drawOceans:(NSArray *)objectList context:(CGContextRef)ctx
{
	NSMutableSet * segments = [NSMutableSet new];
	for ( id obj in objectList ) {
		OsmBaseObject * object = obj;
		if ( [object isKindOfClass:[ObjectSubpart class]] )
			object = [(ObjectSubpart *)object object];
		if ( [[object.tags valueForKey:@"natural"] isEqualToString:@"coastline"] ) {
			[segments addObject:object];
		}
	}
	if ( segments.count == 0 )
		return;
	NSMutableArray * outlineList = [NSMutableArray new];
	while ( segments.count ) {
		// find all connected segments
		OsmWay * way = segments.anyObject;
		[segments removeObject:way];
		OsmNode * firstNode = way.nodes[0];
		OsmNode * lastNode = way.nodes.lastObject;
		NSMutableArray * nodeList = [NSMutableArray arrayWithObject:firstNode];
		AppendNodes( nodeList, way, YES );
		while ( nodeList[0] != nodeList.lastObject ) {
			// find a way adjacent to current list
			for ( way in segments ) {
				if ( way.nodes[0] == lastNode ) {
					AppendNodes( nodeList, way, YES );
					lastNode = nodeList.lastObject;
					break;
				}
				if ( way.nodes.lastObject == firstNode ) {
					AppendNodes( nodeList, way, NO );
					firstNode = nodeList[0];
					break;
				}
			}
			if ( way == nil )
				break;
			[segments removeObject:way];
		}
		[outlineList addObject:nodeList];
	}
	segments = nil;
	CGRect cgViewRect = self.bounds;
	OSMRect viewRect = { cgViewRect.origin.x, cgViewRect.origin.y, cgViewRect.size.width, cgViewRect.size.height };
	CGPoint viewCenter = { viewRect.origin.x+viewRect.size.width/2, viewRect.origin.y+viewRect.size.height/2 };

	// convert nodes to points
	for ( NSMutableArray * outline in outlineList ) {
		BOOL isLoop = outline[0] == outline.lastObject;
		for ( NSInteger index = 0, count = outline.count; index < count; ++index ) {
			if ( isLoop && index == count-1 ) {
				outline[index] = outline[0];
			} else {
				OsmNode * node = outline[index];
				OSMPoint pt = [self pointForLat:node.lat lon:node.lon];
				outline[index] = [OSMPointBoxed pointWithPoint:pt];
			}
		}
	}

	// trim nodes in outlines to only internal paths
	NSMutableArray * islands = nil;
	NSMutableArray * outlineList2 = [NSMutableArray new];
	for ( NSMutableArray * outline in outlineList ) {
		BOOL first = YES;
		BOOL prevInside;
		BOOL isLoop = outline[0] == outline.lastObject;
		OSMPoint prevPoint;
		NSInteger index = 0;
		NSInteger lastEntry = -1;
		NSMutableArray * outline2 = nil;

		if ( isLoop ) {
			BOOL ok = RotateLoop(outline, viewRect);
			if ( !ok ) {
				// entire loop is inside view
				if ( islands == nil ) {
					islands = [NSMutableArray arrayWithObject:outline];
				} else {
					[islands addObject:outline];
				}
				continue;
			}
		}

		for ( OSMPointBoxed * value in outline ) {
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

				if ( index == 1 && isInside && !isEntry ) {
					// DLog(@"first node is not outside");
					return;
				}

				OSMPoint pts[ 2 ];
				NSInteger crossCnt = (isEntry || isExit) ? ClipLineToRect( prevPoint, pt, viewRect, pts ) : 0;
				if ( isEntry ) {
					assert( crossCnt >= 1 );
					OSMPointBoxed * v = [OSMPointBoxed pointWithPoint:pts[0] ];
					outline2 = [NSMutableArray arrayWithObject:v];
					[outlineList2 addObject:outline2];
					lastEntry = index-1;
				}
				if ( isExit ) {
					assert( crossCnt >= 1 );
					OSMPointBoxed * v = [OSMPointBoxed pointWithPoint:pts[crossCnt-1]];
					[outline2 addObject:v];
					outline2 = nil;
				} else if ( isInside ) {
					[outline2 addObject:value];
				}
			}
			prevInside = isInside;
			prevPoint = pt;
			++index;
		}
		if ( lastEntry < 0 ) {
			// never intersects screen
		} else if ( outline2 ) {
			// entered but never exited
			return;
		}
	}
	outlineList = outlineList2;
	outlineList2 = nil;

	for ( id island in islands ) {
		[outlineList removeObject:island];
	}

	[outlineList filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * outline, NSDictionary *bindings) {
		return outline.count > 0;
	}]];
	if ( outlineList.count == 0 && islands.count == 0 )
		return;

	// get list of all external points
	NSMutableSet * pointSet = [NSMutableSet new];
	NSMutableDictionary * entryDict = [NSMutableDictionary new];
	for ( NSArray * outline in outlineList ) {
		[pointSet addObject:outline[0]];
		[pointSet addObject:outline.lastObject];
		[entryDict setObject:outline forKey:outline[0]];
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
	for ( NSArray * outline in outlineList ) {
		OSMPoint p1 = [outline[0] pointValue];
		OSMPoint p2 = [outline[1] pointValue];
		CGContextBeginPath(ctx);
		CGContextSetLineCap(ctx, kCGLineCapRound);
		CGContextMoveToPoint(ctx, p1.x, p1.y);
		CGContextAddLineToPoint(ctx, p2.x, p2.y);
		CGContextSetLineWidth(ctx, 6);
		CGContextSetRGBStrokeColor(ctx, 0, 1, 0, 1);	// green
		CGContextStrokePath(ctx);
		//
		p1 = [outline.lastObject pointValue];
		p2 = [outline[outline.count-2] pointValue];
		CGContextBeginPath(ctx);
		CGContextMoveToPoint(ctx, p1.x, p1.y);
		CGContextAddLineToPoint(ctx, p2.x, p2.y);
		CGContextSetLineWidth(ctx, 6);
		CGContextSetRGBStrokeColor(ctx, 1, 0, 0, 1);	// green
		CGContextStrokePath(ctx);
	}
#endif

	// now have a set of discontiguous arrays of coastline nodes, add points at screen corners to connect them
	BOOL haveCoastline = NO;
	CGContextBeginPath(ctx);
	while ( outlineList.count ) {

		BOOL firstPoint = YES;
		NSArray * firstOutline = outlineList.lastObject;
		OSMPointBoxed * exit  = firstOutline.lastObject;
		[outlineList removeObject:firstOutline];

		for ( OSMPointBoxed * value in firstOutline ) {
			OSMPoint pt = value.point;
			if ( firstPoint ) {
				firstPoint = NO;
				CGContextMoveToPoint( ctx, pt.x, pt.y );
			} else {
				CGContextAddLineToPoint( ctx, pt.x, pt.y );
			}
		}

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
			if ( ![outlineList containsObject:nextOutline] ) {
				return;
			}
			for ( OSMPointBoxed * value in nextOutline ) {
				OSMPoint pt = value.point;
				CGContextAddLineToPoint( ctx, pt.x, pt.y );
			}

			exit = nextOutline.lastObject;
			[outlineList removeObject:nextOutline];
		}
	}
	BOOL first = NO;
	for ( NSArray * island in islands ) {
		first = YES;
		for ( OSMPointBoxed * value in island ) {
			OSMPoint pt = value.point;
			if ( first ) {
				first = NO;
				CGContextMoveToPoint( ctx, pt.x, pt.y );
			} else {
				CGContextAddLineToPoint( ctx, pt.x, pt.y );
			}
		}
		if ( !haveCoastline && IsClockwisePolygon(island) ) {
			// this will still fail if we have an island with a lake in it
			haveCoastline = YES;
		}
	}
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
	if ( [[subpart.object.tags valueForKey:@"natural"] isEqualToString:@"coastline"] && subpart.object.isWay) {
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

-(BOOL)drawArea:(OsmWay *)way context:(CGContextRef)ctx
{
	if ( !way.isArea )
		return NO;

	TagInfo * tagInfo = way.tagInfo;
	if ( tagInfo.areaColor == nil )
		return NO;
	RGBAColor	fillColor;
	[tagInfo.areaColor getRed:&fillColor.red green:&fillColor.green blue:&fillColor.blue alpha:&fillColor.alpha];
	CGPathRef path = [self pathForWay:way];
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);
	CGContextSetRGBFillColor(ctx, fillColor.red, fillColor.green, fillColor.blue, 0.25);
	CGContextFillPath(ctx);
	CGPathRelease(path);
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

-(BOOL)drawWayCasing:(OsmWay *)way context:(CGContextRef)ctx
{
	if ( [way isKindOfClass:[ObjectSubpart class]] )
		return NO;

	if ( way.isArea )
		return NO;

	TagInfo * tagInfo = way.tagInfo;
	if ( tagInfo.lineWidth == 0 )
		return NO;

	CGPathRef path = [self pathForWay:way];
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);

	CGFloat red = 0.2, green = 0.2, blue = 0.2, alpha = 1.0;
	CGContextSetRGBStrokeColor(ctx, red, green, blue, alpha);
	CGContextSetLineWidth(ctx, (1+tagInfo.lineWidth)*_highwayScale);
	CGContextStrokePath(ctx);

	CGPathRelease(path);
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

-(BOOL)drawWay:(OsmWay *)way context:(CGContextRef)ctx
{
	NSString * name = [way.tags objectForKey:@"name"];
	if ( [name isEqualToString:@"Test"] ) {
		name = nil;
	}

	TagInfo * tagInfo = way.tagInfo;
	assert( tagInfo );

	//	DLog(@"draw way: %ld nodes", way.nodes.count);

	CGPathRef path = [self pathForWay:way];
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);

	CGFloat red = 0, green = 0, blue = 0, alpha = 1;
	[tagInfo.lineColor getRed:&red green:&green blue:&blue alpha:&alpha];
	CGContextSetRGBStrokeColor(ctx, red, green, blue, alpha);
	CGFloat lineWidth = tagInfo.lineWidth*_highwayScale;
	if ( lineWidth == 0 )
		lineWidth = 1;
	CGContextSetLineWidth(ctx, lineWidth);
	CGContextStrokePath(ctx);

	if ( way.isOneWay ) {
		[self drawArrowsForPath:path context:ctx];
	}

	CGPathRelease(path);
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

		[CurvedTextLayer drawString:name centeredOnPoint:cgPoint font:nil color:self.textColor shadowColor:ShadowColorForColor2(self.textColor) context:ctx];
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


-(BOOL)drawWayName:(OsmWay *)way context:(CGContextRef)ctx
{
	const CGFloat Pixels_Per_Character = 8.0;

	// add street names
	NSString * name = [way.tags valueForKey:@"name"];
	if ( name == nil )
		name = DrawNodeAsHouseNumber( way.tags );
	if ( name == nil )
		return NO;

	// don't draw the same name twice
	if ( [_nameDrawSet containsObject:name] )
		return NO;
	[_nameDrawSet addObject:name];

	//	DLog(@"draw way: %ld nodes", way.nodes.count);

	BOOL area = way.nodes.count >= 3 && way.nodes[0] == way.nodes.lastObject;
	if ( !area ) {

		double length = 0.0;
		CGPathRef path = [self pathClippedToViewRect:way length:&length];
		double offset = (length - name.length * Pixels_Per_Character) / 2;
		if ( offset < 0 ) {
			CGPathRelease( path );
			return NO;
		}

		CGContextBeginPath(ctx);
		CGContextAddPath(ctx, path);
		[CurvedTextLayer drawString:name alongPath:path offset:offset color:self.textColor shadowColor:ShadowColorForColor2(self.textColor) context:ctx];
		CGPathRelease(path);

	} else {

		// don't draw names on objects too narrow for the label
		OSMRect bbox = [way boundingBox];
		double pixelWidth = bbox.size.width * MetersPerDegree( bbox.origin.y ) / _mapView.metersPerPixel;
		if ( name.length * Pixels_Per_Character > pixelWidth * 1.5 )
			return NO;
		
		OSMPoint point = [way centerPoint];
		point = [self pointForLat:point.y lon:point.x];
		CGPoint cgPoint = CGPointFromOSMPoint(point);
		UIFont * font = [UIFont systemFontOfSize:11];
		UIColor * shadowColor = ShadowColorForColor2(self.textColor);
		[CurvedTextLayer drawString:name centeredOnPoint:cgPoint font:font color:self.textColor shadowColor:shadowColor context:ctx];
	}
	return YES;
}


-(BOOL)drawNode:(OsmNode *)node context:(CGContextRef)ctx
{
	if ( _mapCss ) {
		ObjectSubpart * subpart = (id)node;
		OsmBaseObject * object = subpart.object;
		if ( !object.isNode && !(object.isWay && ((OsmWay *)object).isArea) )
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
		pt = [((OsmWay *)node) centerPoint];
		pt = [self pointForLat:pt.y lon:pt.x];
	} else {
		assert(NO);
		return NO;
	}

	TagInfo * tagInfo = node.tagInfo;
	if ( tagInfo.icon ) {

		// draw with icon
		pt.x = round(pt.x);	// performance optimization when drawing images
		pt.y = round(pt.y);
		CGContextSaveGState(ctx);
		CGContextTranslateCTM(ctx, 0, pt.y+_iconSize.height);
		CGContextScaleCTM(ctx, 1.0, -1.0);
		CGRect rect = CGRectMake(pt.x-_iconSize.width/2, _iconSize.height/2, _iconSize.width, _iconSize.height);
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, NSColor.whiteColor.CGColor );
		CGContextDrawImage( ctx, rect, tagInfo.cgIcon );
		CGContextRestoreGState(ctx);

	} else {

		// draw generic box
		CGContextSetLineWidth(ctx, 2.0);
		CGFloat red, green, blue;
		if ( node.tags.count ) {
			if ( [node.tags objectForKey:@"shop"] ) {
				red = 0xAC/255.0;
				green = 0x39/255.0;
				blue = 0xAC/255.0;
			} else if ( [node.tags objectForKey:@"amenity"] ) {
				red = 0x73/255.0;
				green = 0x4A/255.0;
				blue = 0x08/255.0;
			} else if ( [node.tags objectForKey:@"tourism"] || [node.tags objectForKey:@"transport"] ) {
				red = 0x00/255.0;
				green = 0x92/255.0;
				blue = 0xDA/255.0;
			} else if ( [node.tags objectForKey:@"medical"] ) {
				red = 0xDA/255.0;
				green = 0x00/255.0;
				blue = 0x92/255.0;
			} else {
				red = 0;
				green = 0;
				blue = 1;
			}
		} else {
			// gray for untagged nodes
			green = blue = red = 0.5;
		}
		CGContextSetRGBStrokeColor(ctx, red, green, blue, 1.0);

		NSString * houseNumber = DrawNodeAsHouseNumber( node.tags );
		if ( houseNumber ) {

			UIColor * shadowColor = ShadowColorForColor2(self.textColor);
			CGPoint point = CGPointFromOSMPoint(pt);
			[CurvedTextLayer drawString:houseNumber	centeredOnPoint:point font:nil color:self.textColor shadowColor:shadowColor context:ctx];

		} else {

			pt.x = round(pt.x);	// performance optimization when drawing images
			pt.y = round(pt.y);
			CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, ShadowColorForColor(red, green, blue).CGColor );
			CGRect rect = CGRectMake(pt.x + - _iconSize.width/4, pt.y - _iconSize.height/4, _iconSize.width/2, _iconSize.height/2);
			CGContextBeginPath(ctx);
			CGContextAddRect(ctx, rect);
			CGContextStrokePath(ctx);
		}
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
	[_mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
		if ( !obj.deleted ) {
			if ( obj.isWay ) {
				[a addObject:obj];
				for ( OsmNode * node in ((OsmWay *)obj).nodes ) {
					if ( ShouldDisplayNodeInWay( node.tags ) ) {
						[a addObject:node];
					}
				}
			} else if ( obj.isNode ) {
				if ( ((OsmNode *)obj).wayCount == 0 ) {
					[a addObject:obj];
				}
			}
		}
	}];
//	DLog(@"%ld ways, %ld nodes", (long)wayCount, (long)nodeCount);
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



static NSComparisonResult VisibleSizeCompare( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	// always display dirty objects
	NSInteger diff = obj1.modifyCount - obj2.modifyCount;
	if ( diff ) {
		return diff > 0 ? NSOrderedAscending : NSOrderedDescending;
	}

	NSInteger size1 = [obj1.tagInfo renderSize:obj1];
	NSInteger size2 = [obj2.tagInfo renderSize:obj2];
	if ( size1 > size2 ) return NSOrderedAscending;
	if ( size1 < size2 ) return NSOrderedDescending;
	return NSOrderedSame;
}

static NSComparisonResult VisibleSizeCompareStrict( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	NSComparisonResult diff1 = VisibleSizeCompare( obj1, obj2 );
	if ( diff1 )
		return diff1;

	// break ties by showing older stuff first
	OsmIdentifier diff2 = obj1.changeset - obj2.changeset;
	if ( diff2 )
		return diff2 > 0 ? NSOrderedAscending : NSOrderedDescending;
	diff2 = obj1.ident.longLongValue - obj2.ident.longLongValue;
	return diff2 > 0 ? NSOrderedAscending : NSOrderedDescending;
}
static BOOL VisibleSizeLess( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	NSComparisonResult result = VisibleSizeCompareStrict( obj1, obj2 );
	return result < 0;
}

- (void)drawInContext:(CGContextRef)ctx
{
#if 0
	// these have no affect on performance:
	CGContextSetShouldAntialias(ctx, NO);
	CGContextSetShouldSmoothFonts(ctx, NO);
	CGContextSetShouldSubpixelPositionFonts(ctx, NO);
	CGContextSetShouldSubpixelQuantizeFonts(ctx, NO);
#endif

	_nameDrawSet = [NSMutableSet new];

	if ( _mapCss ) {
		[self drawMapCssInContext:ctx];
		return;
	}

#if TARGET_OS_IPHONE
	NSInteger objectLimit = 100;
	NSInteger nameLimit = 10;
#else
	NSInteger objectLimit = 500;
	NSInteger nameLimit = 100;
#endif

	CFTimeInterval totalTime = CACurrentMediaTime();

	// get objects in visible rect
	_shownObjects = [self getVisibleObjects];

	// get taginfo for objects
	for ( OsmBaseObject * object in _shownObjects ) {
		if ( object.tagInfo == nil ) {
			object.tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForObject:object];
		}
	}

	// sort from big to small objects
	[_shownObjects partialSortK:objectLimit compare:VisibleSizeLess];

	// adjust the list of objects so that we get all or none of the same type
	if ( _shownObjects.count > objectLimit ) {
		// We have more objects available than we want to display. If some of the objects are the same size as the last visible object then include those too.
		NSInteger lastIndex = objectLimit;
		OsmBaseObject * last = _shownObjects[ objectLimit-1 ];
		for ( NSInteger i = objectLimit, e = _shownObjects.count; i < e; ++i ) {
			if ( VisibleSizeCompare( last, _shownObjects[i] ) == NSOrderedSame ) {
				_shownObjects[lastIndex++] = _shownObjects[i];
			}
		}
		if ( lastIndex - objectLimit >= objectLimit ) {
			// we doubled the number of objects, so back off instead
			NSMutableArray * newList = [NSMutableArray arrayWithCapacity:objectLimit];
			for ( NSInteger i = objectLimit-1; i >= 0; --i ) {
				OsmBaseObject * item = _shownObjects[ i ];
				if ( VisibleSizeCompare( item, last ) == NSOrderedAscending ) {
					[newList addObject:item];
				}
			}
			if ( newList.count >= 1 ) {
				_shownObjects = newList;
				lastIndex = _shownObjects.count;
			}
		}
		DLog( @"added %ld same", (long)lastIndex - objectLimit);
		objectLimit = lastIndex;

		// remove unwanted objects
		NSIndexSet * range = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(objectLimit,_shownObjects.count-objectLimit)];
		[_shownObjects removeObjectsAtIndexes:range];
	}

	[self drawOceans:_shownObjects context:ctx];

	int areaCount = 0;
	int casingCount = 0;
	int wayCount = 0;
	int nodeCount = 0;
	int nameCount = 0;

	// draw areas
	CFTimeInterval areaTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isWay ) {
			areaCount += [self drawArea:(id)obj context:ctx];
		}
	}
	areaTime = CACurrentMediaTime() - areaTime;

	// draw casings
	CFTimeInterval casingTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isWay ) {
			casingCount += [self drawWayCasing:(id)obj context:ctx];
		}
	}
	casingTime = CACurrentMediaTime() - casingTime;

	// draw ways
	CFTimeInterval wayTime = CACurrentMediaTime();
	for ( OsmBaseObject * obj in _shownObjects ) {
		if ( obj.isWay ) {
			wayCount += [self drawWay:(id)obj context:ctx];
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
		if ( obj.isWay ) {
			BOOL drawn = [self drawWayName:(id)obj context:ctx];
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

#if 1
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
	CGFloat dist = sqrt( delta.x*delta.x + delta.y*delta.y);
	return dist;
}

+ (OsmBaseObject *)osmHitTest:(CGPoint)point mapView:(MapView *)mapView objects:(NSArray *)objects testNodes:(BOOL)testNodes
					ignoreList:(NSArray *)ignoreList segment:(NSInteger *)segment
{
	CGSize iconSize = CGSizeMake(16, 16);
	CLLocationCoordinate2D location = [mapView longitudeLatitudeForViewPoint:point];
	OSMRect viewCoord = [mapView viewportLongitudeLatitude];
	OSMSize pixelsPerDegree = { mapView.bounds.size.width / viewCoord.size.width, mapView.bounds.size.height / viewCoord.size.height };

	__unsafe_unretained id hit = nil;
	NSInteger hitSegment = 0;
	CGFloat bestDist = 1000000;

	OSMSize maxDegreesNode = { iconSize.width  / pixelsPerDegree.width, iconSize.height / pixelsPerDegree.height };
	OSMSize maxDegreesWay = { WayHitTestRadius / pixelsPerDegree.width, WayHitTestRadius / pixelsPerDegree.height };

	for ( OsmBaseObject * object in objects ) {
		if ( object.deleted )
			continue;
		if ( object.isNode ) {
			OsmNode * node = (id)object;
			if ( ![ignoreList containsObject:node] ) {
				if ( segment || testNodes || node.wayCount == 0 ) {
					CGFloat dist = [self osmHitTest:location maxDegrees:maxDegreesNode forNode:node];
					if ( dist < bestDist ) {
						if ( dist < bestDist ) {
							bestDist = dist;
							hit = node;
						}
					}
				}
			}
		} else if ( object.isWay ) {
			OsmWay * way = (id)object;
			if ( ![ignoreList containsObject:way] ) {
				NSInteger seg;
				CGFloat dist = [self osmHitTest:location maxDegrees:maxDegreesWay forWay:way segment:&seg];
				if ( dist < bestDist ) {
					if ( dist < bestDist ) {
						bestDist = dist;
						hit = way;
						hitSegment = seg;
					}
				}
			}
			if ( testNodes ) {
				for ( OsmNode * node in way.nodes ) {
					if ( [ignoreList containsObject:node] )
						continue;
					CGFloat dist = [self osmHitTest:location maxDegrees:maxDegreesNode forNode:node];
					if ( dist < bestDist ) {
						if ( dist < bestDist ) {
							bestDist = dist;
							hit = node;
						}
					}
				}
			}
		}
	}

	if ( bestDist <= 1.0 ) {
		if ( segment )
			*segment = hitSegment;
		return hit;
	}
	return nil;
}

- (NSArray *)objectsNearPoint:(CGPoint)point
{
	// get list of objects to hit test
	CGSize iconSize = CGSizeMake(16, 16);
	CLLocationCoordinate2D location = [_mapView longitudeLatitudeForViewPoint:point];
	OSMRect viewCoord = [_mapView viewportLongitudeLatitude];
	OSMSize pixelsPerDegree = { _mapView.bounds.size.width / viewCoord.size.width, _mapView.bounds.size.height / viewCoord.size.height };

	OSMSize maxDegreesNode = { iconSize.width  / pixelsPerDegree.width, iconSize.height / pixelsPerDegree.height };
	OSMSize maxDegreesWay = { WayHitTestRadius / pixelsPerDegree.width, WayHitTestRadius / pixelsPerDegree.height };
	OSMSize size = { MAX( maxDegreesNode.width, maxDegreesWay.width ), MAX( maxDegreesNode.height, maxDegreesWay.height ) };
	OSMRect hitRect = { location.longitude - size.width/2, location.latitude - size.height/2, size.width, size.height };

	__block NSMutableArray * objects = [NSMutableArray new];
	[_mapData enumerateObjectsInRegion:hitRect block:^(OsmBaseObject * object){
		[objects addObject:object];
	}];
	return objects;
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

#pragma mark Action Sheet

enum {
	ACTION_SPLIT,
	ACTION_RECT,
	ACTION_STRAIGHTEN,
	ACTION_REVERSE,
	ACTION_DUPLICATE,
	ACTION_JOIN,
	ACTION_DISCONNECT,
	ACTION_COPYTAGS,
	ACTION_PASTETAGS,
};
static NSString * ActionTitle[] = {
	@"Split",
	@"Make Rectangular",
	@"Straighten",
	@"Reverse",
	@"Duplicate",
	@"Join",
	@"Disconnect",
	@"Copy Tags",
	@"Paste Tags",
};

- (void)updateActionButton
{
	self.mapView.actionButton.hidden = !(_selectedWay || _selectedNode) || _selectedRelation;
}
- (void)actionButton:(id)sender
{
	_actionSheet = nil;
	_actionList = nil;
	if ( _selectedRelation ) {
		// relation
		_actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS) ];
	} else if ( _selectedWay ) {
		if ( _selectedNode ) {
			// node in way
			if ( _selectedNode.wayCount > 1 ) {
				_actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS), @(ACTION_DISCONNECT), @(ACTION_JOIN) ];
			} else {
				_actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS), @(ACTION_SPLIT) ];
			}
		} else {
			if ( _selectedWay.isClosed ) {
				// polygon
				_actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS), @(ACTION_RECT), @(ACTION_DUPLICATE) ];
			} else {
				// line
				_actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS), @(ACTION_STRAIGHTEN), @(ACTION_REVERSE), @(ACTION_DUPLICATE) ];
			}
		}
	} else if ( _selectedNode ) {
		// node
		_actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS), @(ACTION_DUPLICATE) ];
	} else {
		// nothing selected
		return;
	}
	_actionSheet = [[UIActionSheet alloc] initWithTitle:@"Perform Action" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
	for ( NSNumber * value in _actionList ) {
		NSString * title = ActionTitle[ value.integerValue ];
		[_actionSheet addButtonWithTitle:title];
	}
	_actionSheet.cancelButtonIndex = [_actionSheet addButtonWithTitle:@"Cancel"];

	[_actionSheet showFromRect:self.mapView.actionButton.frame inView:self.mapView animated:YES];
}
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if ( actionSheet != _actionSheet || _actionList == nil || buttonIndex >= _actionList.count )
		return;
	NSInteger action = [_actionList[ buttonIndex ] integerValue];
	NSString * error = nil;
	switch (action) {
		case ACTION_COPYTAGS:
			if ( ! [self.mapData copyTags:self.selectedPrimary] )
				error = @"The object does contain any tags";
			break;
		case ACTION_PASTETAGS:
			if ( ! [self.mapData pasteTags:self.selectedPrimary] )
				error = @"No tags to paste";
			break;
		case ACTION_DUPLICATE:
			assert(NO);
			break;
		case ACTION_RECT:
			if ( ! [self.mapData orthogonalizeWay:self.selectedWay] )
				error = @"The way is not sufficiently rectangular";
			break;
		case ACTION_REVERSE:
			if ( ![self.mapData reverseWay:self.selectedWay] )
				error = @"Cannot reverse way";
			break;
		case ACTION_JOIN:
			if ( ![self.mapData joinWay:self.selectedWay atNode:self.selectedNode] )
				error = @"Cannot join selection";
			break;
		case ACTION_DISCONNECT:
			if ( ! [self.mapData disconnectWay:self.selectedWay atNode:self.selectedNode] )
				error = @"Cannot disconnect way";
			break;
		case ACTION_SPLIT:
			if ( ! [self.mapData splitWay:self.selectedWay atNode:self.selectedNode] )
				error = @"Cannot split way";
			break;
		case ACTION_STRAIGHTEN:
			if ( ! [self.mapData straightenWay:self.selectedWay] )
				error = @"The way is not sufficiently straight";
			break;
		default:
			break;
	}
	if ( error ) {
		UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:error message:nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
		[alertView show];
	}

	[self setNeedsDisplay];
	[self.mapView refreshPushpinText];

	_actionSheet = nil;
	_actionList = nil;
}

#pragma mark Editing

- (void)setSelectedRelation:(OsmRelation *)relation way:(OsmWay *)way node:(OsmNode *)node
{
	[self saveSelection];
	self.selectedWay  = way;
	self.selectedNode = node;
	self.selectedRelation = relation;
	[self updateActionButton];
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
		[self updateActionButton];
	}
}
-(void)setSelectedWay:(OsmWay *)selectedWay
{
	assert( selectedWay == nil || selectedWay.isWay );
	if ( selectedWay != _selectedWay ) {
		_selectedWay = selectedWay;
		[self setNeedsDisplayForObject:selectedWay];
		[self doSelectionChangeCallbacks];
		[self updateActionButton];
	}
}
-(void)setSelectedRelation:(OsmRelation *)selectedRelation
{
	assert( selectedRelation == nil || selectedRelation.isRelation );
	if ( selectedRelation != _selectedRelation ) {
		_selectedRelation = selectedRelation;
		[self setNeedsDisplayForObject:selectedRelation];
		[self doSelectionChangeCallbacks];
		[self updateActionButton];
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
