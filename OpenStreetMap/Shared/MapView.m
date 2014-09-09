//
//  MapView.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "iosapi.h"
#import "BingMapsGeometry.h"
#import "AerialList.h"
#import "DLog.h"
#import "DownloadThreadPool.h"
#import "EditorMapLayer.h"
#import "EditorLayerGL.h"
#import "FpsLabel.h"
#import "GpxLayer.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "Notes.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "RulerLayer.h"
#import "SpeechBalloonView.h"

#if TARGET_OS_IPHONE
#import "LocationBallLayer.h"
#import "MapViewController.h"
#import "PushPinView.h"
#import "WebPageViewController.h"
#else
#import "HtmlErrorWindow.h"
#endif


static const CGFloat Z_AERIAL		= -100;
static const CGFloat Z_MAPNIK		= -99;
static const CGFloat Z_LOCATOR		= -50;
static const CGFloat Z_GPSTRACE		= -40;
//static const CGFloat Z_GPX		= -30;
static const CGFloat Z_EDITOR		= -20;
//static const CGFloat Z_EDITOR_GL	= -19;
static const CGFloat Z_RULER		= -5;	// ruler is being buttons
//static const CGFloat Z_BING_LOGO	= 2;
static const CGFloat Z_BLINK		= 4;
static const CGFloat Z_BALLOON		= 5;
static const CGFloat Z_FLASH		= 6;


CGSize SizeForImage( NSImage * image )
{
#if TARGET_OS_IPHONE
	return image.size;
#else
	NSArray * reps = image.representations;
	if ( reps.count ) {
		CGSize size = { 0 };
		for ( NSImageRep * rep in reps ) {
			if ( rep.pixelsWide > size.width )
				size = CGSizeMake(rep.pixelsWide, rep.pixelsHigh);
		}
		return size;
	} else {
		return image.size;
	}
#endif
}


@implementation MapView

@synthesize aerialLayer			= _aerialLayer;
@synthesize mapnikLayer			= _mapnikLayer;
@synthesize editorLayer			= _editorLayer;
@synthesize trackingLocation	= _trackingLocation;
@synthesize pushpinView			= _pushpinView;
@synthesize viewState			= _viewState;


#pragma mark initialization


#if TARGET_OS_IPHONE
- (id)initWithCoder:(NSCoder *)coder
#else
- (id)initWithFrame:(NSRect)frame
#endif
{
#if TARGET_OS_IPHONE
	self = [super initWithCoder:coder];
#else
	self = [super initWithFrame:frame];
#endif

	if (self) {
#if !TARGET_OS_IPHONE
		self.wantsLayer = YES;
#endif
		self.layer.masksToBounds = YES;
		self.backgroundColor = UIColor.darkGrayColor;

		// get aerial database
		self.customAerials = [AerialList new];

		NSMutableArray * bg = [NSMutableArray new];

		_locatorLayer  = [[MercatorTileLayer alloc] initWithMapView:self];
		_locatorLayer.zPosition = Z_LOCATOR;
		_locatorLayer.aerialService = [AerialService mapboxLocator];
		_locatorLayer.hidden = YES;
		[bg addObject:_locatorLayer];

		_gpsTraceLayer = [[MercatorTileLayer alloc] initWithMapView:self];
		_gpsTraceLayer.zPosition = Z_GPSTRACE;
		_gpsTraceLayer.aerialService = [AerialService gpsTrace];
		_gpsTraceLayer.hidden = YES;
		[bg addObject:_gpsTraceLayer];

		_aerialLayer = [[MercatorTileLayer alloc] initWithMapView:self];
		_aerialLayer.zPosition = Z_AERIAL;
		_aerialLayer.opacity = 0.75;
		_aerialLayer.aerialService = self.customAerials.currentAerial;
		_aerialLayer.hidden = YES;
		[bg addObject:_aerialLayer];

		_mapnikLayer = [[MercatorTileLayer alloc] initWithMapView:self];
		_mapnikLayer.aerialService = [AerialService mapnik];
		_mapnikLayer.zPosition = Z_MAPNIK;
		_mapnikLayer.hidden = YES;
		[bg addObject:_mapnikLayer];

		_editorLayer = [[EditorMapLayer alloc] initWithMapView:self];
		_editorLayer.zPosition = Z_EDITOR;
		[bg addObject:_editorLayer];

#if 0
		_editorLayerGL = [[EditorLayerGL alloc] initWithMapView:self];
		_editorLayerGL.zPosition = Z_EDITOR_GL;
		[bg addObject:_editorLayerGL];
#endif

#if 0 // support gpx traces
		_gpxLayer = [[GpxLayer alloc] initWithMapView:self];
		_gpxLayer.zPosition = Z_GPX;
		[self.layer addSublayer:_gpxLayer];
#endif

		_backgroundLayers = [NSArray arrayWithArray:bg];
		for ( CALayer * layer in _backgroundLayers ) {
			[self.layer addSublayer:layer];
		}

		// bing logo
		{
#if TARGET_OS_IPHONE
			// button provided by storyboard
#else
			NSImage * image = [NSImage imageNamed:@"BingLogo.png"];
			assert(image);
			CGSize size = SizeForImage(image);
			_bingMapsLogo = [CALayer layer];
			_bingMapsLogo.zPosition = Z_BING_LOGO;
			_bingMapsLogo.contents = image;
			_bingMapsLogo.frame = CGRectMake(10, 10, size.width, size.height);
			[self.layer addSublayer:_bingMapsLogo];
#endif
		}

		_rulerLayer = [[RulerLayer alloc] init];
		_rulerLayer.mapView = self;
		_rulerLayer.zPosition = Z_RULER;
		[self.layer addSublayer:_rulerLayer];

#if defined(DEBUG)
		// enable for release, disable to measure perf
#else
		for ( CALayer * layer in _backgroundLayers ) {
			layer.drawsAsynchronously = YES;
		}
		_rulerLayer.drawsAsynchronously	= YES;
#endif

#if !TARGET_OS_IPHONE
		[self setFrame:frame];
#endif

#if TARGET_OS_IPHONE
		_editorLayer.mapData.undoCommentCallback = ^(BOOL undo,NSArray * comments){
			NSString * title = undo ? NSLocalizedString(@"Undo",nil) : NSLocalizedString(@"Redo",nil);
			NSArray * comment = comments.count == 0 ? nil : undo ? comments.lastObject : comments[0];
			NSString * action = comment[0];
			NSData * location = comment[1];
			if ( location.length == sizeof(OSMTransform) ) {
				OSMTransform transform = *(OSMTransform *)[location bytes];
				self.mapTransform = transform;
			} else {
				DLog(@"bad undo comment");
			}
			NSString * message = [NSString stringWithFormat:@"%@ %@", title, action];
			[self flashMessage:message];
		};
#endif
	}
	return self;
}

-(void)awakeFromNib
{
#if TARGET_OS_IPHONE
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:UIApplicationWillResignActiveNotification object:NULL];
#else
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:[NSApplication sharedApplication]];
#endif

	_zoomToEditLabel.layer.cornerRadius = 5;
	_zoomToEditLabel.layer.masksToBounds = YES;
	_zoomToEditLabel.backgroundColor = [UIColor whiteColor];
	_zoomToEditLabel.alpha = 0.5;
	_zoomToEditLabel.hidden = YES;

#if TARGET_OS_IPHONE
	_progressIndicator.color = NSColor.greenColor;
#endif

	if ( [CLLocationManager locationServicesEnabled] ) {
		_locationManager = [[CLLocationManager alloc] init];
		_locationManager.delegate = self;
#if TARGET_OS_IPHONE
		_locationManager.pausesLocationUpdatesAutomatically = YES;
		_locationManager.activityType = CLActivityTypeFitness;
#endif
	}

	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
								@"zoom"				: @(nan("")),
								@"translateX"		: @(nan("")),
								@"translateY"		: @(nan("")),
								@"mapViewState"		: @(MAPVIEW_EDITORAERIAL),
								}];

	// set up action button
	_editControl.hidden = YES;
	_editControl.selected = NO;
	_editControl.selectedSegmentIndex = UISegmentedControlNoSegment;
	[_editControl setTitleTextAttributes:@{ NSFontAttributeName : [UIFont boldSystemFontOfSize:17.0f] }
									   forState:UIControlStateNormal];

	self.viewState		 = (MapViewState) [[NSUserDefaults standardUserDefaults] integerForKey:@"mapViewState"];
	self.viewOverlayMask = (ViewOverlayMask) [[NSUserDefaults standardUserDefaults] integerForKey:@"mapViewOverlays"];

	[self updateBingButton];

	// get current location
	double zoom			= [[NSUserDefaults standardUserDefaults] doubleForKey:@"zoom"];
	double translateX	= [[NSUserDefaults standardUserDefaults] doubleForKey:@"translateX"];
	double translateY	= [[NSUserDefaults standardUserDefaults] doubleForKey:@"translateY"];
	if ( !isnan(translateX) && !isnan(translateY) && !isnan(zoom) ) {
		OSMTransform transform;
		transform.a = zoom;
		transform.b = 0;
		transform.c = 0;
		transform.d = zoom;
		transform.tx = translateX;
		transform.ty = translateY;
		self.mapTransform = transform;
	} else {
		self.mapTransform = OSMTransformIdentity();
	}

	if ( ![self isLocationSpecified] ) {
		[self locateMe:nil];
	}

	_notes = [Notes new];

	// make help button have rounded corners
	_helpButton.layer.cornerRadius = 10.0;

	// observe changes to aerial visibility so we can show/hide bing logo
	[_aerialLayer addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionNew context:NULL];
	[_editorLayer addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionNew context:NULL];
#if !TARGET_OS_IPHONE
	[self.window setAcceptsMouseMovedEvents:YES];
#endif

	_editorLayer.textColor = _aerialLayer.hidden ? NSColor.blackColor : NSColor.whiteColor;
}

-(void)setViewStateOverride:(BOOL)override
{
	[self setViewState:_viewState overlays:_viewOverlayMask override:override];
}
-(void)setViewState:(MapViewState)state
{
	[self setViewState:state overlays:_viewOverlayMask override:_viewStateOverride];
}
-(void)setViewOverlayMask:(ViewOverlayMask)mask
{
	[self setViewState:_viewState overlays:mask override:_viewStateOverride];
}

static inline MapViewState StateFor(MapViewState state, BOOL override)
{
	if ( override && state == MAPVIEW_EDITOR )
		return MAPVIEW_MAPNIK;
	if ( override && state == MAPVIEW_EDITORAERIAL )
		return MAPVIEW_AERIAL;
	return state;
}
static inline ViewOverlayMask OverlaysFor(MapViewState state, ViewOverlayMask mask, BOOL override)
{
	if ( override && state == MAPVIEW_EDITORAERIAL )
		return mask | VIEW_OVERLAY_LOCATOR;
	return mask;
}

-(void)setViewState:(MapViewState)state overlays:(ViewOverlayMask)overlays override:(BOOL)override
{
	if ( _viewState == state && _viewOverlayMask == overlays && _viewStateOverride == override )
		return;

	MapViewState oldState = StateFor(_viewState,_viewStateOverride);
	MapViewState newState = StateFor( state, override );
	ViewOverlayMask oldOverlays = OverlaysFor(_viewState, _viewOverlayMask, _viewStateOverride);
	ViewOverlayMask newOverlays = OverlaysFor(state, overlays, override);
	_viewState = state;
	_viewOverlayMask = overlays;
	_viewStateOverride = override;
	if ( newState == oldState && newOverlays == oldOverlays )
		return;

	// enable/disable editing buttons based on visibility
	[_viewController updateDeleteButtonState];
	[_viewController updateUndoRedoButtonState];

	dispatch_async(dispatch_get_main_queue(), ^{	// do this a little bit later so it can be animated
		[CATransaction begin];
		[CATransaction setAnimationDuration:0.5];

		_locatorLayer.hidden  = (newOverlays & VIEW_OVERLAY_LOCATOR) == 0;
		_gpsTraceLayer.hidden = (newOverlays & VIEW_OVERLAY_GPSTRACE) == 0;

		switch (newState) {
			case MAPVIEW_EDITOR:
				_editorLayer.textColor = NSColor.blackColor;
				_editorLayer.hidden = NO;
				_aerialLayer.hidden = YES;
				_mapnikLayer.hidden = YES;
				_zoomToEditLabel.hidden = YES;
				break;
			case MAPVIEW_EDITORAERIAL:
				_editorLayer.textColor = NSColor.whiteColor;
				_aerialLayer.aerialService = _customAerials.currentAerial;
				_editorLayer.hidden = NO;
				_aerialLayer.hidden = NO;
				_mapnikLayer.hidden = YES;
				_zoomToEditLabel.hidden = YES;
				break;
			case MAPVIEW_AERIAL:
				_aerialLayer.aerialService = _customAerials.currentAerial;
				_editorLayer.hidden = YES;
				_aerialLayer.hidden = NO;
				_mapnikLayer.hidden = YES;
				_zoomToEditLabel.hidden = YES;
				break;
			case MAPVIEW_MAPNIK:
				_editorLayer.hidden = YES;
				_aerialLayer.hidden = YES;
				_mapnikLayer.hidden = NO;
				_zoomToEditLabel.hidden = _viewState != MAPVIEW_EDITOR && _viewState != MAPVIEW_EDITORAERIAL;
				break;
			case MAPVIEW_NONE:
				// shouldn't occur
				_editorLayer.hidden = YES;
				_aerialLayer.hidden = YES;
				_mapnikLayer.hidden = YES;
				break;
		}
		[CATransaction commit];
	});

	[self updateBingButton];
}
-(MapViewState)viewState
{
	return _viewState;
}

-(IBAction)editAction:(id)sender
{
	UISegmentedControl * segmentedControl = (UISegmentedControl *) sender;
	NSInteger segment = segmentedControl.selectedSegmentIndex;
	if ( segment == 0 ) {
		// Tags
		[self editTags:sender];
	} else if ( segment == 1 ) {
		// Delete
		[self delete:sender];
	} else {
		// More
		[self.editorLayer presentEditActions:sender];
	}
	segmentedControl.selectedSegmentIndex = UISegmentedControlNoSegment;
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _aerialLayer && [keyPath isEqualToString:@"hidden"] ) {
		BOOL hidden = [[change valueForKey:NSKeyValueChangeNewKey] boolValue];
		_bingMapsLogo.hidden = hidden;
	} else if ( object == _editorLayer && [keyPath isEqualToString:@"hidden"] ) {
		BOOL hidden = [[change valueForKey:NSKeyValueChangeNewKey] boolValue];
		if ( hidden ) {
			_editorLayer.selectedNode = nil;
			_editorLayer.selectedWay = nil;
#if TARGET_OS_IPHONE
			[self removePin];
#endif
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)applicationWillTerminate :(NSNotification *)notification
{
	// save defaults first
	OSMTransform transform = self.mapTransform;
	[[NSUserDefaults standardUserDefaults] setDouble:transform.a forKey:@"zoom"];
	[[NSUserDefaults standardUserDefaults] setDouble:transform.tx forKey:@"translateX"];
	[[NSUserDefaults standardUserDefaults] setDouble:transform.ty forKey:@"translateY"];

	[[NSUserDefaults standardUserDefaults] setInteger:self.viewState forKey:@"mapViewState"];
	[[NSUserDefaults standardUserDefaults] setInteger:self.viewOverlayMask forKey:@"mapViewOverlaysa"];

	[[NSUserDefaults standardUserDefaults] synchronize];

	[self.customAerials save];

	// then save data
	[_editorLayer save];
}

-(void)setFrame:(CGRect)frameRect
{
	[super setFrame:frameRect];

	[CATransaction begin];
	[CATransaction setAnimationDuration:0.0];
#if TARGET_OS_IPHONE
	CGRect rect = CGRectMake(10, frameRect.size.height - 80, 150, 30);
	_rulerLayer.frame = rect;
#else
	CGRect rect = CGRectMake(10, frameRect.size.height - 40, 150, 30);
	_rulerLayer.frame = rect;
#endif

	CGRect	bounds = self.bounds;
	CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
	bounds.origin.x = -center.x - 128;
	bounds.origin.y = -center.y - 128;
	for ( CALayer * layer in _backgroundLayers ) {
		if ( [layer isKindOfClass:[MercatorTileLayer class]] ) {
			layer.bounds = bounds;
			layer.position = center;
		}
	}

	bounds.origin.x = -center.x;
	bounds.origin.y = -center.y;
	bounds.size = self.bounds.size;
	_editorLayer.bounds = bounds;
	_editorLayer.position = center;
	_editorLayerGL.bounds = bounds;
	_editorLayerGL.position = center;
	_gpxLayer.bounds = bounds;
	_gpxLayer.position = center;

	[CATransaction commit];
}

#pragma mark Utility

-(BOOL)isFlipped
{
	return YES;
}

-(void)updateBingButton
{
	_bingMapsLogo.hidden = self.aerialLayer.hidden || !self.aerialLayer.aerialService.isBingAerial;
}


-(void)flashMessage:(NSString *)message duration:(NSTimeInterval)duration
{
#if TARGET_OS_IPHONE
	const CGFloat MAX_ALPHA = 0.8;

	if ( _flashLabel == nil ) {
		_flashLabel = [UILabel new];
		_flashLabel.font = [UIFont boldSystemFontOfSize:18];
		_flashLabel.textAlignment = NSTextAlignmentCenter;
		_flashLabel.textColor = UIColor.whiteColor;
		_flashLabel.backgroundColor = UIColor.blackColor;
		_flashLabel.layer.cornerRadius = 15;
		_flashLabel.layer.masksToBounds = YES;
		_flashLabel.layer.zPosition = Z_FLASH;
		_flashLabel.hidden = YES;
		[self addSubview:_flashLabel];
	}

	_flashLabel.text = message;

	// set size/position
	[_flashLabel sizeToFit];
	CGRect rc = _flashLabel.frame;
	rc.origin.x = self.bounds.origin.x + (self.bounds.size.width - rc.size.width) / 2;
	rc.origin.y = self.bounds.origin.y + self.bounds.size.height/4 + (self.bounds.size.height - rc.size.height) / 2;
	rc = CGRectInset(rc, -20, -20);
	_flashLabel.frame = rc;

	if ( _flashLabel.hidden ) {
		// animate in
		_flashLabel.alpha = 0.0;
		_flashLabel.hidden = NO;
		[UIView animateWithDuration:0.25 animations:^{
			_flashLabel.alpha = MAX_ALPHA;
		}];
	} else {
		// already displayed
		[_flashLabel.layer removeAllAnimations];
		_flashLabel.alpha = MAX_ALPHA;
	}

	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, duration * NSEC_PER_SEC);
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		[UIView animateWithDuration:0.25 animations:^{
			_flashLabel.alpha = 0.0;
		} completion:^(BOOL finished){
			if ( finished && ((CALayer *)_flashLabel.layer.presentationLayer).opacity == 0.0 ) {
				_flashLabel.hidden = YES;
			}
		}];
	});
#endif
};

-(void)flashMessage:(NSString *)message
{
	[self flashMessage:message duration:0.7];
}

-(void)presentError:(NSError *)error flash:(BOOL)flash
{
	if ( _lastErrorDate == nil || [[NSDate date] timeIntervalSinceDate:_lastErrorDate] > 3.0 ) {

		NSString * text = error.localizedDescription;

		if ( [error.domain isEqualToString:@"HTTP"] && error.code >= 400 && error.code < 500 ) {
			// present HTML error code
			WebPageViewController * webController = [[WebPageViewController alloc] initWithNibName:@"WebPageView" bundle:nil];
			[webController view];
			[[webController.navBar.items lastObject] setTitle:NSLocalizedString(@"Error",nil)];
			[webController.webView loadHTMLString:error.localizedDescription baseURL:nil];
			[self.viewController presentViewController:webController animated:YES completion:nil];
			_lastErrorDate = [NSDate date];
			return;
		}

#if 0
		id ignorable = [error.userInfo objectForKey:@"Ignorable"];
		if ( ignorable )
			return;
#endif

#if TARGET_OS_IPHONE
		BOOL isNetworkError = NO;
		NSString * title = NSLocalizedString(@"Error",nil);
		NSString * ignoreButton = nil;
		if ( [[error userInfo] valueForKey:@"NSErrorFailingURLKey"] )
			isNetworkError = YES;
		NSError * underError = [[error userInfo] valueForKey:@"NSUnderlyingError"];
		if ( [underError isKindOfClass:[NSError class]] ) {
			if ( [underError.domain isEqualToString:(NSString *)kCFErrorDomainCFNetwork] )
				isNetworkError = YES;
		}
		if ( isNetworkError ) {
			if ( _ignoreNetworkErrorsUntilDate && [[NSDate date] timeIntervalSinceDate:_ignoreNetworkErrorsUntilDate] >= 0 )
				_ignoreNetworkErrorsUntilDate = nil;
			if ( _ignoreNetworkErrorsUntilDate )
				return;
			title = NSLocalizedString(@"Network error",nil);
			ignoreButton = NSLocalizedString(@"Ignore",nil);
		}

		// don't let message be too long
		if ( text.length > 1000 ) {
			NSMutableString * newText = [NSMutableString stringWithString:text];
			[newText deleteCharactersInRange:NSMakeRange(1000, text.length-1000)];
			[newText appendString:@"..."];
			text = newText;
		}

		if ( flash ) {
			[self flashMessage:text duration:0.9];
		} else {
			_alertError = [[UIAlertView alloc] initWithTitle:title message:text delegate:self cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:ignoreButton, nil];
			[_alertError show];
		}
#else
		if ( [text.uppercaseString hasPrefix:@"<!DOCTYPE HTML"] ) {
			_htmlErrorWindow = [[HtmlErrorWindow alloc] initWithHtml:text];
			[NSApp beginSheet:_htmlErrorWindow.window modalForWindow:self.window modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
		} else {
			NSAlert * alert = [NSAlert alertWithError:error];
			[alert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:NULL contextInfo:NULL];
		}
#endif
	}
	if ( !flash ) {
		_lastErrorDate = [NSDate date];
	}
}

#pragma mark Coordinate Transforms

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude width:(double)widthDegrees
{
	OSMPoint point = [MapView mapPointForLatitude:latitude longitude:longitude];
	CGFloat zoom = 360 / (widthDegrees / 2);
	OSMTransform transform = { 0 };
	transform.a = zoom;
	transform.d = zoom;
	transform.tx = -(point.x - 128)*zoom;
	transform.ty = -(point.y - 128)*zoom;
	self.mapTransform = transform;
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude
{
	OSMPoint point = [MapView mapPointForLatitude:latitude longitude:longitude];
	CGFloat zoom = _mapTransform.a;
	OSMTransform transform = { 0 };
	transform.a = zoom;
	transform.d = zoom;
	transform.tx = -(point.x - 128)*zoom;
	transform.ty = -(point.y - 128)*zoom;
	self.mapTransform = transform;
}

// get view into 256 map
-(OSMRect)mapRectFromVisibleRect
{
	CGRect viewRect = self.layer.bounds;
	OSMTransform t = self.mapTransform;
	if ( t.a == 0 && t.d == 0 )
		return OSMRectZero();

#if 0
	OSMTransform ti = OSMTransformInvert( t );
	OSMRect mapRect = OSMRectFromCGRect( viewRect );
	mapRect = OSMRectOffset( mapRect, -mapRect.size.width/2, -mapRect.size.height/2);
	mapRect = OSMRectApplyAffineTransform( mapRect, ti );
	mapRect = OSMRectOffset(mapRect, -128, -128);
	return mapRect;
#else
	OSMRect mapRect2;
	mapRect2.origin.x = viewRect.origin.x - (t.tx + viewRect.size.width/2) / t.a  - 128;
	mapRect2.origin.y = viewRect.origin.y - (t.ty + viewRect.size.height/2) / t.a - 128;
	mapRect2.size.width  = viewRect.size.width  / t.a;
	mapRect2.size.height = viewRect.size.height / t.a;
	return mapRect2;
#endif

#if 0
	DLog(@"\n");
	DLog(@"scale3 = %@", NSStringFromRect(mapRect) );
#endif
}

-(OSMRect)viewRectFromMapRect:(OSMRect)mapRect
{
	mapRect = OSMRectOffset(mapRect, 128, 128);
	mapRect = OSMRectApplyAffineTransform( mapRect, self.mapTransform );
	mapRect = OSMRectOffset( mapRect, mapRect.size.width/2, mapRect.size.height/2);
	return mapRect;
}

-(CLLocationCoordinate2D)longitudeLatitudeForViewPoint:(CGPoint)point
{
	CGRect viewRect = self.layer.bounds;
	OSMTransform t = self.mapTransform;
	OSMPoint mapPoint;
	mapPoint.x = viewRect.origin.x - (t.tx + viewRect.size.width/2 - point.x) / t.a - 128;
	mapPoint.y = viewRect.origin.y - (t.ty + viewRect.size.height/2 - point.y) / t.a - 128;

	OSMPoint coord = [MapView longitudeLatitudeFromMapPoint:mapPoint];
	CLLocationCoordinate2D loc = { coord.y, coord.x };
	return loc;
}

-(double)metersPerPixel
{
	// compute meters/pixel
	OSMRect viewCoord = [self viewportLongitudeLatitude];
	if ( viewCoord.size.width <= 0.0 || viewCoord.size.height <= 0.0 )
		return 0.0;
	const double earthRadius = 6378137.0; // meters
	const double circumference = 2 * M_PI * earthRadius;
	double metersPerPixel = (viewCoord.size.height / 360 * circumference) / self.bounds.size.height;
#if 0
	DLog(@"coord = %f,%f  %f,%f", viewCoord.origin.x, viewCoord.origin.y, viewCoord.origin.x+viewCoord.size.width, viewCoord.origin.y+viewCoord.size.height);
	DLog(@"meters/pixel = %f", metersPerPixel);
#endif
	if ( isnan(metersPerPixel) )
		return 0.0;
	
	return metersPerPixel;
}


+(OSMPoint)longitudeLatitudeFromMapPoint:(OSMPoint)point
{
	double x = point.x / 256;
	double y = point.y / 256;
    x = x - floor(x);	// modulus
	y = y - floor(y);
	x = x - 0.5;
	y = 0.5 - y;

	OSMPoint loc;
	loc.y = 90 - 360 * atan(exp(-y * 2 * M_PI)) / M_PI;
	loc.x = 360 * x;
	return loc;
}
+(OSMPoint)mapPointForLatitude:(double)latitude longitude:(double)longitude;
{
	double x = (longitude + 180) / 360;
	double sinLatitude = sin(latitude * M_PI / 180);
	double y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * M_PI);
	OSMPoint point = { x * 256, y * 256 };
	return point;
}

-(OSMRect)viewportLongitudeLatitude
{
	OSMRect rc = [self mapRectFromVisibleRect];
	OSMPoint southwest = { rc.origin.x, rc.origin.y + rc.size.height };
	OSMPoint northeast = { rc.origin.x + rc.size.width, rc.origin.y };
	southwest = [MapView longitudeLatitudeFromMapPoint:southwest];
	northeast = [MapView longitudeLatitudeFromMapPoint:northeast];
	rc.origin.x = southwest.x;
	rc.origin.y = southwest.y;
	rc.size.width = northeast.x - southwest.x;
	rc.size.height = northeast.y - southwest.y;
	if ( rc.size.width < 0 ) // crossed 180 degrees longitude
		rc.size.width += 360;
	return rc;
}

-(CGPoint)viewPointForLatitude:(double)latitude longitude:(double)longitude
{
	CGRect bounds = self.bounds;
	OSMRect rc = [self mapRectFromVisibleRect];
	OSMPoint pt = [MapView mapPointForLatitude:latitude longitude:longitude];
	pt.x -= rc.origin.x;
	pt.y -= rc.origin.y;
	while ( pt.x >= 128.0 )
		pt.x -= 256.0;
	while ( pt.y >= 128.0 )
		pt.y -= 256.0;
	while ( pt.x < -128.0 )
		pt.x += 256.0;
	while ( pt.y < -128.0 )
		pt.y += 256.0;
	pt.x = bounds.origin.x + pt.x/rc.size.width * bounds.size.width;
	pt.y = bounds.origin.y + pt.y/rc.size.height * bounds.size.height;
	return CGPointFromOSMPoint( pt );
}

#pragma mark Progress indicator

-(void)progressIncrement:(BOOL)animate
{
	assert( _progressActive >= 0 );
	if ( _progressActive++ == 0 && animate ) {
#if TARGET_OS_IPHONE
		[_progressIndicator startAnimating];
#else
		[_progressIndicator startAnimation:self];
#endif
	}
}
-(void)progressDecrement
{
	assert( _progressActive > 0 );
	if ( --_progressActive == 0 ) {
#if TARGET_OS_IPHONE
		[_progressIndicator stopAnimating];
#else
		[_progressIndicator stopAnimation:self];
#endif
	}
}
-(void)progressAnimate
{
	assert( _progressActive >= 0 );
	if ( _progressActive > 0 ) {
#if TARGET_OS_IPHONE
		[_progressIndicator startAnimating];
#else
		[_progressIndicator startAnimation:self];
#endif
	}
}

#pragma mark Location manager

- (BOOL)trackingLocation
{
	return _trackingLocation;
}
- (void)setTrackingLocation:(BOOL)trackingLocation
{
	if ( trackingLocation != _trackingLocation ) {
		_trackingLocation = trackingLocation;
		if ( trackingLocation ) {
			[self locateMe:nil];
		} else {
			[self.locationManager stopUpdatingLocation];
#if TARGET_OS_IPHONE
			[self.locationManager stopUpdatingHeading];
#endif
			[_locationBallLayer removeFromSuperlayer];
			_locationBallLayer = nil;
		}
	}
}

-(IBAction)locateMe:(id)sender
{
	CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
	if ( status == kCLAuthorizationStatusRestricted || status == kCLAuthorizationStatusDenied ) {
		NSString * appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
		NSString * title = [NSString stringWithFormat:NSLocalizedString(@"Turn On Location Services to Allow %@ to Determine Your Location",nil),appName];
		_alertGps = [[UIAlertView alloc] initWithTitle:title message:nil delegate:self cancelButtonTitle:NSLocalizedString(@"OK",nil) otherButtonTitles:nil];
		[_alertGps show];
		self.trackingLocation = NO;
		return;
	}

	// ios 8 and later:
	if ( [_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)] ) {
		[_locationManager requestWhenInUseAuthorization];
	}

	_userOverrodeLocationPosition	= NO;
	_userOverrodeLocationZoom		= NO;
	[_locationManager startUpdatingLocation];
#if TARGET_OS_IPHONE
	[_locationManager startUpdatingHeading];
#else
	[self performSelector:@selector(locationUpdateFailed:) withObject:nil afterDelay:5.0];
#endif
}

-(void)locationUpdateFailed:(NSError *)error
{
	self.trackingLocation = NO;

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(locationUpdateFailed:) object:nil];

	if ( ![self isLocationSpecified] ) {
		// go home
		OSMTransform transform = { 0 };
		transform.a = transform.d = 106344;
		transform.tx = 9241972;
		transform.ty = 4112460;
		self.mapTransform = transform;
	}

	NSString * text = [NSString stringWithFormat:NSLocalizedString(@"Ensure Location Services is enabled and you have granted this application access.\n\nError: %@",nil),
					   error ? error.localizedDescription : NSLocalizedString(@"Location services timed out.",nil)];
	text = [NSLocalizedString(@"The current location cannot be determined: ",nil) stringByAppendingString:text];
	if ( error ) {
		error = [NSError errorWithDomain:@"Location" code:100 userInfo:@{ NSLocalizedDescriptionKey : text, NSUnderlyingErrorKey : error} ];
	} else {
		error = [NSError errorWithDomain:@"Location" code:100 userInfo:@{ NSLocalizedDescriptionKey : text} ];
	}
	[self presentError:error flash:NO];
}

- (void)updateUserLocationIndicator
{
	if ( _locationBallLayer ) {
		CLLocationCoordinate2D coord = _locationManager.location.coordinate;
		_locationBallLayer.position = [self viewPointForLatitude:coord.latitude longitude:coord.longitude];
	}
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
	if ( _locationBallLayer ) {
		_locationBallLayer.headingAccuracy	= newHeading.headingAccuracy * M_PI / 180;
		_locationBallLayer.heading			= (newHeading.trueHeading - 90) * M_PI / 180;
		_locationBallLayer.showHeading		= YES;
	}
}



- (void)locationUpdatedTo:(CLLocation *)newLocation
{
	//	DLog(@"updating with %@",_locationManager.location);

	if ( _gpxLayer.activeTrack ) {
		[_gpxLayer addPoint:newLocation];
	}

	if ( !self.trackingLocation ) {
		[_locationManager stopUpdatingLocation];
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(locationUpdateFailed:) object:nil];

#if TARGET_OS_IPHONE
	CLLocationCoordinate2D pp = [self longitudeLatitudeForViewPoint:_pushpinView.arrowPoint];
#endif

	if ( !_userOverrodeLocationPosition ) {
		// move view to center on new location
		if ( _userOverrodeLocationZoom ) {
			[self setTransformForLatitude:newLocation.coordinate.latitude longitude:newLocation.coordinate.longitude];
		} else {
			double widthDegrees = 60 /*meters*/ / EarthRadius * 360;
			[self setTransformForLatitude:newLocation.coordinate.latitude longitude:newLocation.coordinate.longitude width:widthDegrees];
		}
	}
#if TARGET_OS_IPHONE
	_pushpinView.arrowPoint = [self viewPointForLatitude:pp.latitude longitude:pp.longitude];
#endif

	if ( _locationBallLayer == nil ) {
		_locationBallLayer = [LocationBallLayer new];
		_locationBallLayer.zPosition = Z_BALLOON;
		_locationBallLayer.heading = 0.0;
		_locationBallLayer.showHeading = YES;
		[self.layer addSublayer:_locationBallLayer];
	}
	[self updateUserLocationIndicator];
}

// delegate for iIOS 6 and later
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
	[self locationUpdatedTo:locations.lastObject];
}

// delegate for iIOS 5 and earlier
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
	[self locationUpdatedTo:newLocation];
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
	[self locationUpdateFailed:error];
}


#pragma mark Undo/Redo

-(void)placePushpinForSelection
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.selectedNode ) {
		CGPoint point = [self viewPointForLatitude:_editorLayer.selectedNode.lat longitude:_editorLayer.selectedNode.lon];
		[self placePushpinAtPoint:point object:_editorLayer.selectedNode];
	} else if ( _editorLayer.selectedWay ) {
		OSMPoint pt = [_editorLayer.selectedWay centerPoint];
		CGPoint point = [self viewPointForLatitude:pt.y longitude:pt.x];
		[self placePushpinAtPoint:point object:_editorLayer.selectedPrimary];
	} else if (_editorLayer.selectedRelation ) {
		OSMPoint pt = [_editorLayer.selectedRelation centerPoint];
		CGPoint point = [self viewPointForLatitude:pt.y longitude:pt.x];
		[self placePushpinAtPoint:point object:_editorLayer.selectedPrimary];
	}
#endif
}

- (IBAction)undo:(id)sender
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.hidden ) {
		[self flashMessage:NSLocalizedString(@"Editing layer not visible",nil)];
		return;
	}
	// if just dropped a pin then undo removes the pin
	if ( _pushpinView && _editorLayer.selectedPrimary == nil ) {
		[self removePin];
		return;
	}

	[self removePin];
#endif

	[_editorLayer.mapData undo];
	[_editorLayer setNeedsDisplay];

	[self placePushpinForSelection];
}

- (IBAction)redo:(id)sender
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.hidden ) {
		[self flashMessage:@"Editing layer not visible"];
		return;
	}
	[self removePin];
#endif

	[_editorLayer.mapData redo];
	[_editorLayer setNeedsDisplay];

	[self placePushpinForSelection];
}

#if !TARGET_OS_IPHONE
- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
    SEL theAction = [anItem action];
    if ( theAction == @selector(undo:) ) {
		return [_editorLayer.mapData canUndo];
	}
	if ( theAction == @selector(redo:)) {
		return [_editorLayer.mapData canRedo];
	}
	return YES;
}
#endif

#pragma mark Resize & movement

-(BOOL)isLocationSpecified
{
	OSMTransform transform = self.mapTransform;
	return transform.a != 1 || transform.tx != 0 || transform.ty != 0;
}

-(void)setMousePoint:(CGPoint)point
{
#if !TARGET_OS_IPHONE
	// update longitude/latitude property
	CLLocationCoordinate2D loc = [self longitudeLatitudeForViewPoint:point];

	[self willChangeValueForKey:@"mouseLongitude"];
	[self willChangeValueForKey:@"mouseLatitude"];
	_mouseLongitude = loc.longitude;
	_mouseLatitude  = loc.latitude;
	[self didChangeValueForKey:@"mouseLongitude"];
	[self didChangeValueForKey:@"mouseLatitude"];
#endif
}

-(void)updateMouseCoordinates
{
#if !TARGET_OS_IPHONE
	CGPoint point = [NSEvent mouseLocation];
	point = [self.window convertScreenToBase:point];
	point = [self convertPoint:point fromView:nil];
	[self setMousePoint:point];
#endif
}

-(void)setMapTransform:(OSMTransform)mapTransform
{
	if ( OSMTransformEqual(mapTransform, _mapTransform) )
		return;

#if TARGET_OS_IPHONE
	// save pushpinView coordinates
	CLLocationCoordinate2D pp = { 0 };
	if ( _pushpinView ) {
		pp = [self longitudeLatitudeForViewPoint:_pushpinView.arrowPoint];
	}
#endif

	// update transform
	_mapTransform = mapTransform = OSMTransformWrap256( mapTransform );

	// determine if we've zoomed out enough to disable editing
	OSMRect box = [self viewportLongitudeLatitude];
	double area = SurfaceArea( box );
	self.viewStateOverride = area > 10.0*1000*1000;

	[_rulerLayer updateDisplay];
	[self updateMouseCoordinates];
	[self updateUserLocationIndicator];

#if TARGET_OS_IPHONE
	// update pushpin location
	if ( _pushpinView ) {
		_pushpinView.arrowPoint = [self viewPointForLatitude:pp.latitude longitude:pp.longitude];
	}
#endif
}

-(void)adjustOriginBy:(CGPoint)delta
{
	if ( delta.x == 0.0 && delta.y == 0.0 )
		return;
	CGFloat zoom = 1.0 / _mapTransform.a;
	self.mapTransform = OSMTransformTranslate( _mapTransform, delta.x*zoom, -delta.y*zoom );
}


-(void)adjustZoomBy:(CGFloat)ratio
{
	if ( ratio == 1.0 )
		return;
	self.mapTransform = OSMTransformScale( _mapTransform, ratio );
}

-(void)drawRect:(CGRect)rect
{
	[_fpsLabel frameUpdated];
}

#pragma mark Key presses

// Escape key
-(IBAction)cancelOperation:(id)sender
{
	[_editorLayer cancelOperation];

#if !TARGET_OS_IPHONE
	CGPoint point = [NSEvent mouseLocation];
	point = [self.window convertScreenToBase:point];
	point = [self convertPoint:point fromView:nil];
	[self setCursorForPoint:point];
#endif
}


#if TARGET_OS_IPHONE
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if ( alertView == _alertDelete ) {
		if ( buttonIndex == 1 ) {
			[_editorLayer deleteSelectedObject];
			[self removePin];
		}
		_alertDelete = nil;
	}
	if ( alertView == _alertError ) {
		if ( buttonIndex == 1 ) {
			// ignore network errors for a while
			_ignoreNetworkErrorsUntilDate = [[NSDate date] dateByAddingTimeInterval:5*60.0];
		}
		_alertError = nil;
	}
	if ( alertView == _alertMove ) {
		if ( buttonIndex == 0 ) {
			// cancel move
			[_editorLayer.mapData undo];
			[_editorLayer.mapData removeMostRecentRedo];
			[_editorLayer setNeedsDisplay];
			[self removePin];
		} else {
			// okay
		}
		_alertMove = nil;
	}
}
#endif

-(IBAction)delete:(id)sender
{
#if TARGET_OS_IPHONE
	_alertDelete = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Delete",nil) message:NSLocalizedString(@"Delete selection?",nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel",nil) otherButtonTitles:NSLocalizedString(@"Delete",nil), nil];
	[_alertDelete show];
#else
	[_editorLayer deleteSelectedObject];
#endif
}

-(void)keyDown:(NSEvent *)event
{
#if !TARGET_OS_IPHONE
	NSString * chars = [event characters];
	unichar character = [chars characterAtIndex:0];
	double angle = 0.0;
	switch ( character ) {
		case NSLeftArrowFunctionKey:
			angle = M_PI * -1 / 180;
			break;
		case NSRightArrowFunctionKey:
			angle = M_PI * 1 / 180;
			break;
		default:
			break;
	}
	if ( angle ) {
		self.mapTransform = OSMTransformRotate( self.mapTransform, angle );
	}
#endif
}

#pragma mark Editing

#if TARGET_OS_IPHONE
-(OsmBaseObject *)dragConnectionForNode:(OsmNode *)node segment:(NSInteger *)segment
{
	assert( node.isNode );
	assert( _editorLayer.selectedWay );

	OsmWay * way = _editorLayer.selectedWay;
	if ( node != way.nodes[0] && node != way.nodes.lastObject )
		return nil;
	if ( node.wayCount > 1 )
		return nil;

	NSArray * ignoreList = nil;
	NSInteger index = [way.nodes indexOfObject:node];
	if ( way.nodes.count < 4 ) {
		ignoreList = [way.nodes arrayByAddingObject:way];
	} else if ( index == 0 ) {
		ignoreList = @[ way, way.nodes[0], way.nodes[1], way.nodes[2] ];
	} else if ( index == way.nodes.count-1 ) {
		ignoreList = @[ way, way.nodes[index], way.nodes[index-1], way.nodes[index-2] ];
	} else {
		assert(NO);
	}
	OsmBaseObject * hit = [EditorMapLayer osmHitTest:_pushpinView.arrowPoint
											 mapView:self
											 objects:_editorLayer.shownObjects
										   testNodes:YES
										  ignoreList:ignoreList
											 segment:segment];
	return hit;
}

#pragma mark PushPin

-(IBAction)editTags:(id)sender
{
	if ( self.editorLayer.selectedWay && self.editorLayer.selectedNode && self.editorLayer.selectedWay.tags.count == 0 ) {
		// if trying to edit a node in a way that has no tags assume user wants to edit the way instead
		self.editorLayer.selectedNode = nil;
		[self refreshPushpinText];
	}
	[self.viewController performSegueWithIdentifier:@"poiSegue" sender:nil];
}

- (void)updateEditControl
{
	BOOL show = (_pushpinView || _editorLayer.selectedWay || _editorLayer.selectedNode) && !_editorLayer.selectedRelation;
	_editControl.hidden = !show;
	if ( show ) {
		if ( _editorLayer.selectedPrimary == nil ) {
			// show only Tags button
			if ( _editControl.numberOfSegments != 1 ) {
				[_editControl removeSegmentAtIndex:1 animated:NO];
				[_editControl removeSegmentAtIndex:1 animated:NO];
			}
		} else {
			if ( _editControl.numberOfSegments != 3 ) {
				[_editControl insertSegmentWithTitle:NSLocalizedString(@"Delete",nil) atIndex:1 animated:NO];
				[_editControl insertSegmentWithTitle:NSLocalizedString(@"More...",nil) atIndex:2 animated:NO];
			}
		}
	}
}

-(void)removePin
{
	if ( _pushpinView ) {
		[_pushpinView removeFromSuperview];
		_pushpinView = nil;
		[self updateEditControl];
	}
}

-(void)placePushpinAtPoint:(CGPoint)point object:(OsmBaseObject *)object
{
	// drop in center of screen
	[self removePin];

	_pushpinView = [PushPinView new];
	_pushpinView.text = object ? object.friendlyDescription : NSLocalizedString(@"(new object)",nil);
	_pushpinView.layer.zPosition = Z_BALLOON;

	_pushpinView.arrowPoint = point;

	__weak MapView * weakSelf = self;
	if ( object ) {
		_pushpinView.dragCallback = ^(UIGestureRecognizerState state, CGFloat dx, CGFloat dy) {
			switch ( state ) {
				case UIGestureRecognizerStateBegan:
					[weakSelf.editorLayer.mapData beginUndoGrouping];
					break;
					
				case UIGestureRecognizerStateEnded:
					[weakSelf.editorLayer.mapData endUndoGrouping];
					
					[weakSelf unblinkObject];
					if ( weakSelf.editorLayer.selectedWay && object.isNode ) {
						// dragging a node that is part of a way
						OsmNode * dragNode = (id)object;
						OsmWay * way = weakSelf.editorLayer.selectedWay;
						NSInteger segment;
						OsmBaseObject * hit = [weakSelf dragConnectionForNode:dragNode segment:&segment];
						if ( hit.isNode ) {
							// replace dragged node with hit node
							OsmNode * hitNode = (id)hit;
							NSInteger index = [way.nodes indexOfObject:object];
							[weakSelf.editorLayer deleteNode:dragNode fromWay:way allowDegenerate:YES];
							[weakSelf.editorLayer addNode:hitNode toWay:way atIndex:index];
							if ( way.isArea ) {
								weakSelf.editorLayer.selectedNode = nil;
								OSMPoint center = way.centerPoint;
								CGPoint centerPoint = [weakSelf viewPointForLatitude:center.y longitude:center.x];
								[weakSelf placePushpinAtPoint:centerPoint object:way];
							} else {
								CGPoint newPoint = [weakSelf viewPointForLatitude:hitNode.lat longitude:hitNode.lon];
								weakSelf.editorLayer.selectedNode = (id)hit;
								[weakSelf placePushpinAtPoint:newPoint object:hitNode];
							}
						}
						if ( hit.isWay ) {
							// add new node to hit way
							OsmWay * hitWay = (id)hit;
							OSMPoint pt = [dragNode location];
							pt = [hitWay pointOnWayForPoint:pt];
							[weakSelf.editorLayer.mapData setLongitude:pt.x latitude:pt.y forNode:dragNode inWay:weakSelf.editorLayer.selectedWay];
							[weakSelf.editorLayer addNode:dragNode toWay:hitWay atIndex:segment+1];
						}
						return;
					}
					if ( weakSelf.editorLayer.selectedWay && weakSelf.editorLayer.selectedWay.tags.count == 0 && weakSelf.editorLayer.selectedWay.relations.count == 0 )
						break;
					if ( weakSelf.editorLayer.selectedWay && weakSelf.editorLayer.selectedNode )
						break;
					{
						MapView * mySelf = weakSelf;
						mySelf->_alertMove = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Confirm move",nil) message:NSLocalizedString(@"Move selected object?",nil)
																delegate:weakSelf cancelButtonTitle:NSLocalizedString(@"Undo",nil) otherButtonTitles:NSLocalizedString(@"Move",nil), nil];
						[mySelf->_alertMove show];
					}
					break;
					
				case UIGestureRecognizerStateChanged:
					for ( OsmNode * node in object.nodeSet ) {
						CGPoint delta = { dx, -dy };
						[weakSelf.editorLayer adjustNode:node byDistance:delta];
					}
					if ( weakSelf.editorLayer.selectedWay && object.isNode ) {
						NSInteger segment;
						OsmBaseObject * hit = [weakSelf dragConnectionForNode:(id)object segment:&segment];
						if ( hit ) {
							[weakSelf blinkObject:hit segment:segment];
						} else {
							[weakSelf unblinkObject];
						}
					}
					break;
				default:
					break;
			}
		};
	}

	[self updateEditControl];

#if 0
	UIButton * button1 = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
	button1.backgroundColor = [UIColor whiteColor]; // don't want transparent background for ios 7
	button1.layer.cornerRadius = 10.0;
	[_pushpinView addButton:button1 callback:^{
		[weakSelf editTags:nil];
	}];

	if ( YES ) {
		UIButton * button2 = [UIButton buttonWithType:UIButtonTypeContactAdd];
		__weak MapView * weakSelf = self;
		[_pushpinView addButton:button2 callback:^{
			[weakSelf interactiveExtendSelectedWay:nil];
		}];
	}
#endif

#if 0
	UIButton * button2 = [UIButton buttonWithType:UIButtonTypeCustom];
	button2.frame = CGRectMake( 0, 0, 29, 29 );
	[button2 setBackgroundImage:[UIImage imageNamed:@"move2.png"] forState:UIControlStateNormal];
	[_pushpinView addButton:button2 callback:^{
		[self.viewController performSegueWithIdentifier:@"poiSegue" sender:nil];
	}];

	UIButton * button3 = [UIButton buttonWithType:UIButtonTypeCustom];
	button3.frame = CGRectMake( 0, 0, 26, 26 );
	[button3 setBackgroundImage:[UIImage imageNamed:@"wrench.png"] forState:UIControlStateNormal];
	[button3 setBackgroundColor:[UIColor colorWithRed:0.4 green:0.4 blue:1.0 alpha:1.0]];
	button3.layer.cornerRadius = button3.frame.size.width / 2;
	button3.layer.borderColor = UIColor.whiteColor.CGColor;
	button3.layer.borderWidth = 2.0;
	[_pushpinView addButton:button3 callback:^{
		[self.viewController performSegueWithIdentifier:@"poiSegue" sender:nil];
	}];
#endif
	
	if ( object == nil ) {
		_pushpinView.placeholderImage = [UIImage imageNamed:@"question.png"];
	}
	
	[self addSubview:_pushpinView];

	if ( object == nil ) {
		// do animation if creating a new object
		[_pushpinView animateMoveFrom:CGPointMake(self.bounds.origin.x+self.bounds.size.width,self.bounds.origin.y)];
	}
}

- (void)refreshPushpinText
{
	_pushpinView.text = _editorLayer.selectedPrimary.friendlyDescription;
}

-(IBAction)interactiveExtendSelectedWay:(id)sender
{
	if ( !_pushpinView )
		return;
	OsmWay * way = _editorLayer.selectedWay;
	OsmNode * node = _editorLayer.selectedNode;
	CGPoint prevPoint = _pushpinView.arrowPoint;

	if ( way && !node ) {
		// add new node at point
		NSInteger segment;
		OsmBaseObject * object = [_editorLayer osmHitTestSelection:prevPoint segment:&segment];
		if ( object == nil ) {
			UIAlertView * alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Select location",nil)
															 message:NSLocalizedString(@"Select the location in the way in which to create the new node",nil)
															delegate:nil
												   cancelButtonTitle:NSLocalizedString(@"OK",nil)
												   otherButtonTitles:nil];
			[alert show];
			return;
		}
		OsmNode * newNode = [_editorLayer createNodeAtPoint:prevPoint];
		[_editorLayer.mapData addNode:newNode toWay:way atIndex:segment+1];
		_editorLayer.selectedNode = newNode;
		[self placePushpinAtPoint:prevPoint object:newNode];

	} else {

		if ( node && way && way.nodes.count ) {
			if ( way.isClosed )
				return;
			if ( !(node == way.nodes[0] || node == way.nodes.lastObject) ) {
				// both a node and way selected but node is not an endpoint
				return;
			}
		}

		if ( node == nil ) {
			node = [_editorLayer createNodeAtPoint:prevPoint];
		}
		if ( way == nil ) {
			way = [_editorLayer createWayWithNode:node];
		}
		NSInteger prevIndex = [way.nodes indexOfObject:node];
		NSInteger nextIndex = prevIndex;
		if ( nextIndex == way.nodes.count - 1 )
			++nextIndex;
		// add new node at point
		CGPoint newPoint;
		if ( way.nodes.count < 2 ) {
			// create 2nd point in the direction of the center of the screen
			CGPoint centerPoint = self.center;
			BOOL vert = fabs(prevPoint.x - centerPoint.x) < fabs(prevPoint.y - centerPoint.y);
			if ( vert ) {
				newPoint.x = prevPoint.x;
				newPoint.y = fabs(centerPoint.y-prevPoint.y) < 30 ? prevPoint.y + 60 : 2*centerPoint.y - prevPoint.y;
			} else {
				newPoint.x = fabs(centerPoint.x-prevPoint.x) < 30 ? prevPoint.x + 60 : 2*centerPoint.x - prevPoint.x;
				newPoint.y = prevPoint.y;
			}
			CGFloat screenBottom = self.bounds.origin.y+self.bounds.size.height;
			if ( screenBottom - newPoint.y < 190 )
				newPoint.y = screenBottom - 1`	`	90;
		} else if ( way.nodes.count == 2 ) {
			// create 3rd point 90 degrees from first 2
			OsmNode * n1 = way.nodes[1-prevIndex];
			CGPoint p1 = [self viewPointForLatitude:n1.lat longitude:n1.lon];
			CGPoint delta = { p1.x - prevPoint.x, p1.y - prevPoint.y };
			double len = hypot( delta.x, delta.y );
			if ( len > 100 ) {
				delta.x *= 100/len;
				delta.y *= 100/len;
			}
			OSMPoint centerPoint = { self.center.x, self.center.y };
			OSMPoint np1 = { prevPoint.x - delta.y, prevPoint.y + delta.x };
			OSMPoint np2 = { prevPoint.x + delta.y, prevPoint.y - delta.x };
			if ( DistanceFromPointToPoint(np1, centerPoint) < DistanceFromPointToPoint(np2, centerPoint) )
				newPoint = CGPointMake(np1.x,np1.y);
			else
				newPoint = CGPointMake(np2.x, np2.y);
		} else {
			// create 4th point and beyond following angle of previous 3
			OsmNode * n1 = prevIndex == 0 ? way.nodes[1] : way.nodes[prevIndex-1];
			OsmNode * n2 = prevIndex == 0 ? way.nodes[2] : way.nodes[prevIndex-2];
			CGPoint p1 = [self viewPointForLatitude:n1.lat longitude:n1.lon];
			CGPoint p2 = [self viewPointForLatitude:n2.lat longitude:n2.lon];
			OSMPoint d1 = { prevPoint.x - p1.x, prevPoint.y - p1.y };
			OSMPoint d2 = { p1.x - p2.x, p1.y - p2.y };
			double a1 = atan2( d1.y, d1.x );
			double a2 = atan2( d2.y, d2.x );
			double dist = hypot( d1.x, d1.y );
			// if previous angle was 90 degrees then match length of first leg to make a rectangle
			if ( (way.nodes.count == 3 || way.nodes.count == 4) && fabs(fmod(fabs(a1-a2),M_PI)-M_PI/2) < 0.1 ) {
				dist = hypot(d2.x, d2.y);
			} else if ( dist > 100 )
				dist = 100;
			a1 += a1 - a2;
			newPoint = CGPointMake( prevPoint.x + dist*cos(a1), prevPoint.y + dist*sin(a1) );
		}

		if ( way.nodes.count >= 2 ) {
			OsmNode * start = prevIndex == 0 ? way.nodes.lastObject : way.nodes[0];
			CGPoint s = [self viewPointForLatitude:start.lat longitude:start.lon];
			double d = hypot( s.x - newPoint.x, s.y - newPoint.y );
			if ( d < 3.0 ) {
				// join first to last
				[_editorLayer addNode:start toWay:way atIndex:nextIndex];
				_editorLayer.selectedWay = way;
				_editorLayer.selectedNode = start;
				[self placePushpinAtPoint:s object:start];
				return;
			}
		}
		OsmNode * node2 = [_editorLayer createNodeAtPoint:newPoint];
		[_editorLayer addNode:node2 toWay:way atIndex:nextIndex];
		_editorLayer.selectedWay = way;
		_editorLayer.selectedNode = node2;
		[self placePushpinAtPoint:newPoint object:node2];
	}
}
#endif


-(IBAction)dropPin:(id)sender
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.hidden ) {
		[self flashMessage:NSLocalizedString(@"Editing layer not visible",nil)];
		return;
	}
	if ( _pushpinView ) {

		if ( !CGRectContainsPoint( self.bounds, _pushpinView.arrowPoint ) ) {
			// pushpin is off screen
			[self flashMessage:NSLocalizedString(@"Selected object is off screen",nil)];
		} else if ( _editorLayer.selectedWay && _editorLayer.selectedNode ) {
			// already editing a way so try to extend it
			[self interactiveExtendSelectedWay:nil];
		} else if ( _editorLayer.selectedPrimary == nil && _pushpinView ) {
			// just dropped a pin, so convert it into a way
			[self interactiveExtendSelectedWay:nil];
		} else if ( _editorLayer.selectedWay && _editorLayer.selectedNode == nil ) {
			// add a new node to a way
			[self interactiveExtendSelectedWay:nil];
		} else if ( _editorLayer.selectedPrimary.isNode ) {
			// nothing selected, or just a single node selected, so drop pin
			goto drop_pin;
		}
		
	} else {

drop_pin:
		// drop a new pin

		// remove current selection
		_editorLayer.selectedNode = nil;
		_editorLayer.selectedWay = nil;

		CGRect rc = self.bounds;
		CGPoint point = CGPointMake( rc.origin.x + rc.size.width / 2,
									 rc.origin.y + rc.size.height / 2 );
		[self placePushpinAtPoint:point object:nil];
	}
#endif
}

- (void)setTagsForCurrentObject:(NSDictionary *)tags
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.selectedPrimary == nil ) {
		// create new object
		assert( _pushpinView );
		CGPoint point = _pushpinView.arrowPoint;
		OsmNode * node = [_editorLayer createNodeAtPoint:point];
		[_editorLayer.mapData setTags:tags forObject:node];
		_editorLayer.selectedNode = node;
		// create new pushpin for new object
		[self placePushpinAtPoint:point object:node];
	} else {
		// update current object
		[_editorLayer.mapData setTags:tags forObject:_editorLayer.selectedPrimary];
		[self refreshPushpinText];
	}
	[_editorLayer setNeedsDisplay];
#endif
}

-(void)unblinkObject
{
	[_blinkLayer removeFromSuperlayer];
	_blinkLayer = nil;
	_blinkObject = nil;
	_blinkSegment = -1;
}

-(void)blinkObject:(OsmBaseObject *)object segment:(NSInteger)segment
{
	if ( object == _blinkObject && segment == _blinkSegment )
		return;
	[_blinkLayer removeFromSuperlayer];
	_blinkObject = object;
	_blinkSegment = segment;

	// create a layer for the object
	_blinkLayer = [CAShapeLayer layer];
	CGMutablePathRef path = CGPathCreateMutable();
	if ( object.isNode ) {
		OsmNode * node = (id)object;
		CGPoint center = [self viewPointForLatitude:node.lat longitude:node.lon];
		CGRect rect = CGRectMake(center.x, center.y, 0, 0);
		rect = CGRectInset( rect, -10, -10 );
		CGPathAddEllipseInRect(path, NULL, rect);
	} else if ( object.isWay ) {
		OsmWay * way = (id)object;
		assert( way.nodes.count >= segment+2 );
		OsmNode * n1 = way.nodes[segment];
		OsmNode * n2 = way.nodes[segment+1];
		CGPoint p1 = [self viewPointForLatitude:n1.lat longitude:n1.lon];
		CGPoint p2 = [self viewPointForLatitude:n2.lat longitude:n2.lon];
		CGPathMoveToPoint(path, NULL, p1.x, p1.y);
		CGPathAddLineToPoint(path, NULL, p2.x, p2.y);
	} else {
		assert(NO);
	}
	_blinkLayer.path = path;
	_blinkLayer.fillColor	= NULL;
	_blinkLayer.lineWidth	= 3.0;
	_blinkLayer.frame		= self.bounds;
	_blinkLayer.zPosition	= Z_BLINK;
	_blinkLayer.strokeColor	= NSColor.whiteColor.CGColor;
	_blinkLayer.lineDashPhase = 0.0;
	_blinkLayer.lineDashPattern = @[ @(3), @(3) ];
	[self.layer addSublayer:_blinkLayer];
	CABasicAnimation * dashAnimation = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
	dashAnimation.fromValue	= @(0.0);
	dashAnimation.toValue	= @(10.0);
	dashAnimation.duration	= 0.20;
	dashAnimation.repeatCount = 10000;
	[_blinkLayer addAnimation:dashAnimation forKey:@"linePhase"];
	CGPathRelease(path);
}

-(void)updateAddWayProgress
{
#if !TARGET_OS_IPHONE
	// if adding a way draw connection to mouse
	if ( _editorLayer.addWayInProgress && _editorLayer.selectedWay ) {

		if ( _addWayProgressLayer == nil ) {
			_addWayProgressLayer = [CAShapeLayer layer];
			_addWayProgressLayer.strokeColor = NSColor.brownColor.CGColor;
			_addWayProgressLayer.shadowColor = NSColor.whiteColor.CGColor;
			_addWayProgressLayer.shadowRadius = 5.0;
			_addWayProgressLayer.lineWidth = 3.0;
			_addWayProgressLayer.lineCap = @"round";
			_addWayProgressLayer.frame = self.bounds;
			[self.layer addSublayer:_addWayProgressLayer];
		}
		CGMutablePathRef path = CGPathCreateMutable();
		OsmNode * n = _editorLayer.selectedWay.nodes.lastObject;
		CGPoint start = [self viewPointForLatitude:n.lat longitude:n.lon];
		CGPoint mouse = [self.window mouseLocationOutsideOfEventStream];
		mouse = [self convertPoint:mouse fromView:nil];
		CGPathMoveToPoint( path, NULL, start.x, start.y );
		CGPathAddLineToPoint( path, NULL, mouse.x, mouse.y );
		_addWayProgressLayer.path = path;
		CGPathRelease(path);
		_addWayProgressLayer.hidden = NO;
	} else {
		_addWayProgressLayer.hidden = YES;
	}
#endif
}

-(IBAction)duplicateSelectedObject:(id)sender
{
	if ( _editorLayer.selectedPrimary.isNode ) {
		OsmNode * origNode = (id)_editorLayer.selectedPrimary;
		CGPoint pt = [self viewPointForLatitude:origNode.lat longitude:origNode.lon];
		pt.x += 20;
		pt.y += 20;
		OsmNode * newNode = [_editorLayer createNodeAtPoint:pt];
		[_editorLayer.mapData setTags:origNode.tags forObject:newNode];
		_editorLayer.selectedNode = newNode;
		return;
	}
	if ( _editorLayer.selectedPrimary.isWay ) {
		OsmWay * origWay = (id)_editorLayer.selectedPrimary;
		OsmWay * newWay = nil;
		NSInteger last = origWay.nodes.lastObject == origWay.nodes[0] ? origWay.nodes.count : -1;
		for ( OsmNode * origNode in origWay.nodes ) {
			if ( --last == 0 ) {
				[_editorLayer.mapData addNode:newWay.nodes[0] toWay:newWay atIndex:newWay.nodes.count];
				break;
			}
			CGPoint pt = [self viewPointForLatitude:origNode.lat longitude:origNode.lon];
			pt.x += 20;
			pt.y += 20;
			OsmNode * newNode = [_editorLayer createNodeAtPoint:pt];
			if ( newWay == nil ) {
				newWay = [_editorLayer createWayWithNode:newNode];
			} else {
				[_editorLayer.mapData addNode:newNode toWay:newWay atIndex:newWay.nodes.count];
			}
		}
		[_editorLayer.mapData setTags:origWay.tags forObject:newWay];
		_editorLayer.selectedWay = newWay;
		return;
	}
}

-(BOOL)canConnectTo:(OsmBaseObject *)hit
{
	if ( hit == nil )
		return NO;
	if ( _editorLayer.addNodeInProgress ) {
		return hit.isWay;
	}
	if ( _editorLayer.addWayInProgress ) {
		if ( hit.isWay ) {
			return hit != _editorLayer.selectedWay;
		}
		if ( hit.isNode ) {
			// check if connecting to existing way
			if ( _editorLayer.selectedWay && [_editorLayer.selectedWay.nodes containsObject:hit] && hit != _editorLayer.selectedWay.nodes[0] ) {
				// attempt to connect to ourself at other than first position (forming a loop)
				return NO;
			}
			return YES;
		}
	}
	if ( _grabbedObject && _grabbedObjectDragged && _grabbedObject.isNode ) {
		if ( hit.isWay ) {
			return hit != _editorLayer.selectedWay;
		}
		if ( hit.isNode )
			return YES;
	}
	return NO;
}

-(void)setCursorForPoint:(CGPoint)point
{
#if !TARGET_OS_IPHONE
	BOOL isFirstResponder = (self == [self.window firstResponder]) && [self.window isKeyWindow];
	if ( !isFirstResponder ) {
		return;
	}

	OsmNode * canGrabNode = [_editorLayer osmHitTestNodeInSelection:point];

	// draw connector to cursor for adding a new way point
	[self updateAddWayProgress];

	// check for hitting existing object
	OsmBaseObject * hit = [_editorLayer osmHitTest:point];
	[_editorLayer osmHighlightObject:hit mousePoint:point];

	if ( canGrabNode ) {
		hit = canGrabNode;
	}

	if ( [self canConnectTo:hit] ) {
		NSInteger segment;
		OsmBaseObject * hit2 = [_editorLayer osmHitTest:point segment:&segment ignoreList:nil];
		[self blinkObject:hit2 segment:segment];
	} else {
		[self unblinkObject];
	}

	if ( _editorLayer.addNodeInProgress || _editorLayer.addWayInProgress ) {
		[[NSCursor crosshairCursor] set];
		return;
	}

	// check for hovering over a node in a previously selected way
	if ( canGrabNode ) {
		// grabbing selected item node
		if ( [NSEvent pressedMouseButtons] & 1 ) {
			[[NSCursor closedHandCursor] set];
		} else {
			[[NSCursor openHandCursor] set];
		}
		return;
	}

	if ( hit ) {
		[[NSCursor pointingHandCursor] set];
	} else {
		[[NSCursor arrowCursor] set];
	}
#endif
}

#pragma mark Mouse movment


- (void)singleClick:(CGPoint)point extendedCommand:(BOOL)extendedCommand
{
	OsmBaseObject * hit = nil;
	_grabbedObject = nil;

	if ( _editorLayer.addNodeInProgress || _editorLayer.addWayInProgress ) {

		// create node/way
		if ( _editorLayer.addNodeInProgress ) {

			// check if connecting to existing way
			NSInteger segment;
			hit = [_editorLayer osmHitTest:point segment:&segment ignoreList:nil];

			// create node
			_editorLayer.addNodeInProgress = NO;
			OsmNode * node = [_editorLayer createNodeAtPoint:point];
			_editorLayer.selectedNode = node;
			_editorLayer.selectedWay = nil;
			_grabbedObject = node;

			if ( hit && hit.isWay ) {
				OsmWay * way = (id)hit;
				[_editorLayer.mapData addNode:node toWay:way atIndex:segment+1];
				_editorLayer.selectedWay = way;
			}

		} else {

			// check if connecting to existing way
			NSInteger segment;
			hit = [_editorLayer osmHitTest:point segment:&segment ignoreList:nil];
			OsmNode * node = nil;
			if ( hit && hit.isNode ) {

				if ( _editorLayer.selectedWay && hit == _editorLayer.selectedWay.nodes.lastObject ) {
					// double clicked final node, so terminate way
					_editorLayer.addWayInProgress = NO;
					_editorLayer.selectedNode = (id)hit;
					_grabbedObject = (id)hit;
					goto checkGrab;
				}
				if ( _editorLayer.selectedWay && [_editorLayer.selectedWay.nodes containsObject:hit] ) {
					if ( hit == _editorLayer.selectedWay.nodes[0] ) {
						// make loop
						node = (id)hit;
						_editorLayer.addWayInProgress = NO;
						_editorLayer.selectedNode = node;
						_grabbedObject = node;
					} else {
						// attempt to connect to ourself at other than first position (forming a loop)
					}
				} else {
					node = (id)hit;
				}
			}
			if ( node == nil ) {
				node = [_editorLayer createNodeAtPoint:point];
			}
			if ( hit && hit.isWay && hit != _editorLayer.selectedWay ) {
				// add node to other way as well
				OsmWay * way = (id)hit;
				[_editorLayer.mapData addNode:node toWay:way atIndex:segment+1];
			}

			// append node to way
			_editorLayer.selectedNode = node;
			if ( _editorLayer.selectedWay == nil ) {
				// first node in way, so create way
				_editorLayer.selectedWay = [_editorLayer createWayWithNode:node];
			} else {
				[_editorLayer.mapData addNode:node toWay:_editorLayer.selectedWay atIndex:_editorLayer.selectedWay.nodes.count];
			}
			_grabbedObject = node;
		}

	} else {

		BOOL isAddedSelection = extendedCommand;

		if ( _editorLayer.selectedWay && !isAddedSelection ) {
			// check for selecting node inside way
			hit = [_editorLayer osmHitTestNodeInSelection:point];
		}
		if ( hit ) {
			_editorLayer.selectedNode = (id)hit;
			[_delegate mapviewSelectionChanged:hit];
			_grabbedObject = (id)hit;

		} else {

			// hit test anything
			hit = [_editorLayer osmHitTest:point];

			if ( isAddedSelection ) {
				if ( hit ) {
					[_editorLayer toggleExtraSelection:hit];
				}
			} else {
				if ( hit ) {
					if ( hit.isNode ) {
						_editorLayer.selectedNode = (id)hit;
						_editorLayer.selectedWay = nil;
						_editorLayer.selectedRelation = nil;
						_grabbedObject = hit;
#if !TARGET_OS_IPHONE
					} else if ( hit == _editorLayer.selectedWay ) {
						_grabbedObject = hit;
#endif
					} else {
						_editorLayer.selectedNode = nil;
						_editorLayer.selectedWay = (id)hit;
						_editorLayer.selectedRelation = nil;
					}
				} else {
					_editorLayer.selectedNode = nil;
					_editorLayer.selectedWay = nil;
					_editorLayer.selectedRelation = nil;
				}
				[_delegate mapviewSelectionChanged:hit];
				[_editorLayer clearExtraSelections];
			}
		}
#if TARGET_OS_IPHONE
		[self removePin];

		if ( _editorLayer.selectedPrimary ) {
			if ( _editorLayer.selectedPrimary.isNode ) {
				// center on node
				OsmNode * node = (id)_editorLayer.selectedPrimary;
				point = [self viewPointForLatitude:node.lat longitude:node.lon];
			} else if ( _editorLayer.selectedPrimary.isWay ) {
				CLLocationCoordinate2D latLon = [self longitudeLatitudeForViewPoint:point];
				OSMPoint pt = { latLon.longitude, latLon.latitude };
				pt = [_editorLayer.selectedWay pointOnWayForPoint:pt];
				point = [self viewPointForLatitude:pt.y longitude:pt.x];
			}
			[self placePushpinAtPoint:point object:_editorLayer.selectedPrimary];
		}
#endif
	}

checkGrab:
	if ( _grabbedObject ) {
		// grabbing selected item node
#if !TARGET_OS_IPHONE
		[[NSCursor closedHandCursor] push];
		[_editorLayer.mapData beginUndoGrouping];
#endif
		_grabbedObjectDragged = NO;
	} else if ( hit ) {
#if !TARGET_OS_IPHONE
		[[NSCursor pointingHandCursor] push];
#endif
	} else {
		// move view
#if !TARGET_OS_IPHONE
		[[NSCursor arrowCursor] push];
#endif
	}
}

- (void)doubleClick:(CGPoint)point
{
#if !TARGET_OS_IPHONE
	OsmBaseObject * selection = [_editorLayer osmHitTestSelection:point];
	if ( selection ) {

		// open tag editor window
		[[NSCursor arrowCursor] set];
		[_delegate doubleClickSelection:selection];

	} else {

		// zoom in on point
		CGRect bounds = self.bounds;
		CGPoint center = CGPointMake(bounds.origin.x + bounds.size.width/2, bounds.origin.y + bounds.size.height/2);
		point.x = center.x - point.x;
		point.y = center.y - point.y;
		point.y = -point.y;
		[self adjustOriginBy:point];
		[self adjustZoomBy:2.0];
	}
#endif
}

#if TARGET_OS_IPHONE

- (void)panInertia:(NSTimer *)timer
{
	void (^inertiaBlock)() = (void (^)())timer.userInfo;
	inertiaBlock();
}
- (void)handlePanGesture:(UIPanGestureRecognizer *)pan
{
	_userOverrodeLocationPosition = YES;

	if ( pan.state == UIGestureRecognizerStateBegan ) {
		[_inertiaTimer invalidate];
//		DLog( @"start pan" );
    } else if ( pan.state == UIGestureRecognizerStateChanged ) {
//		DLog( @"move pan" );
		CGPoint translation = [pan translationInView:self];
		translation.y = -translation.y;
//		DLog(@"pan %d trans = %f,%f", pan.state, translation.x, translation.y);
		[self adjustOriginBy:translation];
		[pan setTranslation:CGPointMake(0,0) inView:self];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled ) {	// cancelled occurs when we throw an error dialog
//		DLog( @"finish pan" );
		CGPoint velocity = [pan velocityInView:self];
//		DLog(@"pan %d vel = %f,%f",pan.state,velocity.x,velocity.y);
		NSDate * startTime = [NSDate date];
		double interval = 1.0/60.0;
		double duration = 0.5;
		void (^inertiaBlock)() = ^{
			double deltaTime = [[NSDate date] timeIntervalSinceDate:startTime];
			if ( deltaTime >= duration ) {
				[_inertiaTimer invalidate];
			} else {
				CGPoint translation;
				translation.x =  velocity.x / 60 * (duration - deltaTime)/duration;
				translation.y = -velocity.y / 60 * (duration - deltaTime)/duration;
				[self adjustOriginBy:translation];
			}
		};
		_inertiaTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(panInertia:) userInfo:inertiaBlock repeats:YES];
	} else if ( pan.state == UIGestureRecognizerStateFailed ) {
		DLog( @"pan gesture failed" );
	} else {
		DLog( @"pan gesture %d", (int)pan.state);
	}
}
- (void)handlePinchGesture:(UIPinchGestureRecognizer *)pinch
{
#if 0 && DEBUG
	if ( pinch.state == UIGestureRecognizerStateEnded ) {
		OSMRect box = [self viewportLongitudeLatitude];
		[_notes updateForRegion:box completion:^{
			DLog(@"%ld notes", (long)_notes.list.count);
		}];
	}
#endif

	if ( pinch.state != UIGestureRecognizerStateChanged )
		return;

	_userOverrodeLocationZoom = YES;

	[_inertiaTimer invalidate];

	CGPoint point = [pinch locationInView:self];
	CGFloat scale = pinch.scale;

	CGRect bounds = self.bounds;
	CGPoint center = CGPointMake(bounds.origin.x + bounds.size.width/2, bounds.origin.y + bounds.size.height/2);
	point.x = center.x - point.x;
	point.y = center.y - point.y;
	point.y = -point.y;
	point.x *= scale - 1;
	point.y *= scale - 1;

	[CATransaction begin];
	[CATransaction setAnimationDuration:0.0];

	[self adjustOriginBy:point];
	[self adjustZoomBy:scale];

	[CATransaction commit];

	[pinch setScale:1.0];
}
- (IBAction)handleTapGesture:(UITapGestureRecognizer *)tap
{
	if ( tap.state == UIGestureRecognizerStateEnded ) {
		CGPoint point = [tap locationInView:self];
		BOOL extendedCommand = NO;
		if ( tap.numberOfTapsRequired == 1 ) {
			[self singleClick:point extendedCommand:extendedCommand];
		} else if ( tap.numberOfTapsRequired == 2 ) {
			[self doubleClick:point];
		}
	}
}

- (void)updateSpeechBalloonPosition
{
}

#else

- (void)mouseMoved:(NSEvent *)theEvent
{
	CGPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	
	if ( !NSPointInRect(point, self.bounds) ) {
		// not in our view
		[[NSCursor arrowCursor] set];
		[[self nextResponder] mouseMoved:theEvent];
		return;
	}

	// update longitude/latitude property
	[self setMousePoint:point];

	[self setCursorForPoint:point];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	CGPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];

	if ( !NSPointInRect(point, self.bounds) ) {
		[[self nextResponder] mouseMoved:theEvent];
		return;
	}

	CGPoint delta = CGPointMake( point.x-_lastMouseDragPos.x, point.y-_lastMouseDragPos.y);
	_lastMouseDragPos = point;

	delta.y = -delta.y;

	if ( _grabbedObject ) {
		if ( _grabbedObject.isNode ) {
			[_editorLayer adjustNode:(OsmNode *)_grabbedObject byDistance:delta];
		} else {
			OsmWay * w = (id)_grabbedObject;
			NSInteger last = w.nodes.lastObject == w.nodes[0] ? w.nodes.count : 0;
			for ( OsmNode * n in w.nodes ) {
				if ( --last == 0 )
					break;
				[_editorLayer adjustNode:n byDistance:delta];
			}
		}
		_grabbedObjectDragged = YES;

		NSInteger segment = 0;
		OsmBaseObject * hit = [_editorLayer osmHitTest:point segment:&segment ignoreList:@[_grabbedObject]];
		if ( [self canConnectTo:hit] ) {
			[self blinkObject:hit segment:segment];
		} else {
			[self unblinkObject];
		}

	} else {
		[self adjustOriginBy:delta];
	}
}

- (void)mouseDown:(NSEvent *)event
{
	CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];

	if ( !NSPointInRect(point, self.bounds) ) {
		[[self nextResponder] mouseMoved:event];
		return;
	}

	_lastMouseDragPos = point;

	if ( [event clickCount] == 1 ) {
		BOOL extendedCommand = ([event modifierFlags] & NSCommandKeyMask) != 0;
		[self singleClick:point extendedCommand:extendedCommand];
	} else if ( [event clickCount] == 2 ) {
		[self doubleClick:point];
	}
}

- (void)mouseUp:(NSEvent *)theEvent
{
	CGPoint point = [self convertPoint:[theEvent locationInWindow] fromView:nil];

	if ( !NSPointInRect(point, self.bounds) ) {
		[[self nextResponder] mouseMoved:theEvent];
		return;
	}

	if ( _grabbedObject ) {
		[_editorLayer.mapData endUndoGrouping];
		if ( _grabbedObjectDragged ) {
			// check if we dragged node onto another node/line and need to merge/connect
			NSInteger segment;
			OsmBaseObject * hit = [_editorLayer osmHitTest:point segment:&segment ignoreList:@[_grabbedObject]];
			if ( [self canConnectTo:hit] ) {
				
			}
		};

		_grabbedObject = nil;
	}
	[NSCursor pop];

	[self setCursorForPoint:point];
}


-(void)scrollWheel:(NSEvent *)event
{
	[NSAnimationContext beginGrouping];
	[[NSAnimationContext currentContext] setDuration:0.0];

	// if command key is held down when momentum phase begins then preserve it
	if ( [event momentumPhase] == NSEventPhaseBegan ) {
		_isZoomScroll = ([event modifierFlags] & NSCommandKeyMask) != 0;
	} else if ( _isZoomScroll && [event momentumPhase] == NSEventPhaseEnded ) {
		_isZoomScroll = NO;
	}

	if ( _isZoomScroll || ([event modifierFlags] & NSCommandKeyMask) ) {
		// zoom instead of scroll
		CGFloat dy = event.scrollingDeltaY;
		if ( ! event.hasPreciseScrollingDeltas )
			dy *= 10;
		CGFloat ratio = 1000.0 / (dy + 1000.0);

		{
			// center zoom on mouse position
			CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
			CGRect bounds = self.bounds;
			CGPoint center = CGPointMake(bounds.origin.x + bounds.size.width/2, bounds.origin.y + bounds.size.height/2);
			CGPoint delta = { center.x - point.x, center.y - point.y };
			delta.y = -delta.y;
			delta.x *= ratio - 1;
			delta.y *= ratio - 1;
			[self adjustOriginBy:delta];
		}
		[self adjustZoomBy:ratio];
	} else {
		// scroll
		CGPoint delta = CGPointMake( event.scrollingDeltaX, -event.scrollingDeltaY );
		if ( ! event.hasPreciseScrollingDeltas ) {
			delta = CGPointMake(delta.x * 10, delta.y * 10);
		}
		[self adjustOriginBy:delta];
	}

	CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	[self setCursorForPoint:point];

	[NSAnimationContext endGrouping];
}

- (void)magnifyWithEvent:(NSEvent *)event
{
	CGFloat mag = [event magnification];
	[self adjustZoomBy:1.0+mag];

	CGPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	[self setCursorForPoint:point];
}

#if 0
-(void)rotateWithEvent:(NSEvent *)event
{
	CGFloat angle = [event rotation];
	[self rotateByAngle:angle];

	OSMPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
	[self setCursorForPoint:point];
}
#endif
#endif

@end
