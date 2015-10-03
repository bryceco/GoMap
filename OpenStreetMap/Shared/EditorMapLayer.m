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
#import "AppDelegate.h"
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


#define USE_SHAPELAYERS		1
#define FADE_INOUT			0
#define SINGLE_SIDED_WALLS	1

#define PATH_SCALING	(256*256.0)		// scale up sizes in paths so Core Animation doesn't round them off


#define DEFAULT_LINECAP		kCALineCapSquare
#define DEFAULT_LINEJOIN	kCALineJoinMiter

const CGFloat Pixels_Per_Character = 8.0;


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


@interface LayerProperties : NSObject
{
@public
	OSMPoint		position;
	double			lineWidth;
	CATransform3D	transform;
	BOOL			is3D;
}
@end
@implementation LayerProperties
-(instancetype)init
{
	self = [super init];
	if ( self ) {
		transform = CATransform3DIdentity;
	}
	return self;
}
@end


@implementation EditorMapLayer

@synthesize mapView				= _mapView;
@synthesize whiteText			= _whiteText;
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

		self.whiteText = YES;

		_fadingOutSet = [NSMutableSet new];

		// observe changes to geometry
		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];

		[OsmMapData setEditorMapLayerForArchive:self];

		AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
		if ( !appDelegate.isAppUpgrade ) {
			CFTimeInterval t = CACurrentMediaTime();
			_mapData = [[OsmMapData alloc] initWithCachedData];
			t = CACurrentMediaTime() - t;
#if TARGET_OS_IPHONE
			if ( _mapData && t > 10.0 ) {
				NSString * text = NSLocalizedString(@"Your OSM data cache is getting large, which may lead to slow startup and shutdown times. You may want to clear the cache (under Display settings) to improve performance.",nil);
				UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Cache size warning",nil) message:text delegate:nil cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
				[alertView show];
			}
#endif
		} else {
			// discard existing database on upgrade
		}
		if ( _mapData == nil ) {
			_mapData = [OsmMapData new];
			[_mapData purgeHard];	// force database to get reset
		}

		_mapData.credentialsUserName = appDelegate.userName;
		_mapData.credentialsPassword = appDelegate.userPassword;

		__weak EditorMapLayer * weakSelf = self;
		[_mapData setUndoLocationCallback:^NSData *{
			OSMTransform trans = [weakSelf.mapView screenFromMapTransform];
			NSData * data = [NSData dataWithBytes:&trans length:sizeof trans];
			return data;
		}];

		_baseLayer = [CATransformLayer new];
		[self addSublayer:_baseLayer];

		if ( YES ) {
			// implement crosshairs
			_crossHairs = [CAShapeLayer new];
			UIBezierPath * path = [UIBezierPath bezierPath];
			CGFloat radius = 8;
			[path moveToPoint:CGPointMake(-radius, 0)];
			[path addLineToPoint:CGPointMake(radius, 0)];
			[path moveToPoint:CGPointMake(0, -radius)];
			[path addLineToPoint:CGPointMake(0, radius)];
			_crossHairs.anchorPoint	= CGPointMake(0.5, 0.5);
			_crossHairs.path		= path.CGPath;
			_crossHairs.strokeColor = [UIColor colorWithRed:1.0 green:1.0 blue:0.5 alpha:1.0].CGColor;
			_crossHairs.bounds		= CGRectMake(-radius, -radius, 2*radius, 2*radius);
			_crossHairs.lineWidth	= 1.0;
			_crossHairs.zPosition	= Z_CROSSHAIRS;

			path = [UIBezierPath new];
			CGFloat shadowWidth = 1.0;
			UIBezierPath * p1 = [UIBezierPath bezierPathWithRect:CGRectMake(-(radius+shadowWidth), -shadowWidth, 2*(radius+shadowWidth), 2*shadowWidth)];
			UIBezierPath * p2 = [UIBezierPath bezierPathWithRect:CGRectMake(-shadowWidth, -(radius+shadowWidth), 2*shadowWidth, 2*(radius+shadowWidth))];
			[path appendPath:p1];
			[path appendPath:p2];
			_crossHairs.shadowColor		= [UIColor blackColor].CGColor;
			_crossHairs.shadowOpacity	= 1.0;
			_crossHairs.shadowPath		= path.CGPath;
			_crossHairs.shadowRadius	= 0;
			_crossHairs.shadowOffset	= CGSizeMake(0,0);
		}

		self.actions = @{
						  @"onOrderIn"	: [NSNull null],
						  @"onOrderOut" : [NSNull null],
						  @"hidden"		: [NSNull null],
						  @"sublayers"	: [NSNull null],
						  @"contents"	: [NSNull null],
						  @"bounds"		: [NSNull null],
						  @"position"	: [NSNull null],
						  @"transform"	: [NSNull null],
						  @"lineWidth"	: [NSNull null],
		};
		_baseLayer.actions = self.actions;
		_crossHairs.actions = self.actions;
	}
	return self;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
		[self updateMapLocation];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)setBounds:(CGRect)bounds
{
	[super setBounds:bounds];
	_baseLayer.frame = bounds;
	[self updateMapLocation];
}


- (void)save
{
	[_mapData save];
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
#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
	[self updateMapLocation];
}


- (void)updateMapLocation
{
	if ( self.hidden )
		return;

	OSMRect box = [_mapView screenLongitudeLatitude];
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
#if USE_SHAPELAYERS
			[self setNeedsLayout];
#else
			[self setNeedsDisplay];
#endif
		}
	}];

#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
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
	if ( points[0] != points.lastObject ) {
		DLog(@"bad polygon");
		return NO;
	}
	if ( points.count < 4 ) {	// first and last repeat
		DLog(@"bad polygon");
		return NO;
	}
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


static BOOL RotateLoop( NSMutableArray * loop, OSMRect viewRect )
{
	if ( loop[0] != loop.lastObject ) {
		DLog(@"bad loop");
		return NO;
	}
	if ( loop.count < 4 ) {
		DLog(@"bad loop");
		return NO;
	}
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
	if ( isinf(p1.x) || isinf(p2.x) )
		return 0;

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

-(void)convertNodesToScreenPoints:(NSMutableArray *)nodeList
{
	if ( nodeList.count == 0 )
		return;
	BOOL isLoop = nodeList.count > 1 && nodeList[0] == nodeList.lastObject;
	for ( NSInteger index = 0, count = nodeList.count; index < count; ++index ) {
		if ( isLoop && index == count-1 ) {
			nodeList[index] = nodeList[0];
		} else {
			OsmNode * node = nodeList[index];
			CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
			nodeList[index] = [OSMPointBoxed pointWithPoint:OSMPointFromCGPoint(pt)];
		}
	}
}
+(void)convertNodesToMapPoints:(NSMutableArray *)nodeList
{
	if ( nodeList.count == 0 )
		return;
	BOOL isLoop = nodeList.count > 1 && nodeList[0] == nodeList.lastObject;
	for ( NSInteger index = 0, count = nodeList.count; index < count; ++index ) {
		if ( isLoop && index == count-1 ) {
			nodeList[index] = nodeList[0];
		} else {
			OsmNode * node = nodeList[index];
			OSMPoint pt = MapPointForLatitudeLongitude( node.lat, node.lon );
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
					if ( LineSegmentIntersectsRectangle( prevPoint, pt, viewRect ) && !isinf(pt.x) && !isinf(prevPoint.x) ) {
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


-(void)addPointList:(NSArray *)list toPath:(CGMutablePathRef)path
{
	BOOL first = YES;
	for ( OSMPointBoxed * point in list ) {
		OSMPoint p = point.point;
		if ( isinf(p.x) )
			break;
		if ( first ) {
			first = NO;
			CGPathMoveToPoint( path, NULL, p.x, p.y );
		} else {
			CGPathAddLineToPoint( path, NULL, p.x, p.y);
		}
	}
}
+(void)addBoxedPointList:(NSArray *)list toPath:(CGMutablePathRef)path refPoint:(OSMPoint)refPoint
{
	OSMPointBoxed * first = nil;
	for ( OSMPointBoxed * point in list ) {
		OSMPoint p = point.point;
		p.x -= refPoint.x;
		p.y -= refPoint.y;
		p.x *= PATH_SCALING;
		p.y *= PATH_SCALING;
		if ( isinf(p.x) )
			break;
		if ( first == nil ) {
			first = point;
			CGPathMoveToPoint(path, NULL, p.x, p.y );
		} else if ( point == first ) {
			CGPathCloseSubpath( path );
		} else {
			CGPathAddLineToPoint( path, NULL, p.x, p.y );
		}
	}
}


#if USE_SHAPELAYERS
-(CAShapeLayer *)getOceanLayer:(NSArray *)objectList
#else
-(BOOL)drawOceans:(NSArray *)objectList context:(CGContextRef)ctx
#endif
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
		return NO;

	// connect ways together forming congiguous runs
	outerSegments = [self joinConnectedWays:outerSegments];
	innerSegments = [self joinConnectedWays:innerSegments];

	// convert lists of nodes to screen points
	for ( NSMutableArray * a in outerSegments )
		[self convertNodesToScreenPoints:a];
	for ( NSMutableArray * a in innerSegments )
		[self convertNodesToScreenPoints:a];

	// Delete loops with a degenerate number of nodes. These are typically data errors:
	[outerSegments filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * array, NSDictionary *bindings) {
		return array[0] != array.lastObject || array.count >= 4;
	}]];
	[innerSegments filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray * array, NSDictionary *bindings) {
		return array[0] != array.lastObject || array.count >= 4;
	}]];


	CGRect cgViewRect = self.bounds;
	OSMRect viewRect = { cgViewRect.origin.x, cgViewRect.origin.y, cgViewRect.size.width, cgViewRect.size.height };
	CGPoint viewCenter = CGRectCenter(cgViewRect);

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
		return NO;
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
	CGMutablePathRef path = CGPathCreateMutable();
	while ( visibleSegments.count ) {

		NSArray * firstOutline = visibleSegments.lastObject;
		OSMPointBoxed * exit  = firstOutline.lastObject;
		[visibleSegments removeObject:firstOutline];

		[self addPointList:firstOutline toPath:path];

		for (;;) {
			// find next point following exit point
			NSArray * nextOutline = [entryDict objectForKey:exit];	// check if exit point is also entry point
			if ( nextOutline == nil ) {	// find next entry point following exit point
				NSInteger exitIndex = [points indexOfObject:exit];
				NSInteger entryIndex = (exitIndex+1) % points.count;
				nextOutline = [entryDict objectForKey:points[entryIndex]];
			}
			if ( nextOutline == nil ) {
				CGPathRelease(path);
				return NO;
			}
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
							CGPathAddLineToPoint( path, NULL, point1.x, point1.y );
						case SIDE_TOP:
							if ( wall2 == 1 && point1.x < point2.x )
								break;
							point1 = OSMPointMake(viewRect.origin.x+viewRect.size.width, viewRect.origin.y );
							CGPathAddLineToPoint( path, NULL, point1.x, point1.y );
						case SIDE_RIGHT:
							if ( wall2 == 2 && point1.y < point2.y )
								break;
							point1 = OSMPointMake(viewRect.origin.x+viewRect.size.width, viewRect.origin.y+viewRect.size.height);
							CGPathAddLineToPoint( path, NULL, point1.x, point1.y );
						case SIDE_BOTTOM:
							if ( wall2 == 3 && point1.x > point2.x )
								break;
							point1 = OSMPointMake(viewRect.origin.x, viewRect.origin.y+viewRect.size.height);
							CGPathAddLineToPoint( path, NULL, point1.x, point1.y );
						}
				}
			}

			haveCoastline = YES;
			if ( nextOutline == firstOutline ) {
				break;
			}
			if ( ![visibleSegments containsObject:nextOutline] ) {
				CGPathRelease(path);
				return NO;
			}
			for ( OSMPointBoxed * value in nextOutline ) {
				OSMPoint pt = value.point;
				CGPathAddLineToPoint( path, NULL, pt.x, pt.y );
			}

			exit = nextOutline.lastObject;
			[visibleSegments removeObject:nextOutline];
		}
	}

	// draw islands
	for ( NSArray * island in islands ) {
		[self addPointList:island toPath:path];

		if ( !haveCoastline && IsClockwisePolygon(island) ) {
			// this will still fail if we have an island with a lake in it
			haveCoastline = YES;
		}
	}

	// if no coastline then draw water everywhere
	if ( !haveCoastline ) {
		CGPathMoveToPoint(path, NULL, viewRect.origin.x, viewRect.origin.y);
		CGPathAddLineToPoint(path, NULL, viewRect.origin.x+viewRect.size.width, viewRect.origin.y);
		CGPathAddLineToPoint(path, NULL, viewRect.origin.x+viewRect.size.width, viewRect.origin.y+viewRect.size.height);
		CGPathAddLineToPoint(path, NULL, viewRect.origin.x, viewRect.origin.y+viewRect.size.height);
		CGPathCloseSubpath(path);
	}
#if USE_SHAPELAYERS
	CAShapeLayer * layer = [CAShapeLayer new];
	layer.path = path;
	layer.frame			= self.bounds;
	layer.fillColor		= [UIColor colorWithRed:0 green:0 blue:1 alpha:0.1].CGColor;
	layer.strokeColor	= [UIColor blueColor].CGColor;
	layer.lineJoin		= DEFAULT_LINEJOIN;
	layer.lineCap		= DEFAULT_LINECAP;
	layer.lineWidth		= 2.0;
	layer.zPosition		= Z_OCEAN;
	CGPathRelease(path);
	return layer;
#else
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);
	CGContextSetRGBFillColor(ctx, 0, 0, 1, 0.3);
	CGContextFillPath(ctx);
	CGPathRelease(path);
	return YES;
#endif
}

#pragma mark Drawing

-(double)geekbenchScore
{
	static double score = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		struct utsname systemInfo = { 0 };
		uname(&systemInfo);
		NSString * name = [[NSString alloc] initWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
		NSDictionary * dict = @{
								@"x86_64"    :	@4000,				// Simulator
								@"i386"      :	@4000,				// Simulator

								@"iPad5,4"	 :	@0,					// iPad Air 2
								@"iPad4,5"   :	@2493,				// iPad Mini (2nd Generation iPad Mini - Cellular)
								@"iPad4,4"   :	@2493,				// iPad Mini (2nd Generation iPad Mini - Wifi)
								@"iPad4,2"   :	@2664,				// iPad Air 5th Generation iPad (iPad Air) - Cellular
								@"iPad4,1"   :	@2664,				// iPad Air 5th Generation iPad (iPad Air) - Wifi
								@"iPad3,6"   :	@1402,				// iPad 4 (4th Generation)
								@"iPad3,5"   :	@1402,				// iPad 4 (4th Generation)
								@"iPad3,4"   :	@1402,				// iPad 4 (4th Generation)
								@"iPad3,3"   :	@492,				// iPad 3 (3rd Generation)
								@"iPad3,2"   :	@492,				// iPad 3 (3rd Generation)
								@"iPad3,1"   :	@492,				// iPad 3 (3rd Generation)
								@"iPad2,7"   :	@490,				// iPad Mini (Original)
								@"iPad2,6"   :	@490,				// iPad Mini (Original)
								@"iPad2,5"   :	@490,				// iPad Mini (Original)
								@"iPad2,4"   :	@492,				// iPad 2
								@"iPad2,3"   :	@492,				// iPad 2
								@"iPad2,2"   :	@492,				// iPad 2
								@"iPad2,1"   :	@492,				// iPad 2

								@"iPhone7,2" :	@2855,				// iPhone 6+
								@"iPhone7,1" :	@2879,				// iPhone 6
								@"iPhone6,2" :	@2523,				// iPhone 5s (model A1457, A1518, A1528 (China), A1530 | Global)
								@"iPhone6,1" :	@2523,				// iPhone 5s model A1433, A1533 | GSM)
								@"iPhone5,4" :	@1240,				// iPhone 5c (model A1507, A1516, A1526 (China), A1529 | Global)
								@"iPhone5,3" :	@1240,				// iPhone 5c (model A1456, A1532 | GSM)
								@"iPhone5,2" :	@1274,				// iPhone 5 (model A1429, everything else)
								@"iPhone5,1" :	@1274,				// iPhone 5 (model A1428, AT&T/Canada)
								@"iPhone4,1" :	@405,				// iPhone 4S
								@"iPhone3,1" :	@206,				// iPhone 4
								@"iPhone2,1" :	@150,				// iPhone 3GS

								@"iPod4,1"   :	@410,				// iPod Touch (Fifth Generation)
								@"iPod4,1"   :	@209,				// iPod Touch (Fourth Generation)
							};
		NSString * value = [dict objectForKey:name];
		if ( [value isKindOfClass:[NSNumber class]] ) {
			score = value.doubleValue;
		}
		if ( score == 0 ) {
			score = 2500;
		}
	});
	return score;
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
#if USE_SHAPELAYERS
		[self setNeedsLayout];
#else
		[self setNeedsDisplay];
#endif
	}
}


-(CGPathRef)pathForWay:(OsmWay *)way CF_RETURNS_RETAINED
{
	CGMutablePathRef path = CGPathCreateMutable();
	BOOL first = YES;
	for ( OsmNode * node in way.nodes ) {
		CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
		if ( isinf(pt.x) )
			break;
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
	return (NSInteger)floor( log2( OSMTransformScaleX(_mapView.screenFromMapTransform) ) );
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
		NSNumber * index = [colorDict objectForKey:text];
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

-(RGBAColor)defaultColorForObject:(OsmBaseObject *)object
{
	RGBAColor c;
	c.alpha = 1.0;
	if ( object.tags[@"shop"] ) {
		c.red = 0xAC/255.0;
		c.green = 0x39/255.0;
		c.blue = 0xAC/255.0;
	} else if ( object.tags[@"amenity"] || object.tags[@"building"] || object.tags[@"leisure"] ) {
		c.red = 0x73/255.0;
		c.green = 0x4A/255.0;
		c.blue = 0x08/255.0;
	} else if ( object.tags[@"tourism"] || object.tags[@"transport"] ) {
		c.red = 0x00/255.0;
		c.green = 0x92/255.0;
		c.blue = 0xDA/255.0;
	} else if ( object.tags[@"medical"] ) {
		c.red = 0xDA/255.0;
		c.green = 0x00/255.0;
		c.blue = 0x92/255.0;
	} else if ( object.tags[@"name"] ) {
		// blue for generic interesting nodes
		c.red = 0;
		c.green = 0;
		c.blue = 1;
	} else {
		// gray for untagged nodes
		c.alpha = 0.0;
		c.red = c.green = c.blue = 0.5;
	}
	return c;
}

#if USE_SHAPELAYERS
#define ZSCALE 0.001
const static CGFloat Z_BASE				= -1;
const static CGFloat Z_OCEAN			= Z_BASE + 1 * ZSCALE;
const static CGFloat Z_AREA				= Z_BASE + 2 * ZSCALE;
const static CGFloat Z_HALO				= Z_BASE + 2.5 * ZSCALE;
const static CGFloat Z_CASING			= Z_BASE + 3 * ZSCALE;
const static CGFloat Z_LINE				= Z_BASE + 4 * ZSCALE;
const static CGFloat Z_NODE				= Z_BASE + 5 * ZSCALE;
const static CGFloat Z_TEXT				= Z_BASE + 6 * ZSCALE;
const static CGFloat Z_BUILDING_WALL	= Z_BASE + 7 * ZSCALE;
const static CGFloat Z_BUILDING_ROOF	= Z_BASE + 8 * ZSCALE;
const static CGFloat Z_HIGHLIGHT_WAY	= Z_BASE + 9 * ZSCALE;
const static CGFloat Z_HIGHLIGHT_NODE	= Z_BASE + 10 * ZSCALE;
const static CGFloat Z_ARROWS			= Z_BASE + 11 * ZSCALE;
const static CGFloat Z_CROSSHAIRS		= 10000;

-(CGPathRef)pathForObject:(OsmBaseObject *)object refPoint:(OSMPoint *)refPoint CF_RETURNS_RETAINED
{
	NSArray * wayList = object.isWay ? @[ object ] : object.isRelation ? [self wayListForMultipolygonRelation:object.isRelation] : nil;
	if ( wayList == nil )
		return nil;

	CGMutablePathRef	path		= CGPathCreateMutable();
	OSMPoint			initial		= { 0, 0 };
	BOOL				haveInitial	= NO;

	for ( OsmWay * way in wayList ) {

		BOOL first = YES;
		for ( OsmNode * node in way.nodes ) {
			OSMPoint pt = MapPointForLatitudeLongitude( node.lat, node.lon );
			if ( isinf(pt.x) )
				break;
			if ( !haveInitial ) {
				initial = pt;
				haveInitial = YES;
			}
			pt.x -= initial.x;
			pt.y -= initial.y;
			pt.x *= PATH_SCALING;
			pt.y *= PATH_SCALING;
			if ( first ) {
				CGPathMoveToPoint(path, NULL, pt.x, pt.y);
				first = NO;
			} else {
				CGPathAddLineToPoint(path, NULL, pt.x, pt.y);
			}
		}
	}

	if ( refPoint && haveInitial ) {
		// place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
		CGRect bbox	= CGPathGetPathBoundingBox( path );
		if ( !isinf(bbox.origin.x) ) {
			CGAffineTransform tran = CGAffineTransformMakeTranslation( -bbox.origin.x, -bbox.origin.y );
			CGPathRef path2 = CGPathCreateCopyByTransformingPath( path, &tran );
			CGPathRelease( path );
			path = (CGMutablePathRef)path2;
			*refPoint = OSMPointMake( initial.x + (double)bbox.origin.x/PATH_SCALING, initial.y + (double)bbox.origin.y/PATH_SCALING );
		} else {
#if DEBUG
			DLog(@"bad path: %@", object);
			CGPathDump(path);
#endif
		}
	}

	return path;
}

-(CALayer *)buildingWallLayerForPoint:(OSMPoint)p1 point:(OSMPoint)p2 height:(double)height hue:(double)hue
{
	OSMPoint dir = Sub( p2, p1 );
	double length = Mag( dir );
	double angle = atan2( dir.y, dir.x );

	dir.x /= length;
	dir.y /= length;

	double intensity = angle/M_PI;
	if ( intensity < 0 )
		++intensity;
	UIColor	* color = [UIColor colorWithHue:(37+hue)/360.0 saturation:0.61 brightness:0.5+intensity/2 alpha:1.0];

	CALayer * wall = [CALayer new];
	wall.anchorPoint	= CGPointMake(0, 0);
	wall.zPosition		= Z_BUILDING_WALL;
#if SINGLE_SIDED_WALLS
	wall.doubleSided	= NO;
#else
	wall.doubleSided	= YES;
#endif
	wall.opaque			= YES;
	wall.frame			= CGRectMake(0, 0, length*PATH_SCALING, height);
	wall.backgroundColor= color.CGColor;
	wall.position		= CGPointMake( p1.x, p1.y );
	wall.borderWidth	= 1.0;
	wall.borderColor	= [UIColor blackColor].CGColor;

	CATransform3D t1 = CATransform3DMakeRotation( M_PI/2, dir.x, dir.y, 0);
	CATransform3D t2 = CATransform3DMakeRotation( angle, 0, 0, 1 );
	CATransform3D t = CATransform3DConcat( t2, t1 );
	wall.transform = t;

	LayerProperties * props = [LayerProperties new];
	[wall setValue:props forKey:@"properties"];
	props->transform	= t;
	props->position		= p1;
	props->lineWidth	= 1.0;
	props->is3D			= YES;

	return wall;
}

-(NSArray *)getShapeLayersForObject:(OsmBaseObject *)object
{
	if ( object.shapeLayers )
		return object.shapeLayers;

	TagInfo * tagInfo = object.tagInfo;
	NSMutableArray * layers = [NSMutableArray new];

	if ( object.isNode ) {

		if ( _mapCss ) {
#if 0
			ObjectSubpart * subpart = (id)object;
			OsmBaseObject * subObject = subpart.object;
			if ( !subObject.isNode && !subObject.isWay.isArea )
				return NO;
			NSDictionary * cssDict	= subpart.properties;
			NSString * iconName = [cssDict objectForKey:@"icon-image"];
			if ( iconName == nil ) {
				return NO;
			}
			object = (id)subObject;
#endif
		}

		OSMPoint pt;
		if ( object.isNode ) {
			pt = MapPointForLatitudeLongitude( object.isNode.lat, object.isNode.lon );
		} else if ( object.isWay ) {
			// this path is taken when MapCSS is drawing an icon in the center of an area, such as a parking lot
			OSMPoint latLon = [object.isWay centerPoint];
			pt = MapPointForLatitudeLongitude( latLon.y, latLon.x );
		} else {
			assert(NO);
		}

		if ( tagInfo.icon ) {
			UIImage * icon = tagInfo.scaledIcon;
			CGFloat uiScaling = [[UIScreen mainScreen] scale];
			if ( icon == nil ) {
				UIGraphicsBeginImageContext( CGSizeMake(uiScaling*MinIconSizeInPixels,uiScaling*MinIconSizeInPixels) );
				[tagInfo.icon drawInRect:CGRectMake(0,0,uiScaling*MinIconSizeInPixels,uiScaling*MinIconSizeInPixels)];
				icon = UIGraphicsGetImageFromCurrentImageContext();
				UIGraphicsEndImageContext();
				tagInfo.scaledIcon = icon;
			}
			CALayer * layer = [CALayer new];
			layer.bounds		= CGRectMake(0, 0, MinIconSizeInPixels, MinIconSizeInPixels);
			layer.anchorPoint	= CGPointMake(0.5, 0.5);
			layer.position		= CGPointMake(pt.x,pt.y);
			layer.contents		= (id)icon.CGImage;
			layer.shadowColor	= NSColor.whiteColor.CGColor;
			layer.shadowPath	= CGPathCreateWithRect( layer.bounds, NULL );
			layer.shadowRadius	= 0.0;
			layer.shadowOffset	= CGSizeMake(0,0);
			layer.shadowOpacity	= 0.25;
			layer.zPosition		= Z_NODE;

			LayerProperties * props = [LayerProperties new];
			[layer setValue:props forKey:@"properties"];
			props->position = pt;
			[layers addObject:layer];

		} else {

			// draw generic box
			RGBAColor color = [self defaultColorForObject:object];
			BOOL untagged = color.alpha == 0.0;
			NSString * houseNumber = untagged ? DrawNodeAsHouseNumber( object.tags ) : nil;
			if ( houseNumber ) {

				CALayer * layer = [CurvedTextLayer.shared layerWithString:houseNumber whiteOnBlock:self.whiteText];
				layer.anchorPoint	= CGPointMake(0.5, 0.5);
				layer.position		= CGPointMake(pt.x, pt.y);
				layer.zPosition		= Z_NODE;
				LayerProperties * props = [LayerProperties new];
				[layer setValue:props forKey:@"properties"];
				props->position = pt;

				[layers addObject:layer];

			} else {

				// generic box
				CAShapeLayer * layer = [CAShapeLayer new];
				CGRect rect = CGRectMake(-round(MinIconSizeInPixels/4), -round(MinIconSizeInPixels/4), round(MinIconSizeInPixels/2), round(MinIconSizeInPixels/2));
				CGPathRef path		= CGPathCreateWithRect( rect, NULL );
				layer.path			= path;

				layer.anchorPoint	= CGPointMake(0, 0);
				layer.position		= CGPointMake(pt.x,pt.y);
				layer.strokeColor	= [UIColor colorWithRed:color.red green:color.green blue:color.blue alpha:1.0].CGColor;
				layer.fillColor		= nil;
				layer.lineWidth		= 2.0;

				layer.shadowPath	= CGPathCreateWithRect( CGRectInset( rect, -3, -3), NULL);
				layer.shadowColor	= UIColor.whiteColor.CGColor;
				layer.shadowRadius	= 0.0;
				layer.shadowOffset	= CGSizeMake(0,0);
				layer.shadowOpacity	= 0.25;
				layer.zPosition		= Z_NODE;

				LayerProperties * props = [LayerProperties new];
				[layer setValue:props forKey:@"properties"];
				props->position = pt;

				[layers addObject:layer];
				CGPathRelease(path);
			}
		}
	}

	// casing
	if ( object.isWay || object.isRelation.isMultipolygon ) {
		if ( tagInfo.lineWidth && !object.isWay.isArea ) {
			OSMPoint refPoint;
			CGPathRef path = [self pathForObject:object refPoint:&refPoint];
			if ( path ) {

				{
					CAShapeLayer * layer = [CAShapeLayer new];
					layer.anchorPoint	= CGPointMake(0, 0);
					layer.position		= CGPointFromOSMPoint( refPoint );
					layer.path			= path;
					layer.strokeColor	= [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
					layer.fillColor		= nil;
					layer.lineWidth		= (1+tagInfo.lineWidth)*_highwayScale;
					layer.lineCap		= DEFAULT_LINECAP;
					layer.lineJoin		= DEFAULT_LINEJOIN;
					layer.zPosition		= Z_CASING;
					LayerProperties * props = [LayerProperties new];
					[layer setValue:props forKey:@"properties"];
					props->position = refPoint;
					props->lineWidth = layer.lineWidth;

					[layers addObject:layer];
				}

				// provide a halo for streets that don't have a name
				if ( _mapView.enableUnnamedRoadHalo ) {
					if ( object.tags[@"name"] == nil && ![object.tags[@"noname"] isEqualToString:@"yes"] ) {
						// it lacks a name
						static NSDictionary * highwayTypes = nil;
						enum { USES_NAME = 1, USES_REF = 2 };
						if ( highwayTypes == nil )
							highwayTypes = @{ @"motorway":@(USES_REF), @"trunk":@(USES_REF), @"primary":@(USES_REF), @"secondary":@(USES_REF), @"tertiary":@(USES_NAME), @"unclassified":@(USES_NAME), @"residential":@(USES_NAME), @"road":@(USES_NAME) };
						NSString * highway = object.tags[@"highway"];
						if ( highway ) {
							// it is a highway
							NSInteger uses = [highwayTypes[highway] integerValue];
							if ( uses ) {
								if ( (uses & USES_REF) ? object.tags[@"ref"] == nil : YES ) {
									CAShapeLayer * haloLayer = [CAShapeLayer new];
									haloLayer.anchorPoint	= CGPointMake(0, 0);
									haloLayer.position		= CGPointFromOSMPoint( refPoint );
									haloLayer.path			= path;
									haloLayer.strokeColor	= [UIColor colorWithRed:1.0 green:0 blue:0 alpha:1.0].CGColor;
									haloLayer.fillColor		= nil;
									haloLayer.lineWidth		= (2+tagInfo.lineWidth)*_highwayScale;
									haloLayer.lineCap		= DEFAULT_LINECAP;
									haloLayer.lineJoin		= DEFAULT_LINEJOIN;
									haloLayer.zPosition		= Z_HALO;
									LayerProperties * haloProps = [LayerProperties new];
									[haloLayer setValue:haloProps forKey:@"properties"];
									haloProps->position = refPoint;
									haloProps->lineWidth = haloLayer.lineWidth;

									[layers addObject:haloLayer];
								}
							}
						}
					}
				}

				CGPathRelease(path);
			}
		}
	}

	// way (also provides an outline for areas)
	if ( object.isWay || object.isRelation.isMultipolygon ) {
		OSMPoint refPoint = { 0, 0 };
		CGPathRef path = [self pathForObject:object refPoint:&refPoint];

		if ( path ) {
			CGFloat red = 0, green = 0, blue = 0, alpha = 1;
			[tagInfo.lineColor getRed:&red green:&green blue:&blue alpha:&alpha];
			CGFloat lineWidth = tagInfo.lineWidth*_highwayScale;
			if ( lineWidth == 0 )
				lineWidth = 1;

			CAShapeLayer * layer = [CAShapeLayer new];
			layer.anchorPoint	= CGPointMake(0, 0);
			CGRect bbox			= CGPathGetPathBoundingBox( path );
			layer.bounds		= CGRectMake( 0, 0, bbox.size.width, bbox.size.height );
			layer.position		= CGPointFromOSMPoint( refPoint );
			layer.path			= path;
			layer.strokeColor	= [UIColor colorWithRed:red green:green blue:blue alpha:alpha].CGColor;
			layer.fillColor		= nil;
			layer.lineWidth		= lineWidth;
			layer.lineCap		= DEFAULT_LINECAP;
			layer.lineJoin		= DEFAULT_LINEJOIN;
			layer.zPosition		= Z_LINE;

			LayerProperties * props = [LayerProperties new];
			[layer setValue:props forKey:@"properties"];
			props->position		= refPoint;
			props->lineWidth	= layer.lineWidth;

			CGPathRelease(path);
			[layers addObject:layer];
		}
	}

	// Area
	if ( object.isWay.isArea || object.isRelation.isMultipolygon ) {
		if ( tagInfo.areaColor && !object.isCoastline ) {

			NSMutableArray * outer = object.isWay ? [NSMutableArray arrayWithObject:object.isWay] : [NSMutableArray arrayWithCapacity:object.isRelation.members.count];
			NSMutableArray * inner = object.isWay ? nil : [NSMutableArray arrayWithCapacity:object.isRelation.members.count];
			for ( OsmMember * mem in object.isRelation.members ) {
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

			if ( outer.count > 0 ) {
				// convert from nodes to screen points
				for ( NSMutableArray * a in outer )
					[EditorMapLayer convertNodesToMapPoints:a];
				for ( NSMutableArray * a in inner )
					[EditorMapLayer convertNodesToMapPoints:a];

				// draw
				CGMutablePathRef path = CGPathCreateMutable();
				OSMPoint refPoint = ((OSMPointBoxed *)outer[0][0]).point;
				for ( NSArray * w in outer ) {
					[EditorMapLayer addBoxedPointList:w toPath:path refPoint:refPoint];
				}
				for ( NSArray * w in inner ) {
					[EditorMapLayer addBoxedPointList:w toPath:path refPoint:refPoint];
				}
				RGBAColor	fillColor;
				[tagInfo.areaColor getRed:&fillColor.red green:&fillColor.green blue:&fillColor.blue alpha:&fillColor.alpha];
				CAShapeLayer * layer = [CAShapeLayer new];
				layer.anchorPoint	= CGPointMake(0,0);
				layer.path			= path;
				layer.position		= CGPointFromOSMPoint(refPoint);
				layer.fillColor		= [UIColor colorWithRed:fillColor.red green:fillColor.green blue:fillColor.blue alpha:0.25].CGColor;
				layer.lineCap		= DEFAULT_LINECAP;
				layer.lineJoin		= DEFAULT_LINEJOIN;
				layer.zPosition		= Z_AREA;
				LayerProperties * props = [LayerProperties new];
				[layer setValue:props forKey:@"properties"];
				props->position = refPoint;

				[layers addObject:layer];

#if SHOW_3D
				// if its a building then add walls for 3D
				if ( object.tags[@"building"] != nil ) {

					// calculate height in meters
					NSString * value = object.tags[ @"height" ];
					double height = [value doubleValue];
					if ( height ) {	// height in meters?
						double v1 = 0;
						double v2 = 0;
						NSScanner * scanner = [[NSScanner alloc] initWithString:value];
						if ( [scanner scanDouble:&v1] ) {
							[scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
							if ( [scanner scanString:@"'" intoString:nil] ) {
								// feet
								if ( [scanner scanDouble:&v2] ) {
									if ( [scanner scanString:@"\"" intoString:NULL] ) {
										// inches
									} else {
										// malformed
									}
								}
								height = (v1 * 12 + v2) * 0.0254;
							} else if ( [scanner scanString:@"ft" intoString:NULL] ) {
								height *= 0.3048;
							} else if ( [scanner scanString:@"yd" intoString:NULL] ) {
								height *= 0.9144;
							}
						}
					} else {
						height = [object.tags[ @"building:levels" ] doubleValue];
#if DEBUG
						if ( height == 0 ) {
							NSString * layerNum = object.tags[ @"layer" ];
							if ( layerNum ) {
								height = layerNum.doubleValue + 1;
							}
						}
#endif
						if ( height == 0 ) {
							height = 1;
						}
						height *= 3;
					}

					// get walls
					double hue = object.ident.longLongValue % 20 - 10;
					for ( int isInner = 0; isInner < 2; ++isInner ) {
						for ( NSArray * w in isInner ? inner : outer ) {
#if SINGLE_SIDED_WALLS
							BOOL clockwise = [OsmWay isClockwiseArrayOfPoints:w] ^ isInner;
#else
							BOOL clockwise = YES;
#endif
							for ( NSInteger i = 0; i < w.count-1; ++i ) {
								OSMPointBoxed * pp1 = w[i+!clockwise];
								OSMPointBoxed * pp2 = w[i+clockwise];
								CALayer * wall = [self buildingWallLayerForPoint:pp1.point point:pp2.point height:height hue:hue];
								[layers addObject:wall];
							}
						}
					}

					if ( YES ) {
						// get roof
						UIColor	* color = [UIColor colorWithHue:0 saturation:0.05 brightness:0.75+hue/100 alpha:1.0];
						CAShapeLayer * roof = [CAShapeLayer new];
						roof.anchorPoint	= CGPointMake(0, 0);
						CGRect bbox			= CGPathGetPathBoundingBox( path );
						roof.bounds			= CGRectMake( 0, 0, bbox.size.width, bbox.size.height );
						roof.position		= CGPointFromOSMPoint( refPoint );
						roof.path			= path;
						roof.fillColor		= color.CGColor;
						roof.strokeColor	= UIColor.blackColor.CGColor;
						roof.lineWidth		= 1.0;
						roof.lineCap		= DEFAULT_LINECAP;
						roof.lineJoin		= DEFAULT_LINEJOIN;
						roof.zPosition		= Z_BUILDING_ROOF;
						roof.doubleSided	= YES;

						CATransform3D t = CATransform3DMakeTranslation( 0, 0, height );
						props = [LayerProperties new];
						[roof setValue:props forKey:@"properties"];
						props->position		= refPoint;
						props->transform	= t;
						props->is3D			= YES;
						props->lineWidth	= 1.0;
						roof.transform = t;
						[layers addObject:roof];
					}
				}
#endif	// SHOW_3D

				CGPathRelease(path);
			}
		}
	}

	// Names
	if ( object.isWay || object.isRelation.isMultipolygon ) {

		// get object name, or address if no name
		NSString * name = object.tags[@"name"];
		if ( name == nil )
			name = DrawNodeAsHouseNumber( object.tags );

		if ( name ) {

			BOOL isHighway = object.isWay && !object.isWay.isArea;
			if ( isHighway ) {

				// These are drawn dynamically
#if 0
				double length = 0.0;
				CGPathRef path = [self pathClippedToViewRect:object.isWay length:&length];
				double offset = (length - name.length * Pixels_Per_Character) / 2;
				if ( offset >= 0 ) {
					NSArray * a = [CurvedTextLayer layersWithString:name alongPath:path offset:offset color:self.textColor];
					[layers addObjectsFromArray:a];
				}
				CGPathRelease(path);
#endif

			} else {

				OSMPoint point = object.isWay ? object.isWay.centerPoint : object.isRelation.centerPoint;
				OSMPoint pt = MapPointForLatitudeLongitude( point.y, point.x );

				CALayer * layer = [CurvedTextLayer.shared layerWithString:name whiteOnBlock:self.whiteText];
				layer.anchorPoint	= CGPointMake(0.5, 0.5);
				layer.position		= CGPointMake(pt.x, pt.y);
				layer.zPosition		= Z_TEXT;

				LayerProperties * props = [LayerProperties new];
				[layer setValue:props forKey:@"properties"];
				props->position = pt;

				[layers addObject:layer];
			}
		}
	}
	
	static NSDictionary * actions = nil;
	if ( actions == nil )  {
		actions = @{
					  @"onOrderIn"			: [NSNull null],
					  @"onOrderOut"			: [NSNull null],
					  @"sublayers"			: [NSNull null],
					  @"contents"			: [NSNull null],
					  @"bounds"				: [NSNull null],
					  @"position"			: [NSNull null],
					  @"transform"			: [NSNull null],
					  @"affineTransform"	: [NSNull null],
					  @"lineWidth"			: [NSNull null],
					  @"borderWidth"		: [NSNull null],
#if FADE_INOUT
#else
					  @"hidden"				: [NSNull null],
					  @"opacity"			: [NSNull null],
#endif
					  };
	}
	for ( CALayer * layer in layers ) {
		layer.actions = actions;
	}

	object.shapeLayers = layers;
	return layers;
}


-(NSMutableArray *)getShapeLayersForHighlights
{
	double				geekScore	= [self geekbenchScore];
	NSInteger			nameLimit	= 5 + (geekScore - 500) / 200;	// 500 -> 5, 2500 -> 10
	NSMutableSet	*	nameSet		= [NSMutableSet new];
	NSMutableArray	*	layers		= [NSMutableArray new];

	// highlighting
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
		BOOL selected = object == _selectedNode || object == _selectedWay || [_extraSelections containsObject:object];

		if ( object.isWay ) {
			CGFloat		lineWidth	= MaxSubpartWidthForWay( object.isWay, @(zoom) );
			CGPathRef	path		= [self pathForWay:object.isWay];
			RGBAColor	wayColor	= { 1, 1, !selected, 1 };

			if ( lineWidth == 0 )
				lineWidth = 1;
			lineWidth += 2;	// since we're drawing highlight 2-wide we don't want it to intrude inward on way

			CAShapeLayer * layer = [CAShapeLayer new];
			layer.strokeColor	= [UIColor colorWithRed:wayColor.red green:wayColor.green blue:wayColor.blue alpha:wayColor.alpha].CGColor;
			layer.lineWidth		= lineWidth;
			layer.path			= path;
			layer.fillColor		= UIColor.clearColor.CGColor;
			layer.zPosition		= Z_HIGHLIGHT_WAY;

			LayerProperties * props = [LayerProperties new];
			[layer setValue:props forKey:@"properties"];
			props->lineWidth = layer.lineWidth;

			[layers addObject:layer];
			CGPathRelease(path);

			// draw nodes of way
			NSSet * nodes = object == _selectedWay ? object.nodeSet : nil;
			for ( OsmNode * node in nodes ) {
				layer				= [CAShapeLayer new];
				CGRect		rect	= CGRectMake(-WayHighlightRadius, -WayHighlightRadius, 2*WayHighlightRadius, 2*WayHighlightRadius);
				layer.position		= [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
				layer.strokeColor	= node == _selectedNode ? UIColor.redColor.CGColor : UIColor.greenColor.CGColor;
				layer.fillColor		= UIColor.clearColor.CGColor;
				layer.lineWidth		= 2.0;
				path = [node hasInterestingTags] ? CGPathCreateWithRect(rect, NULL) : CGPathCreateWithEllipseInRect(rect, NULL);
				layer.path			= path;
				layer.zPosition		= Z_HIGHLIGHT_NODE;
				[layers addObject:layer];
				CGPathRelease(path);
			}

		} else if ( object.isNode ) {

			OsmNode * node = (id)object;
			CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];

			CAShapeLayer * layer = [CAShapeLayer new];
			CGRect rect = CGRectMake(-MinIconSizeInPixels/2, -MinIconSizeInPixels/2, MinIconSizeInPixels, MinIconSizeInPixels);
			rect = CGRectInset( rect, -3, -3 );
			CGPathRef path		= CGPathCreateWithRect( rect, NULL );
			layer.path			= path;

			layer.anchorPoint	= CGPointMake(0, 0);
			layer.position		= CGPointMake(pt.x,pt.y);
			layer.strokeColor	= [UIColor colorWithRed:1.0 green:1.0 blue:selected?0.0:1.0 alpha:1.0].CGColor;
			layer.fillColor		= [UIColor clearColor].CGColor;
			layer.lineWidth		= 2.0;

			CGPathRef shadowPath = CGPathCreateWithRect( CGRectInset( rect, -3, -3), NULL);
			layer.shadowPath	= shadowPath;
			layer.shadowColor	= UIColor.blackColor.CGColor;
			layer.shadowRadius	= 0.0;
			layer.shadowOffset	= CGSizeMake(0,0);
			layer.shadowOpacity	= 0.25;

			layer.zPosition		= Z_HIGHLIGHT_NODE;
			[layers addObject:layer];
			CGPathRelease(path);
			CGPathRelease(shadowPath);
		}
	}

	// Arrow heads and street names
	for ( OsmBaseObject * object in _shownObjects ) {
		if ( object.isOneWay ) {

			// arrow heads
			[self invokeAlongScreenClippedWay:object.isWay offset:50 interval:100 block:^(OSMPoint loc, OSMPoint dir){
				// draw direction arrow at loc/dir
				BOOL reversed = object.isOneWay == ONEWAY_BACKWARD;
				double len = reversed ? -15 : 15;
				double width = 5;

				OSMPoint p1 = { loc.x - dir.x*len + dir.y*width, loc.y - dir.y*len - dir.x*width };
				OSMPoint p2 = { loc.x - dir.x*len - dir.y*width, loc.y - dir.y*len + dir.x*width };

				CGMutablePathRef arrowPath = CGPathCreateMutable();
				CGPathMoveToPoint(arrowPath, NULL, p1.x, p1.y);
				CGPathAddLineToPoint(arrowPath, NULL, loc.x, loc.y);
				CGPathAddLineToPoint(arrowPath, NULL, p2.x, p2.y);
				CGPathAddLineToPoint(arrowPath, NULL, loc.x-dir.x*len*0.5, loc.y-dir.y*len*0.5);
				CGPathCloseSubpath(arrowPath);

				CAShapeLayer * arrow = [CAShapeLayer new];
				arrow.path = arrowPath;
				arrow.lineWidth = 1;
				arrow.fillColor = UIColor.blackColor.CGColor;
				arrow.zPosition	= Z_ARROWS;
				[layers addObject:arrow];
				CGPathRelease(arrowPath);
			}];
		}

		// street names
		if ( nameLimit > 0 ) {
			BOOL isHighway = object.isWay && !object.isWay.isArea;
			if ( isHighway ) {
				NSString * name = object.tags[ @"name" ];
				if ( name ) {
					if ( ![nameSet containsObject:name] ) {
						double length = 0.0;
						CGPathRef path = [self pathClippedToViewRect:object.isWay length:&length];
						double offset = (length - name.length * Pixels_Per_Character) / 2;	// center along way
						if ( offset >= 0 ) {
							NSArray * a = [CurvedTextLayer.shared layersWithString:name alongPath:path offset:offset whiteOnBlock:self.whiteText];
							if ( a.count ) {
								[layers addObjectsFromArray:a];
								--nameLimit;
								[nameSet addObject:name];
							}
						}
						CGPathRelease(path);
					}
				}
			}
		}
	}

	return layers;
}


#endif



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
		[self convertNodesToScreenPoints:a];
	for ( NSMutableArray * a in inner )
		[self convertNodesToScreenPoints:a];

	// draw
	CGMutablePathRef path = CGPathCreateMutable();
	for ( NSArray * w in outer ) {
		[self addPointList:w toPath:path];
	}
	for ( NSArray * w in inner ) {
		[self addPointList:w toPath:path];
	}
	RGBAColor	fillColor;
	CGContextBeginPath(ctx);
	CGContextAddPath(ctx, path);
	[tagInfo.areaColor getRed:&fillColor.red green:&fillColor.green blue:&fillColor.blue alpha:&fillColor.alpha];
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

-(BOOL)drawWayCasing:(OsmBaseObject *)object context:(CGContextRef)ctx
{
	if ( ![object isKindOfClass:[OsmBaseObject class]] )
		// could be ObjectSubpart
		return NO;

	TagInfo * tagInfo = object.tagInfo;
	if ( tagInfo.lineWidth == 0 )
		return NO;

	if ( object.isWay.isArea )
		return NO;

	NSArray * wayList = object.isWay ? @[ object ] : [self wayListForMultipolygonRelation:object.isRelation];
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

	// draw nodes of way
	for ( OsmNode * node in nodes ) {
		CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
		if ( node == _selectedNode ) {
			CGContextSetRGBStrokeColor(ctx, 1,0,0, 1);	// red
		} else {
			CGContextSetRGBStrokeColor(ctx, 0,1,0, 1);	// green
		}
		CGContextBeginPath(ctx);
		CGContextSetLineWidth(ctx, 2);
		CGRect rect = CGRectMake( round(pt.x - WayHighlightRadius), round(pt.y - WayHighlightRadius), 2*WayHighlightRadius, 2*WayHighlightRadius);
		if ( [node hasInterestingTags] ) {
			CGContextAddRect(ctx, rect);
		} else {
			CGContextAddEllipseInRect(ctx, rect);
		}
		CGContextStrokePath(ctx);
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

-(void)drawArrowsForPath:(CGPathRef)path context:(CGContextRef)ctx reversed:(BOOL)reversed
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
			[self drawArrowsForPath:path context:ctx reversed:way.isOneWay == ONEWAY_BACKWARD];
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
	NSString * name = [subpart.object.tags objectForKey:textKey];
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
		[CurvedTextLayer.shared drawString:name alongPath:path offset:5.0 color:color shadowColor:shadowColor context:ctx];
		CGPathRelease(path);
	} else {
		// it is a node or area
		OSMPoint point = [way centerPoint];
		CGPoint cgPoint = [_mapView screenPointForLatitude:point.y longitude:point.x birdsEye:NO];

		UIColor * textColor2 = self.whiteText ? UIColor.whiteColor : UIColor.blackColor;
		[CurvedTextLayer.shared drawString:name centeredOnPoint:cgPoint width:0 font:nil color:textColor2 shadowColor:ShadowColorForColor2(textColor2) context:ctx];
	}
}



-(void)invokeAlongScreenClippedWay:(OsmWay *)way block:(BOOL(^)(OSMPoint p1, OSMPoint p2, BOOL isEntry, BOOL isExit))block
{
	OSMRect				viewRect = OSMRectFromCGRect( self.bounds );
	BOOL				prevInside;
	OSMPoint			prev = { 0 };
	BOOL				first = YES;

	for ( OsmNode * node in way.nodes ) {

		OSMPoint pt = OSMPointFromCGPoint( [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO] );
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

		BOOL proceed = block( p1, p2, !prevInside, !inside );
		if ( !proceed )
			break;;

	next:
		prev = pt;
		prevInside = inside;
	}
}


-(void)invokeAlongScreenClippedWay:(OsmWay *)way offset:(double)initialOffset interval:(double)interval block:(void(^)(OSMPoint pt, OSMPoint direction))block
{
	__block double offset = initialOffset;
	[self invokeAlongScreenClippedWay:way block:^BOOL(OSMPoint p1, OSMPoint p2, BOOL isEntry, BOOL isExit) {
		if ( isEntry )
			offset = initialOffset;
		double dx = p2.x - p1.x;
		double dy = p2.y - p1.y;
		double len = hypot( dx, dy );
		dx /= len;
		dy /= len;
		while ( offset < len ) {
			// found it
			OSMPoint pos = { p1.x + offset * dx, p1.y + offset * dy };
			OSMPoint dir = { dx, dy };
			block( pos, dir );
			offset += interval;
		}
		offset -= len;
		return YES;
	}];
}


// clip a way to the path inside the viewable rect so we can draw a name on it
-(CGPathRef)pathClippedToViewRect:(OsmWay *)way length:(double *)pLength CF_RETURNS_RETAINED
{
	__block CGMutablePathRef	path = NULL;
	__block	double				length = 0.0;
	__block	OSMPoint			firstPoint = { 0 };
	__block	OSMPoint			lastPoint = { 0 };

	[self invokeAlongScreenClippedWay:way block:^(OSMPoint p1, OSMPoint p2, BOOL isEntry, BOOL isExit ){
		if ( path == NULL ) {
			path = CGPathCreateMutable();
			CGPathMoveToPoint( path, NULL, p1.x, p1.y );
			firstPoint = p1;
		}
		CGPathAddLineToPoint( path, NULL, p2.x, p2.y );
		lastPoint = p2;
		length += hypot( p1.x - p2.x, p1.y - p2.y );
		if ( isExit )
			return NO;
		return YES;
	}];
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
	if ( pLength )
		*pLength = length;

	return path;
}


static NSString * DrawNodeAsHouseNumber( NSDictionary * tags )
{
	NSString * houseNumber = [tags objectForKey:@"addr:housenumber"];
	if ( houseNumber ) {
		NSString * unitNumber = [tags objectForKey:@"addr:unit"];
		if ( unitNumber )
			return [NSString stringWithFormat:@"%@/%@",houseNumber,unitNumber];
	}
	return houseNumber;
}


-(BOOL)drawWayName:(OsmBaseObject *)object context:(CGContextRef)ctx
{
	// add street names
	NSString * name = [object.tags objectForKey:@"name"];
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
		UIColor * textColor = self.whiteText ? UIColor.whiteColor : UIColor.blackColor;
		[CurvedTextLayer.shared drawString:name alongPath:path offset:offset color:textColor shadowColor:ShadowColorForColor2(textColor) context:ctx];
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
		CGPoint cgPoint = [_mapView screenPointForLatitude:point.y longitude:point.x birdsEye:NO];
		UIFont * font = [UIFont systemFontOfSize:11];
		UIColor * textColor = self.whiteText ? UIColor.whiteColor : UIColor.blackColor;
		UIColor * shadowColor = ShadowColorForColor2(textColor);
		[CurvedTextLayer.shared drawString:name centeredOnPoint:cgPoint width:pixelWidth font:font color:textColor shadowColor:shadowColor context:ctx];
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

	CGPoint pt;
	if ( node.isNode ) {
		pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
	} else if ( node.isWay ) {
		// this path is taken when MapCSS is drawing an icon in the center of an area, such as a parking lot
		OSMPoint latLon = [node.isWay centerPoint];
		pt = [_mapView screenPointForLatitude:latLon.y longitude:latLon.x birdsEye:NO];
	} else {
		assert(NO);
		return NO;
	}
#if DEBUG && 0
	NSAssert( CGRectContainsPoint(self.bounds,CGPointMake(pt.x, pt.y)), nil );
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

			UIColor * textColor = self.whiteText ? UIColor.whiteColor : UIColor.blackColor;
			UIColor * shadowColor = ShadowColorForColor2(textColor);
			[CurvedTextLayer.shared drawString:houseNumber	centeredOnPoint:pt width:0 font:nil color:textColor shadowColor:shadowColor context:ctx];

		} else {

			CGContextSetLineWidth(ctx, 2.0);
			CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, ShadowColorForColor(red, green, blue).CGColor );
			CGRect rect = CGRectMake(pt.x - round(_iconSize.width/4), pt.y - round(_iconSize.height/4), round(_iconSize.width/2), round(_iconSize.height/2));
			CGContextBeginPath(ctx);
			CGContextAddRect(ctx, rect);
			CGContextStrokePath(ctx);
		}
	}

	// if zoomed in very close then provide crosshairs
	if ( _iconSize.width > 64 ) {
		CGContextSetStrokeColorWithColor( ctx, NSColor.blackColor.CGColor );
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 3.0, NSColor.whiteColor.CGColor );
		CGContextSetLineWidth( ctx, 2.0 );
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
			CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];

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
	OSMRect box = [_mapView screenLongitudeLatitude];
	NSMutableArray * a = [NSMutableArray arrayWithCapacity:_mapData.wayCount];
	[_mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
		TRISTATE show = obj.isShown;
		if ( show == TRISTATE_UNKNOWN ) {
			if ( !obj.deleted ) {
				if ( obj.isNode ) {
					if ( ((OsmNode *)obj).wayCount == 0 || ShouldDisplayNodeInWay( obj.tags ) ) {
						show = TRISTATE_YES;
					}
				} else if ( obj.isWay ) {
					show = TRISTATE_YES;
				} else if ( obj.isRelation ) {
					show = TRISTATE_YES;
				}
			}
			obj.isShown = show == TRISTATE_YES ? TRISTATE_YES : TRISTATE_NO;
		}
		if ( show == TRISTATE_YES ) {
			[a addObject:obj];
		}
	}];
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
				subpart.zIndex		= [[props objectForKey:@"z-index"] doubleValue];
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
#if !USE_SHAPELAYERS
	[self drawOceans:a context:ctx];
	for ( ObjectSubpart * obj in a ) {
		[self drawMapCssCoastline:obj context:ctx];
	}
#endif
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
	NSInteger diff = obj1->renderPriorityCached - obj2->renderPriorityCached;
	return diff > 0;	// sort descending
}
static BOOL VisibleSizeLessStrict( OsmBaseObject * obj1, OsmBaseObject * obj2 )
{
	long long diff = obj1->renderPriorityCached - obj2->renderPriorityCached;
	if ( diff == 0 )
		diff = obj1.ident.longLongValue - obj2.ident.longLongValue;	// older objects are bigger
	return diff > 0;	// sort descending
}



- (NSMutableArray *)getObjectsToDisplay
{
#if TARGET_OS_IPHONE
	double geekScore = [self geekbenchScore];
	NSInteger objectLimit = 50 + (geekScore - 500) / 40;	// 500 -> 50, 2500 -> 100;
#else
	NSInteger objectLimit = 500;
#endif
#if USE_SHAPELAYERS
	objectLimit *= 3;
#endif

	double metersPerPixel = [_mapView metersPerPixel];
	if ( metersPerPixel < 0.05 ) {
		// we're zoomed in very far, so show everything
		objectLimit = 1000000;
	}

	// get objects in visible rect
	NSMutableArray * objects = [self getVisibleObjects];

	// get taginfo for objects
	for ( OsmBaseObject * object in objects ) {
		if ( object.tagInfo == nil ) {
			object.tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForObject:object];
		}
		if ( object->renderPriorityCached == 0 ) {
			if ( object.modifyCount ) {
				object->renderPriorityCached = 1000000;
			} else {
				object->renderPriorityCached = [object.tagInfo renderSize:object];
			}
		}
	}

	// sort from big to small objects
#if 0
	[objects partialSortK:2*objectLimit+1 compare:VisibleSizeLessStrict];
#else
	[objects partialSortOsmObjectVisibleSize:2*objectLimit+1];
#endif


	// adjust the list of objects so that we get all or none of the same type
	if ( objects.count > objectLimit ) {
		// We have more objects available than we want to display. If some of the objects are the same size as the last visible object then include those too.
		NSInteger lastIndex = objectLimit;
		OsmBaseObject * last = objects[ objectLimit-1 ];
		NSInteger lastRenderPriority = last->renderPriorityCached;
		for ( NSInteger i = objectLimit, e = MIN(objects.count,2*objectLimit); i < e; ++i ) {
			OsmBaseObject * o = objects[ i ];
			if ( o->renderPriorityCached == lastRenderPriority ) {
				lastIndex++;
			} else {
				break;
			}
		}
		if ( lastIndex >= 2*objectLimit ) {
			// we doubled the number of objects, so back off instead
			NSInteger removeCount = 0;
			for ( NSInteger i = objectLimit-1; i >= 0; --i ) {
				OsmBaseObject * o = objects[ i ];
				if ( o->renderPriorityCached == lastRenderPriority ) {
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
		NSIndexSet * range = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(objectLimit,objects.count-objectLimit)];
		[objects removeObjectsAtIndexes:range];
	}
	return objects;
}


#if USE_SHAPELAYERS
- (void)layoutSublayersSafe
{
	if ( _mapView.birdsEyeRotation ) {
		CATransform3D t = CATransform3DIdentity;
		t.m34 = -1.0/_mapView.birdsEyeDistance;
		t = CATransform3DRotate( t, _mapView.birdsEyeRotation, 1.0, 0, 0);
		_baseLayer.sublayerTransform = t;
	} else {
		_baseLayer.sublayerTransform	= CATransform3DIdentity;
	}

	NSArray * previousObjects = _shownObjects;

	_shownObjects = [self getObjectsToDisplay];
	[_shownObjects addObjectsFromArray:_fadingOutSet.allObjects];

	// remove layers no longer visible
	NSMutableSet * removals = [NSMutableSet setWithArray:previousObjects];
	for ( OsmBaseObject * object in _shownObjects ) {
		[removals removeObject:object];
	}
	// use fade when removing objects
	if ( removals.count ) {
#if FADE_INOUT
		[CATransaction begin];
		[CATransaction setAnimationDuration:1.0];
		[CATransaction setCompletionBlock:^{
			for ( OsmBaseObject * object in removals ) {
				[_fadingOutSet removeObject:object];
				[_shownObjects removeObject:object];
				for ( CALayer * layer in object.shapeLayers ) {
					if ( layer.opacity < 0.1 ) {
						[layer removeFromSuperlayer];
					}
				}
			}
		}];
		for ( OsmBaseObject * object in removals ) {
			[_fadingOutSet unionSet:removals];
			for ( CALayer * layer in object.shapeLayers ) {
				layer.opacity = 0.01;
			}
		}
		[CATransaction commit];
#else
		for ( OsmBaseObject * object in removals ) {
			for ( CALayer * layer in object.shapeLayers ) {
				[layer removeFromSuperlayer];
			}
		}
#endif
	}

#if FADE_INOUT
	[CATransaction begin];
	[CATransaction setAnimationDuration:1.0];
#endif

	const double	tRotation		= OSMTransformRotation( _mapView.screenFromMapTransform );
	const double	tScale			= OSMTransformScaleX( _mapView.screenFromMapTransform );
	const double	pScale			= tScale / PATH_SCALING;
	const double	pixelsPerMeter	= 0.8 * 1.0 / [_mapView metersPerPixel];

	for ( OsmBaseObject * object in _shownObjects ) {

		NSArray * layers = [self getShapeLayersForObject:object];

		for ( CALayer * layer in layers ) {

			// configure the layer for presentation
			BOOL isShapeLayer = [layer isKindOfClass:[CAShapeLayer class]];
			LayerProperties * props = [layer valueForKey:@"properties"];
			OSMPoint pt = props->position;
			OSMPoint pt2 = [_mapView screenPointFromMapPoint:pt birdsEye:NO];

			if ( props->is3D || (isShapeLayer && !object.isNode) ) {

				// way or area -- need to rotate and scale
				if ( props->is3D ) {
					if ( _mapView.birdsEyeRotation == 0.0 ) {
						[layer removeFromSuperlayer];
						continue;
					}
					CATransform3D t = CATransform3DMakeTranslation( pt2.x-pt.x, pt2.y-pt.y, 0 );
					t = CATransform3DScale( t, pScale, pScale, pixelsPerMeter );
					t = CATransform3DRotate( t, tRotation, 0, 0, 1 );
					t = CATransform3DConcat( props->transform, t );
					layer.transform = t;
					if ( !isShapeLayer ) {
						layer.borderWidth = props->lineWidth / pScale;	// wall
					}
				} else {
					CGAffineTransform t = CGAffineTransformMakeTranslation( pt2.x-pt.x, pt2.y-pt.y);
					t = CGAffineTransformScale( t, pScale, pScale );
					t = CGAffineTransformRotate( t, tRotation );
					layer.affineTransform = t;
				}

				if ( isShapeLayer ) {
				} else {
					// its a wall, so bounds are already height/length of wall
				}

				if ( isShapeLayer ) {
					CAShapeLayer * shape = (id)layer;
					shape.lineWidth = props->lineWidth / pScale;
				}

			} else {

				// node or text -- no scale transform applied
				if ( [layer isKindOfClass:[CATextLayer class]] ) {

					// get size of building (or whatever) into which we need to fit the text
					if ( object.isNode ) {
						// its a node with text, such as an address node
					} else {
						// its a label on a building or polygon
						OSMRect rcMap = [MapView mapRectForLatLonRect:object.boundingBox];
						OSMRect	rcScreen = [_mapView boundingScreenRectForMapRect:rcMap];
						if ( layer.bounds.size.width >= 1.1*rcScreen.size.width ) {
							// text label is too big so hide it
							[layer removeFromSuperlayer];
							continue;
						}
					}

				} else {

					// its an icon or a generic box
				}

				pt2.x = round(pt2.x);
				pt2.y = round(pt2.y);
				layer.position = CGPointFromOSMPoint(pt2);
			}

			// add the layer if not already present
			if ( layer.superlayer == nil ) {
#if FADE_INOUT
				[layer removeAllAnimations];
				layer.opacity = 1.0;
#endif
				[_baseLayer addSublayer:layer];
			}
		}
	}

#if FADE_INOUT
	[CATransaction commit];
#endif

	// draw highlights: these layers are computed in screen coordinates and don't need to be transformed
	for ( CALayer * layer in _highlightLayers ) {
		// remove old highlights
		[layer removeFromSuperlayer];
	}

	// get highlights
	_highlightLayers = [self getShapeLayersForHighlights];
	
	// get ocean
	CAShapeLayer * ocean = [self getOceanLayer:_shownObjects];
	if ( ocean ) {
		[_highlightLayers addObject:ocean];
	}
	for ( CALayer * layer in _highlightLayers ) {
		// add new highlights
		[_baseLayer addSublayer:layer];
	}

	if ( _crossHairs ) {
		_crossHairs.position = CGRectCenter( self.bounds );
		if ( _crossHairs.superlayer == nil ) {
			[self addSublayer:_crossHairs];
		}
	}

	// NSLog(@"%ld layers", (long)self.sublayers.count);
}

- (void)layoutSublayers
{
	if ( self.hidden )
		return;

	_isPerformingLayout = YES;
	[self layoutSublayersSafe];
	_isPerformingLayout = NO;
}
#endif

-(void)setNeedsLayout
{
	if ( _isPerformingLayout )
		return;
	[super setNeedsLayout];
}


#if !USE_SHAPELAYERS
- (void)drawInContext:(CGContextRef)ctx
{
	if ( self.hidden )
		return;

	if ( _mapCss ) {
		[self drawMapCssInContext:ctx];
		return;
	}

	NSInteger nameLimit	= [self geekbenchScore] >= 2000 ? 10 : 5;

	CFTimeInterval totalTime = CACurrentMediaTime();

	int areaCount = 0;
	int casingCount = 0;
	int wayCount = 0;
	int nodeCount = 0;
	int nameCount = 0;

	_shownObjects = [self getObjectsToDisplay];

	_nameDrawSet = [NSMutableSet new];

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
#endif



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
	delta.x /= maxDegrees.width;
	delta.y /= maxDegrees.height;
	CGFloat dist = hypot(delta.x, delta.y);
	return dist;
}

// distance is in units of the hit test radius (WayHitTestRadius)
+ (void)osmHitTestEnumerate:(CGPoint)point mapView:(MapView *)mapView objects:(NSArray *)objects testNodes:(BOOL)testNodes
				 ignoreList:(NSArray *)ignoreList block:(void(^)(OsmBaseObject * obj,CGFloat dist,NSInteger segment))block
{
	CLLocationCoordinate2D location = [mapView longitudeLatitudeForScreenPoint:point birdsEye:YES];
	OSMRect viewCoord = [mapView screenLongitudeLatitude];
	OSMSize pixelsPerDegree = { mapView.bounds.size.width / viewCoord.size.width, mapView.bounds.size.height / viewCoord.size.height };

	OSMSize maxDegrees = { WayHitTestRadius / pixelsPerDegree.width, WayHitTestRadius / pixelsPerDegree.height };
	const double NODE_BIAS = 0.8;	// make nodes appear closer so they can be selected

	for ( OsmBaseObject * object in objects ) {
		if ( object.deleted )
			continue;
		if ( object.isNode ) {
			OsmNode * node = (id)object;
			if ( ![ignoreList containsObject:node] ) {
				if ( testNodes || node.wayCount == 0 ) {
					CGFloat dist = [self osmHitTest:location maxDegrees:maxDegrees forNode:node];
					dist *= NODE_BIAS;
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
					dist *= NODE_BIAS;
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
			bestDist = dist;
			hit = obj;
			hitSegment = segment;
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

	CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
	pt.x += delta.x;
	pt.y -= delta.y;
	CLLocationCoordinate2D loc = [_mapView longitudeLatitudeForScreenPoint:pt birdsEye:YES];
	[_mapData setLongitude:loc.longitude latitude:loc.latitude forNode:node inWay:_selectedWay];

#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
}


-(OsmNode *)createNodeAtPoint:(CGPoint)point
{
	[self saveSelection];

	CLLocationCoordinate2D loc = [_mapView longitudeLatitudeForScreenPoint:point birdsEye:YES];
	OsmNode * node = [_mapData createNodeAtLocation:loc];
#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
	return node;
}

-(OsmWay *)createWayWithNode:(OsmNode *)node
{
	[self saveSelection];

	OsmWay * way = [_mapData createWay];
	[_mapData addNode:node toWay:way atIndex:0];
#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
	return way;
}

-(void)addNode:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index
{
	[self saveSelection];

	[_mapData addNode:node toWay:way atIndex:index];
#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
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

#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
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
#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
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
#if USE_SHAPELAYERS
	[self setNeedsLayout];
#else
	[self setNeedsDisplay];
#endif
	[self doSelectionChangeCallbacks];
}
- (void)clearExtraSelections
{
	if ( _extraSelections ) {
		_extraSelections = nil;
#if USE_SHAPELAYERS
		[self setNeedsLayout];
#else
		[self setNeedsDisplay];
#endif
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
#if USE_SHAPELAYERS
		[self setNeedsLayout];
#else
		[self setNeedsDisplay];
#endif
	}
	NSString * name = [_highlightObject friendlyDescription];
	if ( name ) {
		if ( _speechBalloon == nil ) {
			_speechBalloon = [SpeechBalloonLayer new];
			[self addSublayer:_speechBalloon];
		}
		if ( _highlightObject.isNode ) {
			OsmNode * node = (id)_highlightObject;
			mousePoint = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
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

-(void)setWhiteText:(BOOL)whiteText
{
	if ( _whiteText != whiteText ) {
		_whiteText = whiteText;
#if USE_SHAPELAYERS
		// need to refresh all text objects
		[_mapData enumerateObjectsUsingBlock:^(OsmBaseObject *obj) {
			obj.shapeLayers = nil;
		}];
		_baseLayer.sublayers = nil;
#endif
#if USE_SHAPELAYERS
		[self setNeedsLayout];
#else
		[self setNeedsDisplay];
#endif
	}
}

#pragma mark Coding

- (void)encodeWithCoder:(NSCoder *)coder
{
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
	// This is just here for completeness. The current object will be substituted during decode.
	return [super init];
}

@end
