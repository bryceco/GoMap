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

#if TARGET_OS_IPHONE
@interface MapView : UIView <CLLocationManagerDelegate>
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
	UILabel							*	_flashLabel;
#else
	HtmlErrorWindow					*	_htmlErrorWindow;
#endif

	NSDate							*	_lastErrorDate;		// to prevent spamming of error dialogs
	NSDate							*	_ignoreNetworkErrorsUntilDate;

	NSTimer							*	_inertiaTimer;		// for adding inertia to map panning
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

@property (readonly,nonatomic)	Notes				*	notes;

@property (readonly,nonatomic)	MercatorTileLayer	*	aerialLayer;
@property (readonly,nonatomic)	MercatorTileLayer	*	mapnikLayer;
@property (readonly,nonatomic)	EditorMapLayer		*	editorLayer;
@property (readonly,nonatomic)	EditorLayerGL		*	editorLayerGL;
@property (readonly,nonatomic)	GpxLayer			*	gpxLayer;
// overlays
@property (readonly,nonatomic)	MercatorTileLayer	*	locatorLayer;
@property (readonly,nonatomic)	MercatorTileLayer	*	gpsTraceLayer;
@property (readonly,nonatomic)	NSArray				*	backgroundLayers;

@property (weak,nonatomic)		NSObject<MapViewDelegate>	*	delegate;
@property (strong,nonatomic)	CLLocationManager			*	locationManager;
@property (readonly,nonatomic)	OSMRect							viewportLongitudeLatitude;
@property (readonly,nonatomic)	CGFloat							mouseLongitude;
@property (readonly,nonatomic)	CGFloat							mouseLatitude;
@property (assign,nonatomic)	OSMTransform					mapTransform;
@property (assign,nonatomic)	BOOL							trackingLocation;
@property (readonly,nonatomic)	PushPinView					*	pushpinView;

@property (strong,nonatomic)	AerialList					*	customAerials;


-(void)updateBingButton;
-(void)updateEditControl;				// show/hide edit control based on selection

-(OSMRect)mapRectFromVisibleRect;
-(OSMRect)viewRectFromMapRect:(OSMRect)mapRect;

-(void)progressIncrement:(BOOL)animate;
-(void)progressDecrement;
-(void)progressAnimate;

-(void)flashMessage:(NSString *)message;
-(void)flashMessage:(NSString *)message duration:(NSTimeInterval)duration;
-(void)presentError:(NSError *)error flash:(BOOL)flash;

-(BOOL)isLocationSpecified;

+(OSMPoint)longitudeLatitudeFromMapPoint:(OSMPoint)point;
+(OSMPoint)mapPointForLatitude:(double)latitude longitude:(double)longitude;
-(CGPoint)viewPointForLatitude:(double)latitude longitude:(double)longitude;
-(double)metersPerPixel;
-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude width:(double)widthDegrees;

-(CLLocationCoordinate2D)longitudeLatitudeForViewPoint:(CGPoint)point;

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
