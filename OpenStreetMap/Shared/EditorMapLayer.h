//
//  OsmMapLayer.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "VectorMath.h"
#import "iosapi.h"
#import "OsmMapData.h"

@class Buildings3DView;
@class OsmMapData;
@class OsmRenderInfo;
@class MapCSS;
@class MapView;
@class OsmBaseObject;
@class OsmNode;
@class OsmWay;
@class OsmRelation;
@class QuadMap;

#define SHOW_3D	1
#define USE_SCENEKIT 0

static const CGFloat DefaultHitTestRadius = 10.0;	// how close to an object do we need to tap to select it
static const CGFloat DragConnectHitTestRadius = DefaultHitTestRadius * 0.6;	// how close to an object do we need to drag a node to connect to it

extern const double MinIconSizeInPixels;

@interface EditorMapLayer : CALayer<UIActionSheetDelegate,NSCoding>
{
	CGSize					_iconSize;
	double					_highwayScale;

	MapCSS				*	_mapCss;
	NSMutableSet		*	_nameDrawSet;

	NSMutableArray		*	_shownObjects;
	NSMutableSet		*	_fadingOutSet;

	NSMutableArray		*	_highlightLayers;

	BOOL					_isPerformingLayout;

	CATransformLayer	*	_baseLayer;
}

@property (assign,nonatomic)	BOOL			enableObjectFilters;	// turn all filters on/on
@property (assign,nonatomic)	BOOL			showLevel;				// filter for building level
@property (copy,nonatomic) 		NSString	*	showLevelRange;			// range of levels for building level
@property (assign,nonatomic)	BOOL			showPoints;
@property (assign,nonatomic)	BOOL			showTrafficRoads;
@property (assign,nonatomic)	BOOL			showServiceRoads;
@property (assign,nonatomic)	BOOL			showPaths;
@property (assign,nonatomic)	BOOL			showBuildings;
@property (assign,nonatomic)	BOOL			showLanduse;
@property (assign,nonatomic)	BOOL			showBoundaries;
@property (assign,nonatomic)	BOOL			showWater;
@property (assign,nonatomic)	BOOL			showRail;
@property (assign,nonatomic)	BOOL			showPower;
@property (assign,nonatomic)	BOOL			showPastFuture;
@property (assign,nonatomic)	BOOL			showOthers;


@property (assign,nonatomic)	MapView				*	mapView;
@property (assign,nonatomic)	BOOL					whiteText;
@property (strong,nonatomic)	OsmNode				*	selectedNode;
@property (strong,nonatomic)	OsmWay				*	selectedWay;
@property (strong,nonatomic)	OsmRelation			*	selectedRelation;
@property (readonly,nonatomic)	OsmBaseObject		*	selectedPrimary;	// way or node, but not a node in a selected way
@property (readonly,nonatomic)	OsmMapData			*	mapData;
@property (assign,nonatomic)	BOOL					addNodeInProgress;

- (id)initWithMapView:(MapView *)mapView;
- (void)didReceiveMemoryWarning;

- (OsmNode *)osmHitTestNodeInSelection:(CGPoint)point radius:(CGFloat)radius ;
- (OsmBaseObject *)osmHitTest:(CGPoint)point radius:(CGFloat)radius ;
- (OsmBaseObject *)osmHitTest:(CGPoint)point radius:(CGFloat)radius segment:(NSInteger *)segment ignoreList:(NSArray *)ignoreList;
- (OsmBaseObject *)osmHitTestSelection:(CGPoint)point radius:(CGFloat)radius ;
- (OsmBaseObject *)osmHitTestSelection:(CGPoint)point radius:(CGFloat)radius segment:(NSInteger *)segment;
+ (OsmBaseObject *)osmHitTest:(CGPoint)point radius:(CGFloat)radius mapView:(MapView *)mapView objects:(NSArray *)objects testNodes:(BOOL)testNodes
				   ignoreList:(NSArray *)ignoreList segment:(NSInteger *)segment;
- (NSArray *)osmHitTestMultiple:(CGPoint)point radius:(CGFloat)radius ;
- (void)osmObjectsNearby:(CGPoint)point radius:(double)radius block:(void(^)(OsmBaseObject * obj,CGFloat dist,NSInteger segment))block;

-(CGPoint)pointOnObject:(OsmBaseObject *)object forPoint:(CGPoint)point;


-(NSArray *)shownObjects;

- (void)updateMapLocation;
- (void)purgeCachedDataHard:(BOOL)hard;

// editing

-(OsmNode *)createNodeAtPoint:(CGPoint)point;
-(OsmWay *)createWayWithNode:(OsmNode *)node;

-(void)adjustNode:(OsmNode *)node byDistance:(CGPoint)delta;
-(OsmBaseObject *)duplicateObject:(OsmBaseObject *)object;

// these are similar to OsmMapData methods but also update selections and refresh the layout
-(EditActionWithNode)canAddNodeToWay:(OsmWay *)way atIndex:(NSInteger)index error:(NSString **)error;
-(EditAction)canDeleteSelectedObject:(NSString **)error;


- (BOOL)copyTags:(OsmBaseObject *)object;
- (BOOL)pasteTags:(OsmBaseObject *)object;
- (BOOL)canPasteTags;


- (void)save;

@end
