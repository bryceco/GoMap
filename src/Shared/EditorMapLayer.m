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
#import "AppDelegate.h"
#import "BingMapsGeometry.h"
#import "Buildings3DView.h"
#import "CommonTagList.h"
#import "CurvedTextLayer.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#if TARGET_OS_IPHONE
#import "FilterObjectsViewController.h"
#import "MapViewController.h"
#endif
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmMapData+Edit.h"
#import "OsmMember.h"
#import "PathUtil.h"
#import "QuadMap.h"
#import "SpeechBalloonLayer.h"
#import "TagInfo.h"
#import "VectorMath.h"
#import "Go_Map__-Swift.h"
#import "GeekbenchScoreProvider.h"

#define FADE_INOUT			0
#define SINGLE_SIDED_WALLS	1

const double PATH_SCALING = (256*256.0);		// scale up sizes in paths so Core Animation doesn't round them off


#define DEFAULT_LINECAP		kCALineCapSquare
#define DEFAULT_LINEJOIN	kCALineJoinMiter

static const CGFloat Pixels_Per_Character = 8.0;


@interface LayerProperties : NSObject
{
@public
	OSMPoint		position;
	double			lineWidth;
	NSArray		*	lineDashes;
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

@interface EditorMapLayer ()

@property (nonatomic) id<GeekbenchScoreProviding> geekbenchScoreProvider;

@end

@implementation EditorMapLayer

@synthesize mapView				= _mapView;
@synthesize whiteText			= _whiteText;
@synthesize selectedNode		= _selectedNode;
@synthesize selectedWay			= _selectedWay;
@synthesize selectedRelation	= _selectedRelation;
@synthesize mapData				= _mapData;


static const CGFloat NodeHighlightRadius = 6.0;

-(id)initWithMapView:(MapView *)mapView
{
	self = [super init];
	if ( self ) {
		_mapView = mapView;
        _geekbenchScoreProvider = [[GeekbenchScoreProvider alloc] init];

		AppDelegate * appDelegate = [AppDelegate getAppDelegate];

		self.whiteText = YES;

		_fadingOutSet = [NSMutableSet new];

		// observe changes to geometry
		[_mapView addObserver:self forKeyPath:@"screenFromMapTransform" options:0 context:NULL];

		[OsmMapData setEditorMapLayerForArchive:self];
		
		NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
		[defaults registerDefaults:@{
			@"editor.enableObjectFilters" : @NO,
			@"editor.showLevel" : @NO,
			@"editor.showLevelRange" : @"",
			@"editor.showPoints" : @YES,
			@"editor.showTrafficRoads" : @YES,
			@"editor.showServiceRoads" : @YES,
			@"editor.showPaths" : @YES,
			@"editor.showBuildings" : @YES,
			@"editor.showLanduse" : @YES,
			@"editor.showBoundaries" : @YES,
			@"editor.showWater" : @YES,
			@"editor.showRail" : @YES,
			@"editor.showPower" : @YES,
			@"editor.showPastFuture" : @YES,
			@"editor.showOthers" : @YES,
		   }];
		
		
		_enableObjectFilters	= [defaults boolForKey:@"editor.enableObjectFilters"];
		_showLevel				= [defaults boolForKey:@"editor.showLevel"];
		_showLevelRange 		= [defaults objectForKey:@"editor.showLevelRange"];
		_showPoints				= [defaults boolForKey:@"editor.showPoints"];
		_showTrafficRoads		= [defaults boolForKey:@"editor.showTrafficRoads"];
		_showServiceRoads		= [defaults boolForKey:@"editor.showServiceRoads"];
		_showPaths 				= [defaults boolForKey:@"editor.showPaths"];
		_showBuildings 			= [defaults boolForKey:@"editor.showBuildings"];
		_showLanduse 			= [defaults boolForKey:@"editor.showLanduse"];
		_showBoundaries 		= [defaults boolForKey:@"editor.showBoundaries"];
		_showWater 				= [defaults boolForKey:@"editor.showWater"];
		_showRail 				= [defaults boolForKey:@"editor.showRail"];
		_showPower 				= [defaults boolForKey:@"editor.showPower"];
		_showPastFuture 		= [defaults boolForKey:@"editor.showPastFuture"];
		_showOthers 			= [defaults boolForKey:@"editor.showOthers"];

		CFTimeInterval t = CACurrentMediaTime();
		_mapData = [[OsmMapData alloc] initWithCachedData];
		t = CACurrentMediaTime() - t;
#if TARGET_OS_IPHONE
		if ( _mapData && mapView.enableAutomaticCacheManagement ) {
			[_mapData discardStaleData];
		} else if ( _mapData && t > 5.0 ) {
			// need to pause before posting the alert because the view controller isn't ready here yet
			dispatch_async(dispatch_get_main_queue(), ^{
				NSString * text = NSLocalizedString(@"Your OSM data cache is getting large, which may lead to slow startup and shutdown times.\n\nYou may want to clear the cache (under Display settings) to improve performance.",nil);
				UIAlertController * alertView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Cache size warning",nil) message:text preferredStyle:UIAlertControllerStyleAlert];
				[alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
				[self.mapView.viewController presentViewController:alertView animated:YES completion:nil];
			});
		}
#endif
		if ( _mapData == nil ) {
			_mapData = [OsmMapData new];
			[_mapData purgeHard];	// force database to get reset
		}

		_mapData.credentialsUserName = appDelegate.userName;
		_mapData.credentialsPassword = appDelegate.userPassword;

		__weak EditorMapLayer * weakSelf = self;
		_mapData.undoContextForComment = ^NSDictionary *(NSString * comment) {
			EditorMapLayer * strongSelf = weakSelf;
			if ( strongSelf == nil )
				return nil;
			OSMTransform trans = [strongSelf.mapView screenFromMapTransform];
			NSData * location = [NSData dataWithBytes:&trans length:sizeof trans];
			NSMutableDictionary * dict = [NSMutableDictionary new];
			dict[ @"comment" ] = comment;
			dict[ @"location" ] = location;
			CGPoint pushpin = strongSelf.mapView.pushpinPosition;
			if ( !isnan(pushpin.x) )
				dict[ @"pushpin" ] = NSStringFromCGPoint(strongSelf.mapView.pushpinPosition);
			if ( strongSelf.selectedRelation )
				dict[ @"selectedRelation" ] = strongSelf.selectedRelation;
			if ( strongSelf.selectedWay )
				dict[ @"selectedWay" ] = strongSelf.selectedWay;
			if ( strongSelf.selectedNode )
				dict[ @"selectedNode" ] = strongSelf.selectedNode;
			return dict;
		};

		_baseLayer = [CATransformLayer new];
		[self addSublayer:_baseLayer];

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
#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fontSizeDidChange:) name:UIContentSizeCategoryDidChangeNotification object:nil];
#endif
	}
	return self;
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _mapView && [keyPath isEqualToString:@"screenFromMapTransform"] )  {
		[self updateMapLocation];
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)fontSizeDidChange:(NSNotification *)notification
{
	[self resetDisplayLayers];
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

-(void)setEnableObjectFilters:(BOOL)enableObjectFilters
{
	if ( enableObjectFilters != _enableObjectFilters ) {
		_enableObjectFilters = enableObjectFilters;
		[[NSUserDefaults standardUserDefaults] setBool:_enableObjectFilters forKey:@"editor.enableObjectFilters"];
	}
}

-(void)setShowLevelRange:(NSString *)showLevelRange
{
	if ( [showLevelRange isEqualToString:_showLevelRange] )
		return;
	_showLevelRange = [showLevelRange copy];
	[[NSUserDefaults standardUserDefaults] setObject:_showLevelRange forKey:@"editor.showLevelRange"];
	[_mapData clearCachedProperties];
}

#define SET_FILTER(name)\
-(void)setShow##name:(BOOL)on {\
if ( on != _show##name ) { _show##name = on;\
[[NSUserDefaults standardUserDefaults] setBool:_show##name forKey:@"editor.show"#name];[_mapData clearCachedProperties];\
}}
SET_FILTER(Level)
SET_FILTER(Points)
SET_FILTER(TrafficRoads)
SET_FILTER(ServiceRoads)
SET_FILTER(Paths)
SET_FILTER(Buildings)
SET_FILTER(Landuse)
SET_FILTER(Boundaries)
SET_FILTER(Water)
SET_FILTER(Rail)
SET_FILTER(Power)
SET_FILTER(PastFuture)
SET_FILTER(Others)
#undef SET_FILTER


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
	if ( hard ) {
		[_mapData purgeHard];
	} else {
		[_mapData purgeSoft];
	}

	[self setNeedsLayout];
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
			[self setNeedsLayout];
		}
	}];

	[self setNeedsLayout];
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

-(CAShapeLayer *)getOceanLayer:(NSArray<OsmBaseObject *> *)objectList
{
	// get all coastline ways
	NSMutableArray * outerSegments = [NSMutableArray new];
	NSMutableArray * innerSegments = [NSMutableArray new];
	for ( OsmBaseObject * object in objectList ) {
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
		return nil;

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
		return nil;
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
				return nil;
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
				return nil;
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
}

#pragma mark Common Drawing

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
	BOOL	hasColor;
} RGBColor;



-(RGBColor)defaultColorForObject:(OsmBaseObject *)object
{
	RGBColor c;
	c.hasColor = YES;
	if ( object.tags[@"shop"] ) {
		c.red = 0xAC/255.0;
		c.green = 0x39/255.0;
		c.blue = 0xAC/255.0;
    } else if ([object.tags[@"natural"] isEqualToString:@"tree"]) {
        /// #127A38
        c.red = 18/255.0;
        c.green = 122/255.0;
        c.blue = 56/255.0;
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
		// black/gray for non-catagorized objects
		c.hasColor = NO;
		c.red = c.green = c.blue = 0.0;
	}
	return c;
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



#pragma mark CAShapeLayer drawing

#define ZSCALE 0.001
const static CGFloat Z_BASE				= -1;
const static CGFloat Z_OCEAN			= Z_BASE + 1 * ZSCALE;
const static CGFloat Z_AREA				= Z_BASE + 2 * ZSCALE;
const static CGFloat Z_HALO				= Z_BASE + 2.5 * ZSCALE;
const static CGFloat Z_CASING			= Z_BASE + 3 * ZSCALE;
const static CGFloat Z_LINE				= Z_BASE + 4 * ZSCALE;
const static CGFloat Z_NODE				= Z_BASE + 5 * ZSCALE;
const static CGFloat Z_TURN             = Z_BASE + 5.5 * ZSCALE;	// higher than street signals, etc
const static CGFloat Z_TEXT				= Z_BASE + 6 * ZSCALE;
const static CGFloat Z_BUILDING_WALL	= Z_BASE + 7 * ZSCALE;
const static CGFloat Z_BUILDING_ROOF	= Z_BASE + 8 * ZSCALE;
const static CGFloat Z_HIGHLIGHT_WAY	= Z_BASE + 9 * ZSCALE;
const static CGFloat Z_HIGHLIGHT_NODE	= Z_BASE + 10 * ZSCALE;
const static CGFloat Z_ARROWS			= Z_BASE + 11 * ZSCALE;


-(CALayer *)buildingWallLayerForPoint:(OSMPoint)p1 point:(OSMPoint)p2 height:(double)height hue:(double)hue
{
	OSMPoint dir = Sub(p2,p1);
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
	wall.position		= CGPointFromOSMPoint(p1);
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

    OsmNode *node = object.isNode;
	if (node) {
        [layers addObjectsFromArray:[self shapeLayersForForNode:node]];
	}

	// casing
	if ( object.isWay || object.isRelation.isMultipolygon ) {
		if ( tagInfo.lineWidth && !object.isWay.isArea ) {
			OSMPoint refPoint;
			CGPathRef path = [object linePathForObjectWithRefPoint:&refPoint];
			if ( path ) {

				{
					CAShapeLayer * layer = [CAShapeLayer new];
					layer.anchorPoint	= CGPointMake(0, 0);
					layer.position		= CGPointFromOSMPoint( refPoint );
					layer.path			= path;
					layer.strokeColor	= UIColor.blackColor.CGColor; // [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:1.0].CGColor;
					layer.fillColor		= nil;
					layer.lineWidth		= (1+tagInfo.lineWidth)*_highwayScale;
					layer.lineCap		= DEFAULT_LINECAP;
					layer.lineJoin		= DEFAULT_LINEJOIN;
					layer.zPosition		= Z_CASING;
					LayerProperties * props = [LayerProperties new];
					[layer setValue:props forKey:@"properties"];
					props->position = refPoint;
					props->lineWidth = layer.lineWidth;
					NSString * bridge = object.tags[@"bridge"];
					if ( bridge && !IsOsmBooleanFalse(bridge) ) {
						props->lineWidth += 4;
					}
					NSString * tunnel = object.tags[@"tunnel"];
					if ( tunnel && !IsOsmBooleanFalse(tunnel) ) {
						// props->lineDashes = @[@(6), @(3)];					// doesn't work because dashes get rounded off due to path scaling
						props->lineWidth += 2;
						layer.strokeColor = UIColor.brownColor.CGColor;
					}

					[layers addObject:layer];
				}

				// provide a halo for streets that don't have a name
				if ( _mapView.enableUnnamedRoadHalo ) {
					if ( object.tags[@"name"] == nil && ![object.tags[@"noname"] isEqualToString:@"yes"] ) {
						// it lacks a name
						static NSDictionary * highwayTypes = nil;
						enum { USES_NAME = 1, USES_REF = 2 };
						if ( highwayTypes == nil )
							highwayTypes = @{ @"motorway":@(USES_REF),
											  @"trunk":@(USES_REF),
											  @"primary":@(USES_REF),
											  @"secondary":@(USES_REF),
											  @"tertiary":@(USES_NAME),
											  @"unclassified":@(USES_NAME),
											  @"residential":@(USES_NAME),
											  @"road":@(USES_NAME),
											  @"living_street":@(USES_NAME) };
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
		CGPathRef path = [object linePathForObjectWithRefPoint:&refPoint];

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

#if 0	// Enable to show motorway_link with dashed lines. Looks kind of ugly and reduces framerate by up to 30%f
			BOOL link = [object.tags[@"highway"] hasSuffix:@"_link"];
			if ( link ) {
				props->lineDashes = @[@(10 * _highwayScale), @(10 * _highwayScale)];
			}
#endif

			CGPathRelease(path);
			[layers addObject:layer];
		}
	}

	// Area
	if ( object.isWay.isArea || object.isRelation.isMultipolygon ) {
		if ( tagInfo.areaColor && !object.isCoastline ) {

			OSMPoint refPoint;
			CGPathRef path = [object shapePathForObjectWithRefPoint:&refPoint];
			if ( path ) {
				// draw
				RGBColor	fillColor;
				[tagInfo.areaColor getRed:&fillColor.red green:&fillColor.green blue:&fillColor.blue alpha:NULL];
				CGFloat alpha = object.tags[@"landuse"] ? 0.15 : 0.25;
				CAShapeLayer * layer = [CAShapeLayer new];
				layer.anchorPoint	= CGPointMake(0,0);
				layer.path			= path;
				layer.position		= CGPointFromOSMPoint(refPoint);
				layer.fillColor		= [UIColor colorWithRed:fillColor.red green:fillColor.green blue:fillColor.blue alpha:alpha].CGColor;
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
								height = (v1 * 12 + v2) * 0.0254;	// meters/inch
							} else if ( [scanner scanString:@"ft" intoString:NULL] ) {
								height *= 0.3048;	// meters/foot
							} else if ( [scanner scanString:@"yd" intoString:NULL] ) {
								height *= 0.9144;	// meters/yard
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

#if USE_SCENEKIT
					UIBezierPath * wallPath = [UIBezierPath bezierPathWithCGPath:path];
					[_mapView.buildings3D addShapeWithPath:wallPath height:height position:refPoint];
#else
					// get walls
					double hue = object.ident.longLongValue % 20 - 10;
					__block BOOL hasPrev = NO;
					__block OSMPoint prevPoint;
					CGPathApplyBlockEx(path, ^(CGPathElementType type, CGPoint *points) {
						if ( type == kCGPathElementMoveToPoint ) {
							prevPoint = Add( refPoint, Mult(OSMPointFromCGPoint(points[0]),1/PATH_SCALING));
							hasPrev = YES;
						} else if ( type == kCGPathElementAddLineToPoint && hasPrev ) {
							OSMPoint pt = Add( refPoint, Mult(OSMPointFromCGPoint(points[0]),1/PATH_SCALING));
							CALayer * wall = [self buildingWallLayerForPoint:pt point:prevPoint height:height hue:hue];
							[layers addObject:wall];
							prevPoint = pt;
						} else {
							hasPrev = NO;
						}
					});
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
#endif // USE_SCENEKIT
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

	// Turn Restrictions
	if ( _mapView.enableTurnRestriction ) {
		if ( object.isRelation.isRestriction ) {
			NSArray * viaMembers = [object.isRelation membersByRole:@"via" ];
			for ( OsmMember * viaMember in viaMembers ) {
				OsmBaseObject * viaMemberObject = viaMember.ref;
				if ( [viaMemberObject isKindOfClass:[OsmBaseObject class]] ) {
					if ( viaMemberObject.isNode || viaMemberObject.isWay ) {
						OSMPoint latLon = viaMemberObject.selectionPoint;
						OSMPoint pt = MapPointForLatitudeLongitude(latLon.y, latLon.x);

						CALayer * restrictionLayerIcon 		= [CALayer new];
						restrictionLayerIcon.bounds 		= CGRectMake(0, 0, MinIconSizeInPixels, MinIconSizeInPixels);
						restrictionLayerIcon.anchorPoint 	= CGPointMake(0.5,0.5);
						restrictionLayerIcon.position 		= CGPointMake(pt.x, pt.y);
						if ( viaMember.isWay && [object.tags[@"restriction"] isEqualToString:@"no_u_turn"] ) {
							restrictionLayerIcon.contents 	= (id)[UIImage imageNamed:@"no_u_turn"].CGImage;
						} else {
							restrictionLayerIcon.contents 	= (id)[UIImage imageNamed:@"restriction_sign"].CGImage;
						}
						restrictionLayerIcon.zPosition		= Z_TURN;
						LayerProperties * restrictionIconProps = [LayerProperties new];
						[restrictionLayerIcon setValue:restrictionIconProps forKey:@"properties"];
						restrictionIconProps->position = pt;

						[layers addObject:restrictionLayerIcon];
					}
				}
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

/**
 Determines the `CALayer` instances required to present the given `node` on the map.
 
 @param node The `OsmNode` instance to get the layers for.
 @return A list of `CALayer` instances that are used to represent the given `node` on the map.
 */
- (NSArray<CALayer *> *)shapeLayersForForNode:(OsmNode *)node
{
    NSMutableArray<CALayer *> *layers = [NSMutableArray array];
    
    CALayer *directionLayer = [self directionShapeLayerWithNode:node];
    if (directionLayer) {
        [layers addObject:directionLayer];
    }

    OSMPoint pt = MapPointForLatitudeLongitude( node.lat, node.lon );
    
    // fetch icon
    NSString * featureName = [CommonTagList featureNameForObjectDict:node.tags geometry:node.geometryName];
    CommonTagFeature * feature = [CommonTagFeature commonTagFeatureWithName:featureName];
	UIImage * icon = feature.icon;
    if ( icon ) {
        /// White box as the background
        CALayer *backgroundLayer = [CALayer new];
        backgroundLayer.bounds          = CGRectMake(0, 0, MinIconSizeInPixels, MinIconSizeInPixels);
        backgroundLayer.backgroundColor	= [UIColor colorWithWhite:1.0 alpha:0.75].CGColor;
        backgroundLayer.cornerRadius    = MinIconSizeInPixels / 2;
        backgroundLayer.masksToBounds   = YES;
        backgroundLayer.anchorPoint 	= CGPointZero;
        backgroundLayer.borderColor = UIColor.darkGrayColor.CGColor;
        backgroundLayer.borderWidth = 0.5;
        
        /// The actual icon image serves as a `mask` for the icon's color layer, allowing for "tinting" of the icons.
        CALayer *iconMaskLayer = [CALayer new];
        CGFloat padding = 4;
        iconMaskLayer.frame            	= CGRectMake(padding, padding, MinIconSizeInPixels - padding * 2, MinIconSizeInPixels - padding * 2);
        iconMaskLayer.contents        	= (id)icon.CGImage;
        
        CALayer *iconLayer = [CALayer new];
        iconLayer.bounds            = CGRectMake(0, 0, MinIconSizeInPixels, MinIconSizeInPixels);
        RGBColor iconColor 			= [self defaultColorForObject:node];
        iconLayer.backgroundColor   = [UIColor colorWithRed:iconColor.red
													green:iconColor.green
													   blue:iconColor.blue
													  alpha:1.0].CGColor;
        iconLayer.mask = iconMaskLayer;
        iconLayer.anchorPoint = CGPointZero;
        
        CALayer * layer = [CALayer new];
        [layer addSublayer:backgroundLayer];
        [layer addSublayer:iconLayer];
        layer.bounds        	= CGRectMake(0, 0, MinIconSizeInPixels, MinIconSizeInPixels);
        layer.anchorPoint    	= CGPointMake(0.5, 0.5);
        layer.position        	= CGPointMake(pt.x,pt.y);
        layer.zPosition        	= Z_NODE;
        
        LayerProperties * props = [LayerProperties new];
        [layer setValue:props forKey:@"properties"];
        props->position = pt;
        [layers addObject:layer];
        
    } else {
        
        // draw generic box
        RGBColor color = [self defaultColorForObject:node];
		NSString * houseNumber = color.hasColor ? nil : DrawNodeAsHouseNumber( node.tags );
		if ( houseNumber ) {
            
            CALayer * layer = [CurvedTextLayer.shared layerWithString:houseNumber whiteOnBlock:self.whiteText];
            layer.anchorPoint	= CGPointMake(0.5, 0.5);
            layer.position      = CGPointMake(pt.x, pt.y);
            layer.zPosition     = Z_NODE;
            LayerProperties * props = [LayerProperties new];
            [layer setValue:props forKey:@"properties"];
            props->position = pt;
            
            [layers addObject:layer];
            
        } else {
            
            // generic box
            CAShapeLayer * layer = [CAShapeLayer new];
            CGRect rect = CGRectMake(round(MinIconSizeInPixels/4), round(MinIconSizeInPixels/4),
                                     round(MinIconSizeInPixels/2), round(MinIconSizeInPixels/2));
            CGPathRef path        	= CGPathCreateWithRect( rect, NULL );
            layer.path            	= path;
            layer.frame         	= CGRectMake(-MinIconSizeInPixels/2, -MinIconSizeInPixels/2,
												  MinIconSizeInPixels, MinIconSizeInPixels);
            layer.position          = CGPointMake(pt.x,pt.y);
            layer.strokeColor       = [UIColor colorWithRed:color.red green:color.green blue:color.blue alpha:1.0].CGColor;
            layer.fillColor         = nil;
            layer.lineWidth         = 2.0;
            layer.backgroundColor	= [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
            layer.cornerRadius      = 5.0;
            layer.zPosition         = Z_NODE;
            
            LayerProperties * props = [LayerProperties new];
            [layer setValue:props forKey:@"properties"];
            props->position = pt;
            
            [layers addObject:layer];
            CGPathRelease(path);
        }
    }

    return layers;
}

/**
 Determines the `CALayer` instance required to draw the direction of the given `node`.

 @param node The node to get the layer for.
 @return A `CALayer` instance for rendering the given node's direction.
 */
- (CALayer *)directionShapeLayerWithNode:(OsmNode *)node
{
    NSInteger direction = node.direction;
    if (direction == NSNotFound) {
        // Without a direction, there's nothing we could display.
        return nil;
    }
    
    CGFloat heading = direction - 90;
    
    CAShapeLayer *layer = [CAShapeLayer layer];
    
    layer.fillColor = [UIColor colorWithWhite:0.2 alpha:0.9].CGColor;
    layer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    layer.lineWidth = 0.5;
    
    layer.zPosition = Z_NODE;
    
    OSMPoint pt = MapPointForLatitudeLongitude(node.lat, node.lon);
    
    double screenAngle = OSMTransformRotation(self.mapView.screenFromMapTransform);
    layer.affineTransform = CGAffineTransformMakeRotation(screenAngle);
    
    CGFloat radius = 30.0;
    CGFloat fieldOfViewRadius = 55;
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddArc(path,
                 NULL,
                 0.0,
                 0.0,
                 radius,
                 [self radiansFromDegrees:heading - fieldOfViewRadius / 2],
                 [self radiansFromDegrees:heading + fieldOfViewRadius / 2],
                 NO);
    CGPathAddLineToPoint(path, NULL, 0, 0);
    CGPathCloseSubpath(path);
    layer.path = path;
    CGPathRelease(path);
    
    LayerProperties *layerProperties = [LayerProperties new];
    layerProperties->position = pt;
    [layer setValue:@"direction" forKey:@"key"];
    [layer setValue:layerProperties forKey:@"properties"];
    
    return layer;
}

- (CGFloat)radiansFromDegrees:(CGFloat)degrees
{
    return degrees * M_PI / 180;
}

-(NSMutableArray<CALayer *> *)getShapeLayersForHighlights
{
	double				geekScore	= [self.geekbenchScoreProvider geekbenchScore];
	NSInteger			nameLimit	= 5 + (geekScore - 500) / 200;	// 500 -> 5, 2500 -> 10
	NSMutableSet	*	nameSet		= [NSMutableSet new];
	NSMutableArray	*	layers		= [NSMutableArray new];
	UIColor			*	relationColor = [UIColor colorWithRed:66/255.0 green:188/255.0 blue:244/255.0 alpha:1.0];
	
	// highlighting
	NSMutableSet * highlights = [NSMutableSet new];
	if ( _selectedNode ) {
		[highlights addObject:_selectedNode];
	}
	if ( _selectedWay ) {
		[highlights addObject:_selectedWay];
	}
	if ( _selectedRelation ) {
		NSSet * members = [_selectedRelation allMemberObjects];
		[highlights unionSet:members];
	}

	for ( OsmBaseObject * object in highlights ) {
		// selected is false if its highlighted because it's a member of a selected relation
		BOOL selected = object == _selectedNode || object == _selectedWay;

		if ( object.isWay ) {
			CGPathRef	path		= [self pathForWay:object.isWay];
			CGFloat		lineWidth	= selected ? 1.0 : 2.0;
			UIColor	*	wayColor	= selected ? UIColor.cyanColor : relationColor;

			if ( lineWidth == 0 )
				lineWidth = 1;
			lineWidth += 2;	// since we're drawing highlight 2-wide we don't want it to intrude inward on way

			CAShapeLayer * layer = [CAShapeLayer new];
			layer.strokeColor	= wayColor.CGColor;
			layer.lineWidth		= lineWidth;
			layer.path			= path;
			layer.fillColor		= UIColor.clearColor.CGColor;
			layer.zPosition		= Z_HIGHLIGHT_WAY;

			LayerProperties * props = [LayerProperties new];
			[layer setValue:props forKey:@"properties"];
			props->lineWidth = layer.lineWidth;

			[layers addObject:layer];
			CGPathRelease(path);

			// Turn Restrictions
			if ( _mapView.enableTurnRestriction ) {
				for ( OsmRelation * relation in object.parentRelations ) {
					if ( relation.isRestriction && [relation memberByRole:@"from"].ref == object  ) {
						// the From member of the turn restriction is the selected way
						if ( _selectedNode == nil || [relation memberByRole:@"via"].ref == _selectedNode ) {	// highlight if no node, is selected, or the selected node is the via node
						//	BOOL isConditionalRestriction = relation.rags
							for ( OsmMember * member in relation.members ) {
								if ( member.isWay && [member.ref isKindOfClass:[OsmWay class]] ) {
									OsmWay * way = member.ref;
									CGPathRef turnPath = [self pathForWay:way];
									CAShapeLayer * haloLayer	= [CAShapeLayer new];
									haloLayer.anchorPoint    	= CGPointMake(0, 0);
									haloLayer.path            	= turnPath;
									if ( member.ref == object && ![member.role isEqualToString:@"to"] )
										haloLayer.strokeColor 	= [UIColor.blackColor colorWithAlphaComponent:0.75].CGColor;
									else if ( [relation.tags[@"restriction"] hasPrefix:@"only_"])
										haloLayer.strokeColor   = [UIColor.blueColor colorWithAlphaComponent:0.75].CGColor;
									else if ( [relation.tags[@"restriction"] hasPrefix:@"no_"])
										haloLayer.strokeColor  	= [UIColor.redColor colorWithAlphaComponent:0.75].CGColor;
									else
										haloLayer.strokeColor  	= [UIColor.orangeColor colorWithAlphaComponent:0.75].CGColor;	// some other kind of restriction
									haloLayer.fillColor        	= nil;
									haloLayer.lineWidth        	= (way.tagInfo.lineWidth + 6) * _highwayScale;
									haloLayer.lineCap        	= kCALineCapRound;
									haloLayer.lineJoin        	= kCALineJoinRound;
									haloLayer.zPosition        	= Z_HALO;
									LayerProperties * haloProps	= [LayerProperties new];
									[haloLayer setValue:haloProps forKey:@"properties"];
									haloProps->lineWidth = haloLayer.lineWidth;

									if ( ([member.role isEqualToString:@"to"] && member.ref == object) || ([member.role isEqualToString:@"via"] && member.isWay) ) {
										haloLayer.lineDashPattern = @[@(10 * _highwayScale), @(10 * _highwayScale)];
									}

									[layers addObject:haloLayer];
									CGPathRelease(turnPath);
								}
							}
						}
					}
				}
			}

			// draw nodes of way
			NSSet * nodes = object == _selectedWay ? object.nodeSet : nil;
			for ( OsmNode * node in nodes ) {
				layer				= [CAShapeLayer new];
				CGRect		rect	= CGRectMake(-NodeHighlightRadius, -NodeHighlightRadius, 2*NodeHighlightRadius, 2*NodeHighlightRadius);
				layer.position		= [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];
				layer.strokeColor	= node == _selectedNode ? UIColor.yellowColor.CGColor : UIColor.greenColor.CGColor;
				layer.fillColor		= UIColor.clearColor.CGColor;
				layer.lineWidth		= 2.0;
				path = [node hasInterestingTags] ? CGPathCreateWithRect(rect, NULL) : CGPathCreateWithEllipseInRect(rect, NULL);
				layer.path			= path;
				layer.zPosition		= Z_HIGHLIGHT_NODE + (node == _selectedNode ? 0.1*ZSCALE : 0);
				[layers addObject:layer];
				CGPathRelease(path);
			}

		} else if ( object.isNode ) {

#if 1 // draw square around selected node
			OsmNode * node = (id)object;
			CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:NO];

			CAShapeLayer * layer = [CAShapeLayer new];
			CGRect rect = CGRectMake(-MinIconSizeInPixels/2, -MinIconSizeInPixels/2, MinIconSizeInPixels, MinIconSizeInPixels);
			rect = CGRectInset( rect, -3, -3 );
			CGPathRef path		= CGPathCreateWithRect( rect, NULL );
			layer.path			= path;

			layer.anchorPoint	= CGPointMake(0, 0);
			layer.position		= CGPointMake(pt.x,pt.y);
			layer.strokeColor	= selected ? UIColor.greenColor.CGColor : UIColor.whiteColor.CGColor;
			layer.fillColor		= UIColor.clearColor.CGColor;
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
#endif
		}
	}

	// Arrow heads and street names
	for ( OsmBaseObject * object in _shownObjects ) {
		if ( object.isOneWay || [highlights containsObject:object] ) {

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
						if ( length >= name.length * Pixels_Per_Character ) {
							NSArray * a = [CurvedTextLayer.shared layersWithString:name alongPath:path
                                                                      whiteOnBlock:self.whiteText
                                                                   shouldRasterize:[self shouldRasterizeStreetNames]];
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

/**
 Determines whether text layers that display street names should be rasterized.

 @return The value to use for the text layer's `shouldRasterize` property.
 */
- (BOOL)shouldRasterizeStreetNames {
    return [self.geekbenchScoreProvider geekbenchScore] < 2500;
}

-(void)resetDisplayLayers
{
	// need to refresh all text objects
	[_mapData enumerateObjectsUsingBlock:^(OsmBaseObject *obj) {
		obj.shapeLayers = nil;
	}];
	_baseLayer.sublayers = nil;
	[self setNeedsLayout];
}

#pragma mark Select objects and draw


-(NSMutableArray *)getVisibleObjects
{
	OSMRect box = [_mapView screenLongitudeLatitude];
	NSMutableArray * a = [NSMutableArray arrayWithCapacity:_mapData.wayCount];
	[_mapData enumerateObjectsInRegion:box block:^(OsmBaseObject *obj) {
		TRISTATE show = obj.isShown;
		if ( show == TRISTATE_UNKNOWN ) {
			if ( !obj.deleted ) {
				if ( obj.isNode ) {
					if ( ((OsmNode *)obj).wayCount == 0 || [obj hasInterestingTags] ) {
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

#if 0
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
#endif


- (void)filterObjects:(NSMutableArray *)objects
{
#if TARGET_OS_IPHONE
	BOOL (^predLevel)(OsmBaseObject *) = nil;

	if ( _showLevel ) {
		// set level predicate dynamically since it depends on the the text range
		NSArray * levelFilter = [FilterObjectsViewController levelsForString:self.showLevelRange];
		if ( levelFilter.count ) {
			predLevel = ^BOOL(OsmBaseObject * object) {
				NSString * objectLevel = object.tags[ @"level" ];
				if ( objectLevel == nil )
					return YES;
				NSArray * floorSet = nil;
				double floor = 0.0;
				if ( [objectLevel containsString:@";"] ) {
					floorSet = [objectLevel componentsSeparatedByString:@";"];
				} else {
					floor = [objectLevel doubleValue];
				}
				for ( NSArray * filterRange in levelFilter ) {
					if ( filterRange.count == 1 ) {
						// filter is a single floor
						double filterValue = [filterRange[0] doubleValue];
						if ( floorSet ) {
							// object spans multiple floors
							for ( NSString * s in floorSet ) {
								double f = [s doubleValue];
								if ( f == filterValue ) {
									return YES;
								}
							}
						} else {
							if ( floor == filterValue ) {
								return YES;
							}
						}
					} else if ( filterRange.count == 2 ) {
						// filter is a range
						double filterLow = [filterRange[0] doubleValue];
						double filterHigh = [filterRange[1] doubleValue];
						if ( floorSet ) {
							// object spans multiple floors
							for ( NSString * s in floorSet ) {
								double f = [s doubleValue];
								if ( f >= filterLow && f <= filterHigh ) {
									return YES;
								}
							}
						} else {
							// object is a single value
							if ( floor >= filterLow && floor <= filterHigh ) {
								return YES;
							}
						}
					} else {
						assert(NO);
					}
				}
				return NO;
			};
		}
	}
	
	static NSDictionary *traffic_roads, *service_roads, *paths, *past_futures, *parking_buildings, *natural_water, *landuse_water;
	if ( traffic_roads == nil ) {
		traffic_roads = @{
			 @"motorway": @YES,
			 @"motorway_link": @YES,
			 @"trunk": @YES,
			 @"trunk_link": @YES,
			 @"primary": @YES,
			 @"primary_link": @YES,
			 @"secondary": @YES,
			 @"secondary_link": @YES,
			 @"tertiary": @YES,
			 @"tertiary_link": @YES,
			 @"residential": @YES,
			 @"unclassified": @YES,
			 @"living_street": @YES
			 };
		service_roads = @{
			 @"service": @YES,
			 @"road": @YES,
			 @"track": @YES
			 };
		paths = @{
			  @"path": @YES,
			  @"footway": @YES,
			  @"cycleway": @YES,
			  @"bridleway": @YES,
			  @"steps": @YES,
			  @"pedestrian": @YES,
			  @"corridor": @YES
			  };
		past_futures = @{
				@"proposed": @YES,
				@"construction": @YES,
				@"abandoned": @YES,
				@"dismantled": @YES,
				@"disused": @YES,
				@"razed": @YES,
				@"demolished": @YES,
				@"obliterated": @YES
				};
		parking_buildings = @{
			   @"multi-storey" : @YES,
			   @"sheds" : @YES,
			   @"carports" : @YES,
			   @"garage_boxes" : @YES
			   };
		natural_water = @{
			  @"water" : @YES,
			  @"coastline" : @YES,
			  @"bay" : @YES
			  };
		landuse_water = @{
			  @"pond": @YES,
			  @"basin" : @YES,
			  @"reservoir" : @YES,
			  @"salt_pond" : @YES
			  };
	}
	static BOOL (^predPoints)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return object.isNode != nil;
	};
	static BOOL (^predTrafficRoads)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return object.isWay && traffic_roads[ object.tags[@"highway"] ];
	};
	static BOOL (^predServiceRoads)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return object.isWay && service_roads[ object.tags[@"highway"] ];
	};
	static BOOL (^predPaths)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return object.isWay && paths[ object.tags[@"highway"] ];
	};
	static BOOL (^predBuildings)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		NSString * v;
		return object.tags[ @"building:part" ] ||
		((v = object.tags[@"building"]) && ![v isEqualToString:@"no"]) ||
		[object.tags[@"amenity"] isEqualToString:@"shelter"] ||
		parking_buildings[ object.tags[@"parking"] ];
	};
	static BOOL (^predWater)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return object.tags[@"waterway"] ||
				natural_water[ object.tags[@"natural"] ] ||
				landuse_water[ object.tags[@"landuse"] ];

	};
	static BOOL (^predLanduse)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return (object.isWay.isArea || object.isRelation.isMultipolygon) && !predBuildings(object) && !predWater(object);
	};
	static BOOL (^predBoundaries)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		if ( object.tags[ @"boundary" ] ) {
			NSString * highway = object.tags[ @"highway" ];
			return !( traffic_roads[highway] || service_roads[highway] || paths[highway] );
		}
		return NO;
	};
	static BOOL (^predRail)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		if ( object.tags[ @"railway" ] || [object.tags[ @"landuse" ] isEqualToString:@"railway"] ) {
			NSString * highway = object.tags[ @"highway" ];
			return !( traffic_roads[highway] || service_roads[highway] || paths[highway] );
		}
		return NO;
	};
	static BOOL (^predPower)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		return object.tags[ @"power" ] != nil;
	};
	static BOOL (^predPastFuture)(OsmBaseObject *) = ^BOOL(OsmBaseObject * object) {
		// contains a past/future tag, but not in active use as a road/path/cycleway/etc..
		NSString * highway = object.tags[ @"highway" ];
		if ( traffic_roads[highway] || service_roads[highway] || paths[highway] )
			return NO;
		__block BOOL ok = NO;
		[object.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL * stop) {
			if ( past_futures[ key ] || past_futures[value] ) {
				*stop = YES;
				ok = YES;
			}
		}];
		return ok;
	};

	NSPredicate * predicate = [NSPredicate predicateWithBlock:^BOOL(OsmBaseObject * object, NSDictionary<NSString *,id> * _Nullable bindings) {
		if ( predLevel && !predLevel(object) ) {
			return NO;
		}
		BOOL matchAny = NO;
#define MATCH(name)\
		if ( _show##name || _showOthers ) { \
			BOOL match = pred##name(object); \
			if ( match && _show##name ) return YES; \
			matchAny |= match; \
		}
		MATCH(Points);
		MATCH(TrafficRoads);
		MATCH(ServiceRoads);
		MATCH(Paths);
		MATCH(PastFuture);
		MATCH(Buildings);
		MATCH(Landuse);
		MATCH(Boundaries);
		MATCH(Water);
		MATCH(Rail);
		MATCH(Power);
		MATCH(Water);
#undef MATCH
		if ( _showOthers && !matchAny ) {
			if ( object.isWay && object.parentRelations.count == 1 && ((OsmRelation *)object.parentRelations.lastObject).isMultipolygon ) {
				return NO;	// follow parent filter instead
			}
			return YES;
		}
		return NO;
	}];
	
	// filter everything
	[objects filterUsingPredicate:predicate];
	
	// if we are showing relations we need to ensure the members are visible too
	NSMutableSet * add = [NSMutableSet new];
	for ( OsmBaseObject * obj in objects ) {
		if ( obj.isRelation.isMultipolygon ) {
			NSSet * set = [obj.isRelation allMemberObjects];
			for ( OsmBaseObject * o in set ) {
				if ( o.isWay ) {
					[add addObject:o];
				}
			}
		}
	}
	for ( OsmBaseObject * o in add ) {
		[objects addObject:o];
	}
#endif
}

- (NSMutableArray<OsmBaseObject *> *)getObjectsToDisplay
{
#if TARGET_OS_IPHONE
	double geekScore = [self.geekbenchScoreProvider geekbenchScore];
	NSInteger objectLimit = 50 + (geekScore - 500) / 40;	// 500 -> 50, 2500 -> 100;
#else
	NSInteger objectLimit = 500;
#endif
	objectLimit *= 3;

	double metersPerPixel = [_mapView metersPerPixel];
	if ( metersPerPixel < 0.05 ) {
		// we're zoomed in very far, so show everything
		objectLimit = 1000000;
	}

	// get objects in visible rect
	NSMutableArray * objects = [self getVisibleObjects];

	if ( self.enableObjectFilters ) {
		[self filterObjects:objects];
	}
	
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
	[objects partialSortOsmObjectVisibleSize:2*objectLimit+1];

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
		objectLimit = lastIndex;

		// remove unwanted objects
		NSIndexSet * range = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(objectLimit,objects.count-objectLimit)];
		[objects removeObjectsAtIndexes:range];
	}

	// sometimes there are way too many address nodes that clog up the view, so limit those items specifically
	objectLimit = objects.count;
	NSInteger addressCount = 0;
	while ( addressCount < objectLimit ) {
		OsmBaseObject * obj = objects[objectLimit-addressCount-1];
		if ( ![obj.tagInfo isAddressPoint] )
			break;
		++addressCount;
	}
	if ( addressCount > 50 ) {
		NSIndexSet * range = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(objectLimit-addressCount,addressCount)];
		[objects removeObjectsAtIndexes:range];
	}

	return objects;
}


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

	NSArray<OsmBaseObject *> * previousObjects = _shownObjects;

	_shownObjects = [self getObjectsToDisplay];
	[_shownObjects addObjectsFromArray:_fadingOutSet.allObjects];

	// remove layers no longer visible
	NSMutableSet<OsmBaseObject *> * removals = [NSMutableSet setWithArray:previousObjects];
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
					shape.lineDashPattern = props->lineDashes ? @[ @([props->lineDashes[0] doubleValue]/pScale), @([props->lineDashes[1] doubleValue]/pScale) ] : nil;
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

                } else if ([[layer valueForKey:@"key"] isEqualToString:@"direction"]) {
                    // This layer draws the `direction` of an object, so it needs to rotate along with the map.
                    layer.affineTransform = CGAffineTransformMakeRotation(tRotation);
                } else {

					// its an icon or a generic box
				}

				CGFloat scale = [[UIScreen mainScreen] scale];
				pt2.x = round(pt2.x * scale)/scale;
				pt2.y = round(pt2.y * scale)/scale;
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


#if USE_SCENEKIT
	{
		CGPoint center = CGRectCenter(_mapView.bounds);
		OSMPoint mapCenter = [_mapView mapPointFromScreenPoint:OSMPointFromCGPoint(center) birdsEye:NO];
		[_mapView.buildings3D setCameraDirection:tRotation birdsEye:_mapView.birdsEyeRotation distance:_mapView.birdsEyeDistance fromPoint:mapCenter];
	}
#endif

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

	// NSLog(@"%ld layers", (long)self.sublayers.count);
}

- (void)layoutSublayers
{
	if ( self.hidden )
		return;

	if ( _highwayScale == 0.0 ) {
		// Make sure stuff is initialized for current view. This is only necessary because layout code is called before bounds are set
		[self updateIconSize];
	}

	_isPerformingLayout = YES;
	[self layoutSublayersSafe];
	_isPerformingLayout = NO;
}

-(void)setNeedsLayout
{
	if ( _isPerformingLayout )
		return;
	[super setNeedsLayout];
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

+ (CGFloat)osmHitTestWay:(OsmWay *)way location:(CLLocationCoordinate2D)location maxDegrees:(OSMSize)maxDegrees segment:(NSInteger *)segment
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
+ (CGFloat)osmHitTestNode:(OsmNode *)node location:(CLLocationCoordinate2D)location maxDegrees:(OSMSize)maxDegrees
{
	OSMPoint delta = {
		(location.longitude - node.lon) / maxDegrees.width,
		(location.latitude - node.lat) / maxDegrees.height
	};
	CGFloat dist = hypot(delta.x, delta.y);
	return dist;
}

// distance is in units of the hit test radius (WayHitTestRadius)
+ (void)osmHitTestEnumerate:(CGPoint)point
					 radius:(CGFloat)radius
					mapView:(MapView *)mapView
					objects:(NSArray<OsmBaseObject *> *)objects
				  testNodes:(BOOL)testNodes
				 ignoreList:(NSArray<OsmBaseObject *> *)ignoreList
					  block:(void(^)(OsmBaseObject * obj,CGFloat dist,NSInteger segment))block
{
	CLLocationCoordinate2D location = [mapView longitudeLatitudeForScreenPoint:point birdsEye:YES];
	OSMRect viewCoord = [mapView screenLongitudeLatitude];
	OSMSize pixelsPerDegree = { mapView.bounds.size.width / viewCoord.size.width, mapView.bounds.size.height / viewCoord.size.height };

	OSMSize maxDegrees = { radius / pixelsPerDegree.width, radius / pixelsPerDegree.height };
	const double NODE_BIAS = 0.5;	// make nodes appear closer so they can be selected

	NSMutableSet * parentRelations = [NSMutableSet new];
	for ( OsmBaseObject * object in objects ) {
		if ( object.deleted )
			continue;

		if ( object.isNode ) {
			OsmNode * node = (id)object;
			if ( ![ignoreList containsObject:node] ) {
				if ( testNodes || node.wayCount == 0 ) {
					CGFloat dist = [self osmHitTestNode:node location:location maxDegrees:maxDegrees];
					dist *= NODE_BIAS;
					if ( dist <= 1.0 ) {
						block( node, dist, 0 );
						[parentRelations addObjectsFromArray:node.parentRelations];
					}
				}
			}
		} else if ( object.isWay ) {
			OsmWay * way = (id)object;
			if ( ![ignoreList containsObject:way] ) {
				NSInteger seg = 0;
				CGFloat distToWay = [self osmHitTestWay:way location:location maxDegrees:maxDegrees segment:&seg];
				if ( distToWay <= 1.0 ) {
					block( way, distToWay, seg );
					[parentRelations addObjectsFromArray:way.parentRelations];
				}
			}
			if ( testNodes ) {
				for ( OsmNode * node in way.nodes ) {
					if ( [ignoreList containsObject:node] )
						continue;
					CGFloat dist = [self osmHitTestNode:node location:location maxDegrees:maxDegrees];
					dist *= NODE_BIAS;
					if ( dist < 1.0 ) {
						block( node, dist, 0 );
						[parentRelations addObjectsFromArray:node.parentRelations];
					}
				}
			}
		} else if ( object.isRelation.isMultipolygon ) {
			OsmRelation * relation = (id)object;
			if ( ![ignoreList containsObject:relation] ) {
				CGFloat bestDist = 10000.0;
				for ( OsmMember * member in relation.members ) {
					OsmWay * way = member.ref;
					if ( [way isKindOfClass:[OsmWay class]] ) {
						if ( ![ignoreList containsObject:way] ) {
							if ( [member.role isEqualToString:@"inner"] || [member.role isEqualToString:@"outer"] ) {
								NSInteger seg = 0;
								CGFloat dist = [self osmHitTestWay:way location:location maxDegrees:maxDegrees segment:&seg];
								if ( dist < bestDist )
									bestDist = dist;
							}
						}
					}
				}
				if ( bestDist <= 1.0 ) {
					block( relation, bestDist, 0 );
				}
			}
		}
	}
	for ( OsmRelation * relation in parentRelations ) {
		// for non-multipolygon relations, like turn restrictions
		block( relation, 1.0, 0 );
	}
}

// default hit test when clicking on the map, or drag-connecting
- (OsmBaseObject *)osmHitTest:(CGPoint)point radius:(CGFloat)radius isDragConnect:(BOOL)isDragConnect ignoreList:(NSArray<OsmBaseObject *> *)ignoreList segment:(NSInteger *)pSegment
{
	if ( self.hidden )
		return nil;

	__block CGFloat bestDist = 1000000;
	NSMutableDictionary * best = [NSMutableDictionary new];
	[EditorMapLayer osmHitTestEnumerate:point radius:radius mapView:_mapView objects:_shownObjects testNodes:isDragConnect ignoreList:ignoreList block:^(OsmBaseObject *obj, CGFloat dist, NSInteger segment) {
		if ( dist < bestDist ) {
			bestDist = dist;
			[best removeAllObjects];
			best[obj] = @(segment);
		} else if ( dist == bestDist ) {
			best[obj] = @(segment);
		}
	}];
	if ( bestDist > 1.0 )
		return nil;

	OsmBaseObject * pick = nil;
	if ( best.count > 1 ) {
		if ( isDragConnect ) {
			// prefer to connecct to a way in a relation over the relation itself, which is opposite what we do when selecting by tap
			for ( OsmBaseObject * obj in best ) {
				if ( !obj.isRelation ) {
					pick = obj;
					break;
				}
			}
		} else {
			// performing selection by tap
			if ( pick == nil && self.selectedRelation ) {
				// pick a way that is a member of the relation if possible
				for ( OsmMember * member in self.selectedRelation.members ) {
					if ( best[member.ref] ) {
						pick = member.ref;
						break;
					}
				}
			}
			if ( pick == nil && self.selectedPrimary == nil ) {
				// nothing currently selected, so prefer relations
				for ( OsmBaseObject * obj in best ) {
					if ( obj.isRelation ) {
						pick = obj;
						break;
					}
				}
			}
		}
	}
	if ( pick == nil ) {
		pick = [[best keyEnumerator] nextObject];
	}
	if ( pSegment )
		*pSegment = [best[pick] integerValue];
	return pick;
}

// return all nearby objects
- (NSArray<OsmBaseObject *> *)osmHitTestMultiple:(CGPoint)point radius:(CGFloat)radius
{
	NSMutableSet<OsmBaseObject *> * objectSet = [NSMutableSet new];
	[EditorMapLayer osmHitTestEnumerate:point radius:radius mapView:self.mapView objects:_shownObjects testNodes:YES ignoreList:nil block:^(OsmBaseObject *obj, CGFloat dist, NSInteger segment) {
		[objectSet addObject:obj];
	}];
	NSMutableArray<OsmBaseObject *> * objectList = [objectSet.allObjects mutableCopy];
	[objectList sortUsingComparator:^NSComparisonResult(OsmBaseObject * o1, OsmBaseObject * o2) {
		int diff = (o1.isRelation?2:o1.isWay?1:0) - (o2.isRelation?2:o2.isWay?1:0);
		if ( diff )
			return -diff;
		int64_t diff2 = o1.ident.longLongValue - o2.ident.longLongValue;
		return diff2 < 0 ? NSOrderedAscending : diff2 > 0 ? NSOrderedDescending : NSOrderedSame;
	}];
	return objectList;
}

// drill down to a node in the currently selected way
-(OsmNode *)osmHitTestNodeInSelectedWay:(CGPoint)point radius:(CGFloat)radius
{
	if ( _selectedWay == nil )
		return nil;
	__block __unsafe_unretained OsmBaseObject * hit = nil;
	__block CGFloat bestDist = 1000000;
	[EditorMapLayer osmHitTestEnumerate:point radius:radius mapView:self.mapView objects:_selectedWay.nodes testNodes:YES ignoreList:nil block:^(OsmBaseObject * obj,CGFloat dist,NSInteger segment){
		if ( dist < bestDist ) {
			bestDist = dist;
			hit = obj;
		}
	}];
	if ( bestDist <= 1.0 ) {
		assert(hit.isNode);
		return hit.isNode;
	}
	return nil;
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
- (void)mergeTags:(OsmBaseObject *)object
{
    // Merge tags
	NSDictionary * copyPasteTags = [[NSUserDefaults standardUserDefaults] objectForKey:@"copyPasteTags"];
	NSDictionary * newTags = MergeTags(object.tags, copyPasteTags, YES);
	[self.mapData setTags:newTags forObject:object];
	[self setNeedsLayout];
}
- (void)replaceTags:(OsmBaseObject *)object
{
    // Replace all tags
    NSDictionary * copyPasteTags = [[NSUserDefaults standardUserDefaults] objectForKey:@"copyPasteTags"];
    [self.mapData setTags:copyPasteTags forObject:object];
	[self setNeedsLayout];
}



#pragma mark Editing


- (void)adjustNode:(OsmNode *)node byDistance:(CGPoint)delta
{
	CGPoint pt = [_mapView screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
	pt.x += delta.x;
	pt.y -= delta.y;
	CLLocationCoordinate2D loc = [_mapView longitudeLatitudeForScreenPoint:pt birdsEye:YES];
	[_mapData setLongitude:loc.longitude latitude:loc.latitude forNode:node];

	[self setNeedsLayout];
}

-(OsmBaseObject *)duplicateObject:(OsmBaseObject *)object
{
	OsmBaseObject * newObject = [_mapData duplicateObject:object];
	[self setNeedsLayout];
	return newObject;
}

-(OsmNode *)createNodeAtPoint:(CGPoint)point
{
	CLLocationCoordinate2D loc = [_mapView longitudeLatitudeForScreenPoint:point birdsEye:YES];
	OsmNode * node = [_mapData createNodeAtLocation:loc];
	[self setNeedsLayout];
	return node;
}

-(OsmWay *)createWayWithNode:(OsmNode *)node
{
	OsmWay * way = [_mapData createWay];
	NSString * dummy;
	EditActionWithNode add = [_mapData canAddNodeToWay:way atIndex:0 error:&dummy];
	add( node );
	[self setNeedsLayout];
	return way;
}

#pragma mark Editing actions that modify data and can fail

-(EditActionWithNode)canAddNodeToWay:(OsmWay *)way atIndex:(NSInteger)index error:(NSString **)error
{
	EditActionWithNode action = [_mapData canAddNodeToWay:way atIndex:index error:error];
	if ( action == nil )
		return nil;
	return ^(OsmNode * node){
		action(node);
		[self setNeedsLayout];
	};
}

-(EditAction)canDeleteSelectedObject:(NSString **)error
{
	if ( _selectedNode ) {

		// delete node from selected way
		EditAction action;
		if ( _selectedWay ) {
			action = [_mapData canDeleteNode:_selectedNode fromWay:_selectedWay error:error];
		} else {
			action = [_mapData canDeleteNode:_selectedNode error:error];
		}
		if ( action ) {
			return ^{
				// deselect node after we've removed it from ways
				action();
				[self setSelectedNode:nil];
				[self setNeedsLayout];
			};
		}

	} else if ( _selectedWay ) {

		// delete way
		EditAction action = [_mapData canDeleteWay:_selectedWay error:error];
		if ( action ) {
			return ^{
				action();
				[self setSelectedNode:nil];
				[self setSelectedWay:nil];
				[self setNeedsLayout];
			};
		}

	} else if ( _selectedRelation ) {
		EditAction action = [_mapData canDeleteRelation:_selectedRelation error:error];
		if ( action ) {
			return ^{
				action();
				[self setSelectedNode:nil];
				[self setSelectedWay:nil];
				[self setSelectedRelation:nil];
				[self setNeedsLayout];
			};
		}
	}

	return nil;
}


#pragma mark Highlighting and Selection

-(void)setNeedsDisplayForObject:(OsmBaseObject *)object
{
	[self setNeedsLayout];
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
		[_mapView updateEditControl];
	}
}
-(void)setSelectedWay:(OsmWay *)selectedWay
{
	assert( selectedWay == nil || selectedWay.isWay );
	if ( selectedWay != _selectedWay ) {
		_selectedWay = selectedWay;
		[self setNeedsDisplayForObject:selectedWay];
		[_mapView updateEditControl];
	}
}
-(void)setSelectedRelation:(OsmRelation *)selectedRelation
{
	assert( selectedRelation == nil || selectedRelation.isRelation );
	if ( selectedRelation != _selectedRelation ) {
		_selectedRelation = selectedRelation;
		[self setNeedsDisplayForObject:selectedRelation];
		[_mapView updateEditControl];
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
		[self resetDisplayLayers];
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
