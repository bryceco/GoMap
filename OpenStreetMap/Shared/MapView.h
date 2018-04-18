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
#import <StoreKit/StoreKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif


#import <CoreLocation/CoreLocation.h>
#import "VectorMath.h"

@class CAShapeLayer;
@class AerialList;
@class AerialService;
@class DisplayLink;
@class EditorMapLayer;
@class GpxLayer;
@class HtmlErrorWindow;
@class LocationBallLayer;
@class MapViewController;
@class MercatorTileLayer;
@class OsmNote;
@class OsmNotesDatabase;
@class OsmBaseObject;
@class PushPinView;
@class RulerLayer;
@class SpeechBalloonView;
@class FpsLabel;
@class TapAndDragGesture;
@class VoiceAnnouncement;


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
	VIEW_OVERLAY_NOTES		= 1 << 2,
} ViewOverlayMask;

typedef enum {
	GPS_STATE_NONE,
	GPS_STATE_LOCATION,
	GPS_STATE_HEADING,
} GPS_STATE;

#if TARGET_OS_IPHONE
@interface MapView : UIView <CLLocationManagerDelegate,UIActionSheetDelegate,UIGestureRecognizerDelegate,SKStoreProductViewControllerDelegate>
#else
@interface MapView : NSView <CLLocationManagerDelegate>
#endif
{
#if TARGET_OS_IPHONE
#else
	CALayer							*	_bingMapsLogo;
#endif
	RulerLayer						*	_rulerLayer;

	CGPoint								_lastMouseDragPos;

	NSInteger							_progressActive;

	OsmBaseObject					*	_grabbedObject;
	BOOL								_grabbedObjectDragged;	// track whether a node was actually dragged during select

	LocationBallLayer				*	_locationBallLayer;
	CAShapeLayer					*	_addWayProgressLayer;

	id									_blinkObject;	// used for creating a moving dots animation during selection
	NSInteger							_blinkSegment;
	CAShapeLayer					*	_blinkLayer;

	BOOL								_isZoomScroll;	// Command-scroll zooms instead of scrolling (desktop only)
	BOOL								_isRotateObjectMode;
	CAShapeLayer					*	_rotateObjectOverlay;
	OSMPoint							_rotateObjectCenter;

	BOOL								_confirmDrag;	// should we confirm that the user wanted to drag the selected object? Only if they haven't modified it since selecting it

#if TARGET_OS_IPHONE
	PushPinView						*	_pushpinView;
	UILabel							*	_flashLabel;
#else
	HtmlErrorWindow					*	_htmlErrorWindow;
#endif

	NSDate							*	_lastErrorDate;		// to prevent spamming of error dialogs
	NSDate							*	_ignoreNetworkErrorsUntilDate;

	CLLocationManager				*	_locationManager;

	dispatch_source_t					_mailTimer;
	VoiceAnnouncement				*	_voiceAnnouncement;

	TapAndDragGesture				*	_tapAndDragGesture;

	CGPoint								_pushpinDragTotalMove;	// to maintain undo stack
	BOOL								_gestureDidMove;		// to maintain undo stack

	UILongPressGestureRecognizer	*	_addNodeButtonLongPressGestureRecognizer;
	NSTimeInterval						_addNodeButtonPressed;
}

#if TARGET_OS_IPHONE
@property (assign,nonatomic)	MapViewController			*	viewController;
@property (assign,nonatomic)	IBOutlet FpsLabel			*	fpsLabel;
@property (assign,nonatomic)	IBOutlet UILabel			*	userInstructionLabel;
@property (assign,nonatomic)	IBOutlet UIButton			*	compassButton;

@property (assign,nonatomic)	IBOutlet UIButton			*	aerialServiceLogo;
@property (assign,nonatomic)	IBOutlet UIButton			*	helpButton;
@property (assign,nonatomic)	IBOutlet UIButton			*	centerOnGPSButton;

@property (assign,nonatomic)	IBOutlet UIToolbar			*	toolbar;
@property (assign,nonatomic)	IBOutlet UIButton			*	addNodeButton;
#endif
@property (assign,nonatomic)	IBOutlet UIActivityIndicatorView	*	progressIndicator;


@property (readonly,nonatomic)	CLLocation					*	currentLocation;
@property (assign,nonatomic)	BOOL							userOverrodeLocationPosition;	// prevent gps updates from re-centering the view
@property (assign,nonatomic)	BOOL							userOverrodeLocationZoom;		// prevent gps updates from changing the zoom level

@property (assign,nonatomic)	MapViewState					viewState;			// layer currently displayed
@property (assign,nonatomic)	BOOL							viewStateOverride;	// override layer because we're zoomed out
@property (assign,nonatomic)	ViewOverlayMask					viewOverlayMask;

@property (assign,nonatomic)	IBOutlet UISegmentedControl *	editControl;
@property (strong,nonatomic)	NSArray						*	editControlActions;

@property (readonly,nonatomic)	OsmNotesDatabase			*	notesDatabase;
@property (readonly,nonatomic)	NSMutableDictionary			*	notesViewDict;

@property (readonly,nonatomic)	MercatorTileLayer			*	aerialLayer;
@property (readonly,nonatomic)	MercatorTileLayer			*	mapnikLayer;
@property (readonly,nonatomic)	EditorMapLayer				*	editorLayer;
@property (readonly,nonatomic)	GpxLayer					*	gpxLayer;
// overlays
@property (readonly,nonatomic)	MercatorTileLayer			*	locatorLayer;
@property (readonly,nonatomic)	MercatorTileLayer			*	gpsTraceLayer;
@property (readonly,nonatomic)	NSArray						*	backgroundLayers;	// list of all layers that need to be resized, etc.

@property (weak,nonatomic)		NSObject<MapViewDelegate>	*	delegate;
@property (assign,nonatomic)	OSMTransform					screenFromMapTransform;
@property (readonly,nonatomic)	OSMTransform					mapFromScreenTransform;

@property (assign,nonatomic)	GPS_STATE						gpsState;
@property (assign,nonatomic)	BOOL							gpsInBackground;
@property (readonly,nonatomic)	PushPinView					*	pushpinView;
@property (assign,nonatomic)	BOOL							silentUndo;	// don't flash message about undo

@property (strong,nonatomic)	AerialList					*	customAerials;

@property (readonly,nonatomic)	CGFloat							birdsEyeRotation;
@property (readonly,nonatomic)	CGFloat							birdsEyeDistance;

@property (assign,nonatomic)	BOOL							enableBirdsEye;
@property (assign,nonatomic)	BOOL							enableRotation;
@property (assign,nonatomic)	BOOL							enableUnnamedRoadHalo;
@property (assign,nonatomic)	BOOL							enableGpxLogging;
@property (assign,nonatomic)	BOOL							enableTurnRestriction;

@property (readonly,nonatomic)	CAShapeLayer				*	crossHairs;


-(void)updateAerialAttributionButton;
-(void)updateEditControl;				// show/hide edit control based on selection

-(void)viewDidAppear;
-(void)save;

+(OSMRect)mapRectForLatLonRect:(OSMRect)latLon;

- (void)locationUpdatedTo:(CLLocation *)newLocation;

-(OSMRect)screenLongitudeLatitude;
-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude birdsEye:(BOOL)birdsEye;
-(CLLocationCoordinate2D)longitudeLatitudeForScreenPoint:(CGPoint)point birdsEye:(BOOL)birdsEye;

-(OSMPoint)screenPointFromMapPoint:(OSMPoint)point birdsEye:(BOOL)birdsEye;
-(OSMPoint)mapPointFromScreenPoint:(OSMPoint)point birdsEye:(BOOL)birdsEye;

-(OSMRect)boundingScreenRectForMapRect:(OSMRect)mapRect;
-(OSMRect)boundingMapRectForScreenRect:(OSMRect)screenRect;
-(OSMRect)boundingMapRectForScreen;

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude width:(double)widthDegrees;
-(double)metersPerPixel;

-(void)progressIncrement:(BOOL)animate;
-(void)progressDecrement;
-(void)progressAnimate;

-(void)flashMessage:(NSString *)message;
-(void)flashMessage:(NSString *)message duration:(NSTimeInterval)duration;
-(void)presentError:(NSError *)error flash:(BOOL)flash;

-(void)setAerialTileService:(AerialService *)service;

-(BOOL)isLocationSpecified;

-(IBAction)requestAerialServiceAttribution:(id)sender;
-(IBAction)locateMe:(id)sender;
-(IBAction)centerOnGPS:(id)sender;
-(IBAction)rotateToNorth:(id)sender;
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

-(void)refreshNoteButtonsFromDatabase;

-(void)askToRate:(NSInteger)uploadCount;

@end
