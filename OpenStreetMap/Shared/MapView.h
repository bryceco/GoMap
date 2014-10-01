//
//  MapView.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#if TARGET_OS_IPHONE
#import "iosapi.h"
#import <Foundation/Foundation.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#import <CoreLocation/CoreLocation.h>
#import "VectorMath.h"

@class CAShapeLayer;
@class AerialList;
@class AerialService;
@class EditorLayerGL;
@class EditorMapLayer;
@class GpxLayer;
@class HtmlErrorWindow;
@class LocationBallLayer;
@class MapViewController;
@class MercatorTileLayer;
@class Notes;
@class OsmBaseObject;
@class PushPinView;
@class RulerLayer;
@class SpeechBalloonView;
@class FpsLabel;


@protocol MapViewDelegate <NSObject>
-(void)mapviewSelectionChanged:(id)selection;
-(void)mapviewViewportChanged;
-(void)doubleClickSelection:(id)selection;
@end

typedef enum _MapViewState {
	MAPVIEW_NONE = -1,
	MAPVIEW_EDITOR,
	MAPVIEW_EDITORAERIAL,
	MAPVIEW_AERIAL,
	MAPVIEW_MAPNIK,
} MapViewState;

typedef enum _ViewOverlayMask {
	VIEW_OVERLAY_LOCATOR	= 1 << 0,
	VIEW_OVERLAY_GPSTRACE	= 1 << 1,
} ViewOverlayMask;

typedef enum {
	GPS_STATE_NONE,
	GPS_STATE_LOCATION,
	GPS_STATE_HEADING,
} GPS_STATE;

#if TARGET_OS_IPHONE
@interface MapView : UIView <CLLocationManagerDelegate,UIActionSheetDelegate>
#else
@interface MapView : NSView <CLLocationManagerDelegate>
#endif
{
#if TARGET_OS_IPHONE
	IBOutlet UIButton				*	_bingMapsLogo;
	IBOutlet UIButton				*	_helpButton;
#else
	CALayer							*	_bingMapsLogo;
#endif
	RulerLayer						*	_rulerLayer;

	CGPoint								_lastMouseDragPos;

	IBOutlet NSProgressIndicator	*	_progressIndicator;
	NSInteger							_progressActive;

	OsmBaseObject					*	_grabbedObject;
	BOOL								_grabbedObjectDragged;	// track whether a node was actually dragged during select

	LocationBallLayer				*	_locationBallLayer;
	CAShapeLayer					*	_addWayProgressLayer;
	BOOL								_userOverrodeLocationPosition;
	BOOL								_userOverrodeLocationZoom;

	id									_blinkObject;	// used for creating a moving dots animation during selection
	NSInteger							_blinkSegment;
	CAShapeLayer					*	_blinkLayer;

	BOOL								_isZoomScroll;

#if TARGET_OS_IPHONE
	PushPinView						*	_pushpinView;
	UIAlertView						*	_alertDelete;
	UIAlertView						*	_alertError;
	UIAlertView						*	_alertMove;
	UIAlertView						*	_alertUndo;
	UIAlertView						*	_alertGps;
	UIActionSheet					*	_multiSelectSheet;
	NSArray							*	_multiSelectObjects;
	UILabel							*	_flashLabel;

	UIActionSheet					*	_actionSheet;
	NSArray							*	_actionList;	// storer mapping of action menu items to actions
#else
	HtmlErrorWindow					*	_htmlErrorWindow;
#endif

	NSDate							*	_lastErrorDate;		// to prevent spamming of error dialogs
	NSDate							*	_ignoreNetworkErrorsUntilDate;

	NSTimer							*	_inertiaTimer;		// for adding inertia to map panning

	CLLocationManager				*	_locationManager;
	CLLocation						*	_currentLocation;

	CGFloat								_rotationCurrent;
}

#if TARGET_OS_IPHONE
@property (assign,nonatomic)	MapViewController	*	viewController;
@property (assign,nonatomic)	IBOutlet FpsLabel	*	fpsLabel;
@property (assign,nonatomic)	IBOutlet UILabel	*	zoomToEditLabel;
#endif

@property (assign,nonatomic)	MapViewState			viewState;			// layer currently displayed
@property (assign,nonatomic)	BOOL					viewStateOverride;	// override layer because we're zoomed out
@property (assign,nonatomic)	ViewOverlayMask			viewOverlayMask;

@property (assign,nonatomic)	IBOutlet UISegmentedControl *	editControl;
@property (strong,nonatomic)	NSArray						*	editControlActions;

@property (readonly,nonatomic)	Notes				*	notes;

@property (readonly,nonatomic)	MercatorTileLayer	*	aerialLayer;
@property (readonly,nonatomic)	MercatorTileLayer	*	mapnikLayer;
@property (readonly,nonatomic)	EditorMapLayer		*	editorLayer;
@property (readonly,nonatomic)	EditorLayerGL		*	editorLayerGL;
@property (readonly,nonatomic)	GpxLayer			*	gpxLayer;
// overlays
@property (readonly,nonatomic)	MercatorTileLayer	*	locatorLayer;
@property (readonly,nonatomic)	MercatorTileLayer	*	gpsTraceLayer;
@property (readonly,nonatomic)	NSArray				*	backgroundLayers;	// list of all layers that need to be resized, etc.

@property (weak,nonatomic)		NSObject<MapViewDelegate>	*	delegate;
@property (readonly,nonatomic)	OSMRect							viewportLongitudeLatitude;
@property (readonly,nonatomic)	CGFloat							mouseLongitude;
@property (readonly,nonatomic)	CGFloat							mouseLatitude;
@property (assign,nonatomic)	OSMTransform					screenFromMapTransform;
@property (readonly,nonatomic)	OSMTransform					mapFromScreenTransform;

@property (assign,nonatomic)	GPS_STATE						gpsState;
@property (readonly,nonatomic)	PushPinView					*	pushpinView;

@property (strong,nonatomic)	AerialList					*	customAerials;


-(void)updateBingButton;
-(void)updateEditControl;				// show/hide edit control based on selection

+(OSMPoint)mapPointForLatitude:(double)latitude longitude:(double)longitude;
+(OSMPoint)longitudeLatitudeFromMapPoint:(OSMPoint)point;
-(OSMRect)mapRectFromScreenRect;
-(OSMRect)screenLongitudeLatitude;
-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude;
-(CLLocationCoordinate2D)longitudeLatitudeForScreenPoint:(CGPoint)point;
-(OSMRect)screenRectFromMapRect:(OSMRect)mapRect;
-(OSMPoint)screenPointFromMapPoint:(OSMPoint)point;
-(OSMRect)boundingMapRectForScreen;
-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude width:(double)widthDegrees;
-(double)metersPerPixel;

-(void)progressIncrement:(BOOL)animate;
-(void)progressDecrement;
-(void)progressAnimate;

-(void)flashMessage:(NSString *)message;
-(void)flashMessage:(NSString *)message duration:(NSTimeInterval)duration;
-(void)presentError:(NSError *)error flash:(BOOL)flash;

-(BOOL)isLocationSpecified;

-(IBAction)locateMe:(id)sender;
-(IBAction)duplicateSelectedObject:(id)sender;
-(IBAction)dropPin:(id)sender;
-(void)removePin;
-(void)refreshPushpinText;
-(void)placePushpinForSelection;
-(void)placePushpinAtPoint:(CGPoint)point object:(OsmBaseObject *)object;

- (IBAction)undo:(id)sender;
- (IBAction)redo:(id)sender;

#if TARGET_OS_IPHONE
- (IBAction)handlePanGesture:(UIPanGestureRecognizer *)pan;
- (IBAction)handlePinchGesture:(UIPinchGestureRecognizer *)pinch;
- (IBAction)handleTapGesture:(UITapGestureRecognizer *)tap;

- (void)setTagsForCurrentObject:(NSDictionary *)tags;
#endif

@end
