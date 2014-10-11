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

@class OsmMapData;
@class OsmRenderInfo;
@class MapCSS;
@class MapView;
@class OsmBaseObject;
@class OsmNode;
@class OsmWay;
@class OsmRelation;
@class QuadMap;
@class SpeechBalloonLayer;

@interface EditorMapLayer : CALayer<UIActionSheetDelegate,NSCoding>
{
	CGSize					_iconSize;
	double					_highwayScale;

	OsmBaseObject		*	_highlightObject;
	NSMutableArray		*	_extraSelections;

	SpeechBalloonLayer	*	_speechBalloon;

	MapCSS				*	_mapCss;
	NSMutableSet		*	_nameDrawSet;

	NSMutableArray		*	_shownObjects;
	NSMutableSet		*	_fadingOutSet;

	NSMutableArray		*	_selectionChangeCallbacks;

	NSArray				*	_highlightLayers;

}

@property (assign,nonatomic)	MapView				*	mapView;
@property (strong,nonatomic)	NSColor				*	textColor;
@property (strong,nonatomic)	OsmNode				*	selectedNode;
@property (strong,nonatomic)	OsmWay				*	selectedWay;
@property (strong,nonatomic)	OsmRelation			*	selectedRelation;
@property (readonly,nonatomic)	OsmBaseObject		*	selectedPrimary;	// way or node, but not a node in a selected way
@property (readonly,nonatomic)	OsmMapData			*	mapData;
@property (assign,nonatomic)	BOOL					addNodeInProgress;
@property (assign,nonatomic)	BOOL					addWayInProgress;
@property (assign,nonatomic)	BOOL					enableMapCss;

- (id)initWithMapView:(MapView *)mapView;
- (void)didReceiveMemoryWarning;

- (OsmNode *)osmHitTestNodeInSelection:(CGPoint)point;
- (OsmBaseObject *)osmHitTest:(CGPoint)point;
- (OsmBaseObject *)osmHitTest:(CGPoint)point segment:(NSInteger *)segment ignoreList:(NSArray *)ignoreList;
- (OsmBaseObject *)osmHitTestSelection:(CGPoint)point;
- (OsmBaseObject *)osmHitTestSelection:(CGPoint)point segment:(NSInteger *)segment;
+ (OsmBaseObject *)osmHitTest:(CGPoint)point mapView:(MapView *)mapView objects:(NSArray *)objects testNodes:(BOOL)testNodes
				   ignoreList:(NSArray *)ignoreList segment:(NSInteger *)segment;
- (NSArray *)osmHitTestMultiple:(CGPoint)point;


-(NSArray *)shownObjects;

- (void)osmHighlightObject:(OsmBaseObject *)object mousePoint:(CGPoint)mousePoint;
- (void)updateMapLocation;
- (void)purgeCachedDataHard:(BOOL)hard;

- (void)toggleExtraSelection:(OsmBaseObject *)object;
- (void)clearExtraSelections;
- (NSArray *)extraSelections;

- (void)setSelectionChangeCallback:(void (^)(void))callback;

-(OsmNode *)createNodeAtPoint:(CGPoint)point;
-(OsmWay *)createWayWithNode:(OsmNode *)node;
-(void)deleteNode:(OsmNode *)node fromWay:(OsmWay *)way;
-(void)deleteNode:(OsmNode *)node fromWay:(OsmWay *)way allowDegenerate:(BOOL)allowDegenerate;
-(void)addNode:(OsmNode *)node toWay:(OsmWay *)way atIndex:(NSInteger)index;
-(void)deleteSelectedObject;
-(void)cancelOperation;

- (BOOL)copyTags:(OsmBaseObject *)object;
- (BOOL)pasteTags:(OsmBaseObject *)object;
- (BOOL)canPasteTags;


- (void)adjustNode:(OsmNode *)node byDistance:(CGPoint)delta;
- (void)save;

@end
