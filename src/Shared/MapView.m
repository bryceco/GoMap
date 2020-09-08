//
//  MapView.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <SafariServices/SafariServices.h>

#import "iosapi.h"

#import "AerialList.h"
#import "BingMapsGeometry.h"
#import "Buildings3DView.h"
#import "DisplayLink.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "FpsLabel.h"
#import "GpxLayer.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "MyApplication.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "OsmMapData+Edit.h"
#import "OsmMember.h"
#import "RulerView.h"
#import "SpeechBalloonView.h"
#import "TapAndDragGesture.h"
#import "TurnRestrictController.h"
#import "VoiceAnnouncement.h"

#if TARGET_OS_IPHONE
#import "DDXML.h"
#import "LocationBallLayer.h"
#import "MainViewController.h"
#import "PushPinView.h"
#else
#import "HtmlErrorWindow.h"
#endif



static const CGFloat Z_AERIAL			= -100;
static const CGFloat Z_NONAME           = -99;
static const CGFloat Z_MAPNIK			= -98;
static const CGFloat Z_LOCATOR			= -50;
static const CGFloat Z_GPSTRACE			= -40;
#if USE_SCENEKIT
static const CGFloat Z_BUILDINGS3D		= -30;
#endif
static const CGFloat Z_EDITOR			= -20;
static const CGFloat Z_GPX				= -15;
//static const CGFloat Z_BUILDINGS		= -18;
static const CGFloat Z_ROTATEGRAPHIC	= -3;
//static const CGFloat Z_BING_LOGO		= 2;
static const CGFloat Z_BLINK			= 4;
static const CGFloat Z_CROSSHAIRS		= 5;
static const CGFloat Z_BALL				= 6;
static const CGFloat Z_TOOLBAR			= 90;
static const CGFloat Z_PUSHPIN			= 105;
static const CGFloat Z_FLASH			= 110;


@implementation MapLocation
@end


@interface MapView ()
@property (strong,nonatomic) IBOutlet UIVisualEffectView	*	statusBarBackground;
@end

@implementation MapView

@synthesize aerialLayer			= _aerialLayer;
@synthesize mapnikLayer			= _mapnikLayer;
@synthesize editorLayer			= _editorLayer;
@synthesize gpsState			= _gpsState;
@synthesize pushpinView			= _pushpinView;
@synthesize viewState			= _viewState;
@synthesize screenFromMapTransform	= _screenFromMapTransform;

const CGFloat kEditControlCornerRadius = 4;

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
		self.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1];

		_screenFromMapTransform = OSMTransformIdentity();
		_birdsEyeDistance = 1000.0;

		[[NSUserDefaults standardUserDefaults] registerDefaults:@{
																  @"view.scale"				: @(nan("")),
																  @"view.latitude"			: @(nan("")),
																  @"view.longitude"			: @(nan("")),
																  @"mapViewState"			: @(MAPVIEW_EDITORAERIAL),
																  @"mapViewEnableBirdsEye"	: @(NO),
																  @"mapViewEnableRotation"	: @(YES),
																  @"automaticCacheManagement": @(YES)
																  }];

		// this option needs to be set before the editor is initialized
		self.enableAutomaticCacheManagement	= [[NSUserDefaults standardUserDefaults] boolForKey:@"automaticCacheManagement"];

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
        
        _noNameLayer = [[MercatorTileLayer alloc] initWithMapView:self];
        _noNameLayer.zPosition = Z_NONAME;
        _noNameLayer.aerialService = [AerialService noName];
        _noNameLayer.hidden = YES;
        [bg addObject:_noNameLayer];

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

		_gpxLayer = [[GpxLayer alloc] initWithMapView:self];
		_gpxLayer.zPosition = Z_GPX;
		_gpxLayer.hidden = YES;
		[bg addObject:_gpxLayer];

#if USE_SCENEKIT
		_buildings3D = [[Buildings3DView alloc] initWithFrame:self.bounds];
		_buildings3D.mapView = self;
		[self addSubview:_buildings3D];
		_buildings3D.layer.zPosition = Z_BUILDINGS3D;
#endif
		
		_backgroundLayers = [NSArray arrayWithArray:bg];
		for ( CALayer * layer in _backgroundLayers ) {
			[self.layer addSublayer:layer];
		}

		if ( YES ) {
			// implement crosshairs
			_crossHairs = [CAShapeLayer new];
			UIBezierPath * path = [UIBezierPath bezierPath];
			CGFloat radius = 12;
			[path moveToPoint:CGPointMake(-radius, 0)];
			[path addLineToPoint:CGPointMake(radius, 0)];
			[path moveToPoint:CGPointMake(0, -radius)];
			[path addLineToPoint:CGPointMake(0, radius)];
			_crossHairs.anchorPoint	= CGPointMake(0.5, 0.5);
			_crossHairs.path		= path.CGPath;
			_crossHairs.strokeColor = [UIColor colorWithRed:1.0 green:1.0 blue:0.5 alpha:1.0].CGColor;
			_crossHairs.bounds		= CGRectMake(-radius, -radius, 2*radius, 2*radius);
			_crossHairs.lineWidth	= 2.0;
			_crossHairs.zPosition	= Z_CROSSHAIRS;

			path = [UIBezierPath new];
			CGFloat shadowWidth = 2.0;
			UIBezierPath * p1 = [UIBezierPath bezierPathWithRect:CGRectMake(-(radius+shadowWidth-1), -shadowWidth, 2*(radius+shadowWidth-1), 2*shadowWidth)];
			UIBezierPath * p2 = [UIBezierPath bezierPathWithRect:CGRectMake(-shadowWidth, -(radius+shadowWidth-1), 2*shadowWidth, 2*(radius+shadowWidth-1))];
			[path appendPath:p1];
			[path appendPath:p2];
			_crossHairs.shadowColor		= UIColor.blackColor.CGColor;
			_crossHairs.shadowOpacity	= 1.0;
			_crossHairs.shadowPath		= path.CGPath;
			_crossHairs.shadowRadius	= 0;
			_crossHairs.shadowOffset	= CGSizeMake(0,0);

			_crossHairs.position = CGRectCenter( self.bounds );
			[self.layer addSublayer:_crossHairs];
		}

#if 0
		_voiceAnnouncement = [VoiceAnnouncement new];
		_voiceAnnouncement.mapView = self;
		_voiceAnnouncement.radius = 30;	// meters
#endif

#if 0	// no evidence this help things
		for ( CALayer * layer in _backgroundLayers ) {
			layer.drawsAsynchronously = YES;
		}
		_rulerLayer.drawsAsynchronously	= YES;
#endif

		_editorLayer.mapData.undoCommentCallback = ^(BOOL undo,NSDictionary * context) {

			if ( self.silentUndo )
				return;

			NSString 	 * title 	= undo ? NSLocalizedString(@"Undo",nil) : NSLocalizedString(@"Redo",nil);
			NSString 	 * action 	= context[@"comment"];
			NSData 		 * location = context[@"location"];

			if ( location.length == sizeof(OSMTransform) ) {
				const OSMTransform * transform = (OSMTransform *)[location bytes];
				self.screenFromMapTransform = *transform;
			}

			_editorLayer.selectedRelation 	= context[ @"selectedRelation" ];
			_editorLayer.selectedWay 		= context[ @"selectedWay" ];
			_editorLayer.selectedNode		= context[ @"selectedNode" ];
			if ( _editorLayer.selectedNode.deleted )
				_editorLayer.selectedNode = nil;

#if TARGET_OS_IPHONE
			NSString * pushpin = context[@"pushpin"];
			if ( pushpin && _editorLayer.selectedPrimary ) {
				// since we don't record the pushpin location until after a drag has begun we need to re-center on the object:
				CGPoint pt = CGPointFromString(pushpin);
				CLLocationCoordinate2D loc = [self longitudeLatitudeForScreenPoint:pt birdsEye:YES];
				OSMPoint pos = [_editorLayer.selectedPrimary pointOnObjectForPoint:OSMPointMake(loc.longitude, loc.latitude)];
				pt = [self screenPointForLatitude:pos.y longitude:pos.x birdsEye:YES];
				// place pushpin
				[self placePushpinAtPoint:pt object:_editorLayer.selectedPrimary];
			} else {
				[self removePin];
			}
#endif
			NSString * message = [NSString stringWithFormat:@"%@ %@", title, action];
			[self flashMessage:message];
		};
	}
	return self;
}

-(void)awakeFromNib
{
	[super awakeFromNib];

#if TARGET_OS_IPHONE
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:UIApplicationWillResignActiveNotification object:NULL];
#else
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:[NSApplication sharedApplication]];
#endif

	_userInstructionLabel.layer.cornerRadius	= 5;
	_userInstructionLabel.layer.masksToBounds	= YES;
	_userInstructionLabel.backgroundColor		= [UIColor colorWithWhite:0.0 alpha:0.3];
	_userInstructionLabel.textColor				= UIColor.whiteColor;
	_userInstructionLabel.hidden = YES;

#if TARGET_OS_IPHONE
	_progressIndicator.color = NSColor.greenColor;
#endif

	_locationManager = [[CLLocationManager alloc] init];
	_locationManager.delegate = self;
#if TARGET_OS_IPHONE
	_locationManager.pausesLocationUpdatesAutomatically = NO;
	_locationManager.allowsBackgroundLocationUpdates = self.gpsInBackground && self.enableGpxLogging;
	if (@available(iOS 11.0, *)) {
		_locationManager.showsBackgroundLocationIndicator = YES;
	}
	_locationManager.activityType = CLActivityTypeOther;
#endif

	_rulerView.mapView = self;
//	_rulerView.layer.zPosition = Z_RULER;

	// set up action button
	_editControl.hidden = YES;
	_editControl.selected = NO;
	_editControl.selectedSegmentIndex = UISegmentedControlNoSegment;
	[_editControl setTitleTextAttributes:@{ NSFontAttributeName : [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline] }
									   forState:UIControlStateNormal];
	_editControl.layer.zPosition = Z_TOOLBAR;
    _editControl.layer.cornerRadius = kEditControlCornerRadius;

	// long press for selecting from multiple objects
	UILongPressGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
	longPress.delegate = self;
	[self addGestureRecognizer:longPress];

	// two-finger rotation
	UIRotationGestureRecognizer * rotationGesture = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotationGesture:)];
	rotationGesture.delegate = self;
	[self addGestureRecognizer:rotationGesture];

	// long-press on + for adding nodes via taps
	_addNodeButtonLongPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(addNodeButtonLongPressHandler:)];
	_addNodeButtonLongPressGestureRecognizer.minimumPressDuration = 0.001;
	_addNodeButtonLongPressGestureRecognizer.delegate = self;
	[self.addNodeButton addGestureRecognizer:_addNodeButtonLongPressGestureRecognizer];

	// pan gesture to recognize mouse-wheel scrolling (zoom)
	if (@available(iOS 13.4, *)) {
		UIPanGestureRecognizer * scrollWheelGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleScrollWheelGesture:)];
		scrollWheelGesture.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
		scrollWheelGesture.maximumNumberOfTouches = 0;
		[self addGestureRecognizer:scrollWheelGesture];
	}

	_notesDatabase			= [OsmNotesDatabase new];
	_notesDatabase.mapData	= _editorLayer.mapData;
	_notesViewDict			= [NSMutableDictionary new];

	// make help button have rounded corners
	_helpButton.layer.cornerRadius = _helpButton.bounds.size.width / 2;

	// observe changes to aerial visibility so we can show/hide bing logo
	[_aerialLayer addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionNew context:NULL];
	[_editorLayer addObserver:self forKeyPath:@"hidden" options:NSKeyValueObservingOptionNew context:NULL];
#if !TARGET_OS_IPHONE
	[self.window setAcceptsMouseMovedEvents:YES];
#endif

	_editorLayer.whiteText = !_aerialLayer.hidden;

	// center button
	_centerOnGPSButton.backgroundColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.5];
	_centerOnGPSButton.layer.cornerRadius = 5;
	_centerOnGPSButton.layer.borderWidth = 1.0;
	_centerOnGPSButton.layer.borderColor = UIColor.blueColor.CGColor;
	_centerOnGPSButton.hidden = YES;

	// compass button
	self.compassButton.contentMode = UIViewContentModeCenter;
	[self.compassButton setImage:nil forState:UIControlStateNormal];
	self.compassButton.backgroundColor = UIColor.whiteColor;
	[self compassOnLayer:self.compassButton.layer withRadius:self.compassButton.bounds.size.width/2];

	// error message label
	_flashLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
	_flashLabel.layer.cornerRadius = 5;
	_flashLabel.layer.masksToBounds = YES;
	_flashLabel.layer.zPosition = Z_FLASH;
	_flashLabel.hidden = YES;

#if 0
	// Support zoom via tap and drag
	_tapAndDragGesture = [[TapAndDragGesture alloc] initWithTarget:self action:@selector(handleTapAndDragGesture:)];
	_tapAndDragGesture.delegate = self;
	[self addGestureRecognizer:_tapAndDragGesture];
#endif

	// these need to be loaded late because assigning to them changes the view
	self.viewState				= (MapViewState)	[[NSUserDefaults standardUserDefaults] integerForKey:@"mapViewState"];
	self.viewOverlayMask		= (ViewOverlayMask) [[NSUserDefaults standardUserDefaults] integerForKey:@"mapViewOverlays"];

	self.enableRotation			= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableRotation"];
	self.enableBirdsEye			= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableBirdsEye"];
	self.enableUnnamedRoadHalo	= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableUnnamedRoadHalo"];
	self.enableGpxLogging		= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableBreadCrumb"];
	self.enableTurnRestriction	= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableTurnRestriction"];

	_countryCodeForLocation = [[NSUserDefaults standardUserDefaults] objectForKey:@"countryCodeForLocation"];

	[self updateAerialAttributionButton];
}

-(void)viewDidAppear
{
	// get current location
	double scale		= [[NSUserDefaults standardUserDefaults] doubleForKey:@"view.scale"];
	double latitude		= [[NSUserDefaults standardUserDefaults] doubleForKey:@"view.latitude"];
	double longitude	= [[NSUserDefaults standardUserDefaults] doubleForKey:@"view.longitude"];

	if ( !isnan(latitude) && !isnan(longitude) && !isnan(scale) ) {
		[self setTransformForLatitude:latitude longitude:longitude scale:scale];
	} else {
		OSMRect rc = OSMRectFromCGRect( self.layer.bounds );
		self.screenFromMapTransform = OSMTransformMakeTranslation( rc.origin.x+rc.size.width/2 - 128, rc.origin.y+rc.size.height/2 - 128);
		// turn on GPS which will move us to current location
		[self.mainViewController setGpsState:GPS_STATE_LOCATION];
	}

	// get notes
	[self updateNotesFromServerWithDelay:0];
}

-(void)compassOnLayer:(CALayer *)layer withRadius:(CGFloat)radius
{
	CGFloat needleWidth = round(radius/5);
	layer.bounds = CGRectMake(0, 0, 2*radius, 2*radius);
	layer.cornerRadius = radius;
	{
		CAShapeLayer * north = [CAShapeLayer new];
		UIBezierPath * path = [UIBezierPath bezierPath];
		[path moveToPoint:CGPointMake(-needleWidth,0)];
		[path addLineToPoint:CGPointMake(needleWidth,0)];
		[path addLineToPoint:CGPointMake(0,-round(radius*0.9))];
		[path closePath];
		north.path = path.CGPath;
		north.fillColor = UIColor.systemRedColor.CGColor;
		north.position = CGPointMake(radius, radius);
		[layer addSublayer:north];
	}
	{
		CAShapeLayer * south = [CAShapeLayer new];
		UIBezierPath * path = [UIBezierPath bezierPath];
		[path moveToPoint:CGPointMake(-needleWidth,0)];
		[path addLineToPoint:CGPointMake(needleWidth,0)];
		[path addLineToPoint:CGPointMake(0,round(radius*0.9))];
		[path closePath];
		south.path = path.CGPath;
		south.fillColor = UIColor.lightGrayColor.CGColor;
		south.position = CGPointMake(radius, radius);
		[layer addSublayer:south];
	}
	{
		CALayer * pivot = [CALayer new];
		pivot.bounds = CGRectMake(radius-needleWidth/2, radius-needleWidth/2, needleWidth, needleWidth);
		pivot.backgroundColor = UIColor.whiteColor.CGColor;
		pivot.borderColor = UIColor.blackColor.CGColor;
		pivot.cornerRadius = needleWidth/2;
		pivot.position = CGPointMake(radius, radius);
		[layer addSublayer:pivot];
	}
}
-(BOOL)automatedFramerateTestActive
{
	NSString * NAME = @"autoScroll";
	DisplayLink * displayLink = [DisplayLink shared];
	return [displayLink hasName:NAME];
}
-(void)setAutomatedFramerateTestActive:(BOOL)enable
{
	NSString * NAME = @"autoScroll";
	DisplayLink * displayLink = [DisplayLink shared];

	if ( enable == [displayLink hasName:NAME] ) {
		// nothing to do
	} else if ( enable ) {
		// automaatically scroll view for frame rate testing
		self.fpsLabel.showFPS = YES;

		// this set's the starting center point
		const OSMPoint startLatLon = { -122.205831, 47.675024 };
		const double startZoom = 17.302591;
		[self setTransformForLatitude:startLatLon.y longitude:startLatLon.x zoom:startZoom];

		// sets the size of the circle
		const double radius = 100;
		const CGFloat startAngle = 1.5 * M_PI;
		const CGFloat rpm = 2.0;
		const CGFloat zoomTotal = 1.1; // 10% larger
		const CGFloat zoomDelta = pow(zoomTotal,1/60.0);

		__block CGFloat angle = startAngle;
		__block CFTimeInterval prevTime = CACurrentMediaTime();
		__weak MapView * weakSelf = self;

		[displayLink addName:NAME block:^{
			CFTimeInterval time = CACurrentMediaTime();
			CFTimeInterval delta = time - prevTime;
			CGFloat newAngle = angle + (2*M_PI)/rpm * delta;	// angle change depends on framerate to maintain 2/RPM

			if ( angle < startAngle && newAngle >= startAngle ) {
				// reset to start position
				[self setTransformForLatitude:startLatLon.y longitude:startLatLon.x zoom:startZoom];
				angle = startAngle;
			} else {
				// move along circle
				CGFloat x1 = cos(angle);
				CGFloat y1 = sin(angle);
				CGFloat x2 = cos(newAngle);
				CGFloat y2 = sin(newAngle);
				CGFloat dx = (x2 - x1) * radius;
				CGFloat dy = (y2 - y1) * radius;

				[weakSelf adjustOriginBy:CGPointMake(dx,dy)];
				double zoomRatio = dy >= 0 ? zoomDelta : 1/zoomDelta;
				[weakSelf adjustZoomBy:zoomRatio aroundScreenPoint:_crossHairs.position];
				angle = fmod( newAngle, 2*M_PI );
			}
			prevTime = time;
		}];
	} else {
		self.fpsLabel.showFPS = NO;
		[displayLink removeName:NAME];
	}
}

- (BOOL)acceptsFirstResponder
{
	return YES;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( object == _aerialLayer && [keyPath isEqualToString:@"hidden"] ) {
		BOOL hidden = [[change valueForKey:NSKeyValueChangeNewKey] boolValue];
		_aerialServiceLogo.hidden = hidden;
	} else if ( object == _editorLayer && [keyPath isEqualToString:@"hidden"] ) {
		BOOL hidden = [[change valueForKey:NSKeyValueChangeNewKey] boolValue];
		if ( hidden ) {
			_editorLayer.selectedNode = nil;
			_editorLayer.selectedWay = nil;
			_editorLayer.selectedRelation = nil;
#if TARGET_OS_IPHONE
			[self removePin];
#endif
		}
	} else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

-(void)save
{
	// save defaults first
	OSMPoint center = OSMPointFromCGPoint( self.crossHairs.position );
	center = [self mapPointFromScreenPoint:center birdsEye:NO];
	center = LongitudeLatitudeFromMapPoint( center );
	double scale = OSMTransformScaleX(self.screenFromMapTransform);
#if 0 && DEBUG
	assert( scale > 1.0 );
#endif
	[[NSUserDefaults standardUserDefaults] setDouble:scale					forKey:@"view.scale"];
	[[NSUserDefaults standardUserDefaults] setDouble:center.y				forKey:@"view.latitude"];
	[[NSUserDefaults standardUserDefaults] setDouble:center.x				forKey:@"view.longitude"];

	[[NSUserDefaults standardUserDefaults] setInteger:self.viewState		forKey:@"mapViewState"];
	[[NSUserDefaults standardUserDefaults] setInteger:self.viewOverlayMask	forKey:@"mapViewOverlays"];

	[[NSUserDefaults standardUserDefaults] setBool:self.enableRotation			forKey:@"mapViewEnableRotation"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableBirdsEye			forKey:@"mapViewEnableBirdsEye"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableUnnamedRoadHalo	forKey:@"mapViewEnableUnnamedRoadHalo"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableGpxLogging		forKey:@"mapViewEnableBreadCrumb"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableTurnRestriction	forKey:@"mapViewEnableTurnRestriction"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableAutomaticCacheManagement	forKey:@"automaticCacheManagement"];

	[[NSUserDefaults standardUserDefaults] setObject:_countryCodeForLocation 	forKey:@"countryCodeForLocation"];

	[[NSUserDefaults standardUserDefaults] synchronize];

	[self.customAerials save];
	[self.gpxLayer saveActiveTrack];

	// then save data
	[_editorLayer save];
}
-(void)applicationWillTerminate :(NSNotification *)notification
{
	[_voiceAnnouncement removeAll];
	[self save];
}

-(void)layoutSubviews
{
	[super layoutSubviews];

	CGRect bounds = self.bounds;

	// update bounds of layers
	for ( CALayer * layer in _backgroundLayers ) {
		layer.frame = bounds;
		layer.bounds = bounds;
	}
	_buildings3D.frame = bounds;

	_crossHairs.position = CGRectCenter( bounds );

	_statusBarBackground.hidden = [UIApplication sharedApplication].statusBarHidden;
}

-(void)setBounds:(CGRect)bounds
{
	// adjust bounds so we're always centered on 0,0
	bounds = CGRectMake( -bounds.size.width/2, -bounds.size.height/2, bounds.size.width, bounds.size.height );
	[super setBounds:bounds];
}

#pragma mark Utility

-(BOOL)isFlipped
{
	return YES;
}

-(void)updateAerialAttributionButton
{
	AerialService * service = self.aerialLayer.aerialService;
	_aerialServiceLogo.hidden = self.aerialLayer.hidden || (service.attributionString.length == 0 && service.attributionIcon == nil);
	if ( !_aerialServiceLogo.hidden ) {
        // For Bing maps, the attribution icon is part of the app's assets and already has the desired size,
        // so there's no need to scale it.
        if (!service.isBingAerial) {
            [service scaleAttributionIconToHeight:_aerialServiceLogo.frame.size.height];
        }
		
		[_aerialServiceLogo setImage:service.attributionIcon forState:UIControlStateNormal];
		[_aerialServiceLogo setTitle:service.attributionString forState:UIControlStateNormal];
	}
}

-(void)showAlert:(NSString *)title message:(NSString *)message
{
	UIAlertController * alertError = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
	[self.mainViewController presentViewController:alertError animated:YES completion:nil];
}

-(NSAttributedString *)htmlAsAttributedString:(NSString *)html textColor:(UIColor *)textColor backgroundColor:(UIColor *)backColor
{
	if ( [html hasPrefix:@"<"] ) {
		NSDictionary<NSAttributedStringDocumentReadingOptionKey,id> * d1 = @{
			NSDocumentTypeDocumentAttribute 		:	NSHTMLTextDocumentType,
			NSCharacterEncodingDocumentAttribute	: 	@(NSUTF8StringEncoding)
		};
		NSAttributedString * attrText = [[NSAttributedString alloc] initWithData:[html dataUsingEncoding:NSUTF8StringEncoding]
																		 options:d1
															  documentAttributes:NULL
																		   error:NULL];
		if ( attrText ) {
			NSMutableAttributedString * s = [[NSMutableAttributedString alloc] initWithAttributedString:attrText];
			// change text color
			[s addAttribute:NSForegroundColorAttributeName value:textColor range:NSMakeRange(0, s.length)];
			[s addAttribute:NSBackgroundColorAttributeName value:backColor range:NSMakeRange(0, s.length)];
			// center align
			NSMutableParagraphStyle * paragraphStyle = [NSMutableParagraphStyle new];
			paragraphStyle.alignment = NSTextAlignmentCenter;
			[s addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0,s.length)];

			return s;
		}
	}
	return nil;
}
-(void)flashMessage:(NSString *)message duration:(NSTimeInterval)duration
{
#if TARGET_OS_IPHONE
	const CGFloat MAX_ALPHA = 0.8;

	NSAttributedString * attrText = [self htmlAsAttributedString:message textColor:UIColor.whiteColor backgroundColor:UIColor.blackColor];
	if ( attrText.length > 0 ) {
		_flashLabel.attributedText = attrText;
	} else {
		_flashLabel.text = message;
	}

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
		[UIView animateWithDuration:0.35 animations:^{
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
		NSError * underError = [[error userInfo] objectForKey:@"NSUnderlyingError"];
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
			NSAttributedString * attrText = [self htmlAsAttributedString:text textColor:UIColor.blackColor backgroundColor:UIColor.whiteColor];
			UIAlertController * alertError = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
			if ( attrText ) {
				[alertError setValue:attrText forKey:@"attributedMessage"];
			}
			[alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			if ( ignoreButton ) {
				[alertError addAction:[UIAlertAction actionWithTitle:ignoreButton style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
					// ignore network errors for a while
					_ignoreNetworkErrorsUntilDate = [[NSDate date] dateByAddingTimeInterval:5*60.0];
				}]];
			}
			[self.mainViewController presentViewController:alertError animated:YES completion:nil];
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


-(void)askToRate:(NSInteger)uploadCount
{
	double countLog10 = log10(uploadCount);
	if ( uploadCount > 1 && countLog10 == floor(countLog10) ) {
		NSString * title = [NSString stringWithFormat:NSLocalizedString(@"You've uploaded %ld changesets with this version of Go Map!!\n\nRate this app?",nil), (long)uploadCount];
        UIAlertController * alertViewRateApp = [UIAlertController alertControllerWithTitle:title message:NSLocalizedString(@"Rating this app makes it easier for other mappers to discover it and increases the visibility of OpenStreetMap.",nil) preferredStyle:UIAlertControllerStyleAlert];
        [alertViewRateApp addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Maybe later...",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
        [alertViewRateApp addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"I'll do it!",nil)    style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			[self showInAppStore];
        }]];
        [self.mainViewController presentViewController:alertViewRateApp animated:YES completion:nil];
	}
}
-(void)showInAppStore
{
#if 1
	NSString * urlText = [NSString stringWithFormat:@"itms-apps://itunes.apple.com/app/id%@", @592990211];
	NSURL * url = [NSURL URLWithString:urlText];
	[[UIApplication sharedApplication] openURL:url];
#else
	SKStoreProductViewController * spvc = [SKStoreProductViewController new];
	spvc.delegate = self; //self is the view controller to present spvc
	[spvc loadProductWithParameters:@{SKStoreProductParameterITunesItemIdentifier:@592990211}
					completionBlock:^(BOOL result, NSError * error){
						if (result) {
							[self.viewController presentViewController:spvc animated:YES completion:nil];
						}
					}];
#endif
}
-(void)productViewControllerDidFinish:(SKStoreProductViewController*)viewController
{
	[(UIViewController*)viewController.delegate dismissViewControllerAnimated:YES completion:nil];
}

-(IBAction)requestAerialServiceAttribution:(id)sender
{
	AerialService * aerial = self.aerialLayer.aerialService;
	if ( aerial.isBingAerial ) {
		// present bing metadata
		[self.mainViewController performSegueWithIdentifier:@"BingMetadataSegue" sender:self];
	} else if ( aerial.attributionUrl.length > 0 ) {
		// open the attribution url
		NSURL * url = [NSURL URLWithString:aerial.attributionUrl];
		SFSafariViewController * safariViewController = [[SFSafariViewController alloc] initWithURL:url];
		[self.mainViewController presentViewController:safariViewController animated:YES completion:nil];
	}
}

-(void)updateCountryCodeForLocationUsingNominatim
{
	if ( self.viewStateZoomedOut )
		return;

	// if we moved a significant distance then check our country location
	CLLocationCoordinate2D loc = [self longitudeLatitudeForScreenPoint:self.center birdsEye:YES];
	double distance = GreatCircleDistance(OSMPointMake(loc.longitude,loc.latitude), OSMPointMake(_countryCodeLocation.longitude,_countryCodeLocation.latitude));
	if ( distance < 10*1000 ) {
		return;
	}
	_countryCodeLocation = loc;

	NSString * url = [NSString stringWithFormat:@"https://nominatim.openstreetmap.org/reverse?zoom=13&addressdetails=1&format=json&lat=%f&lon=%f",loc.latitude,loc.longitude];
	NSURLSessionDataTask * task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		if ( data.length ) {
			id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
			if ( json ) {
				NSString * code = json[ @"address" ][ @"country_code" ];
				if ( code ) {
					dispatch_async(dispatch_get_main_queue(), ^{
						_countryCodeForLocation = code;
					});
				}
			}
		}
	}];
	[task resume];
}



#pragma mark Rotate object

-(void)startObjectRotation
{
	_isRotateObjectMode	= YES;
	_rotateObjectCenter	= _editorLayer.selectedNode ? _editorLayer.selectedNode.location
						: _editorLayer.selectedWay ? _editorLayer.selectedWay.centerPoint
						: _editorLayer.selectedRelation ? _editorLayer.selectedRelation.centerPoint
						: OSMPointMake(0,0);
	[self removePin];
	_rotateObjectOverlay = [[CAShapeLayer alloc] init];
	CGFloat radiusInner = 70;
	CGFloat radiusOuter = 90;
	CGFloat arrowWidth = 60;
	CGPoint center = [self screenPointForLatitude:_rotateObjectCenter.y longitude:_rotateObjectCenter.x birdsEye:YES];
	UIBezierPath * path = [UIBezierPath bezierPathWithArcCenter:center radius:radiusInner startAngle:M_PI/2 endAngle:M_PI clockwise:NO];
	[path addLineToPoint:CGPointMake(center.x-(radiusOuter+radiusInner)/2+arrowWidth/2,center.y)];
	[path addLineToPoint:CGPointMake(center.x-(radiusOuter+radiusInner)/2, center.y+arrowWidth/sqrt(2.0))];
	[path addLineToPoint:CGPointMake(center.x-(radiusOuter+radiusInner)/2-arrowWidth/2,center.y)];
	[path addArcWithCenter:center radius:radiusOuter startAngle:M_PI endAngle:M_PI/2 clockwise:YES];
	[path closePath];
	_rotateObjectOverlay.path = path.CGPath;
	_rotateObjectOverlay.fillColor = [UIColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:0.4].CGColor;
	_rotateObjectOverlay.zPosition = Z_ROTATEGRAPHIC;
	[self.layer addSublayer:_rotateObjectOverlay];
}
-(void)endObjectRotation
{
	_isRotateObjectMode = NO;
	[_rotateObjectOverlay removeFromSuperlayer];
	_rotateObjectOverlay = nil;
	[self placePushpinForSelection];
	_confirmDrag = NO;
}

#pragma mark View State

-(void)setViewStateZoomedOut:(BOOL)override
{
	[self setViewState:_viewState overlays:_viewOverlayMask zoomedOut:override];
}
-(void)setViewState:(MapViewState)state
{
	[self setViewState:state overlays:_viewOverlayMask zoomedOut:_viewStateZoomedOut];
}
-(void)setViewOverlayMask:(ViewOverlayMask)mask
{
	[self setViewState:_viewState overlays:mask zoomedOut:_viewStateZoomedOut];
}

static inline MapViewState StateFor(MapViewState state, BOOL override)
{
	if ( override && state == MAPVIEW_EDITOR )
		return MAPVIEW_MAPNIK;
	if ( override && state == MAPVIEW_EDITORAERIAL )
		return MAPVIEW_AERIAL;
	return state;
}
static inline ViewOverlayMask OverlaysFor(MapViewState state, ViewOverlayMask mask, BOOL zoomedOut)
{
	if ( zoomedOut && state == MAPVIEW_EDITORAERIAL ) {
		return mask | VIEW_OVERLAY_LOCATOR;
	}
	if ( !zoomedOut ) {
		return mask & ~VIEW_OVERLAY_NONAME;
	}
	return mask;
}

-(void)setViewState:(MapViewState)state overlays:(ViewOverlayMask)overlays zoomedOut:(BOOL)zoomedOut
{
	if ( _viewState == state && _viewOverlayMask == overlays && _viewStateZoomedOut == zoomedOut )
		return;

	MapViewState oldState = StateFor(_viewState,_viewStateZoomedOut);
	MapViewState newState = StateFor( state, zoomedOut );
	ViewOverlayMask oldOverlays = OverlaysFor(_viewState, _viewOverlayMask, _viewStateZoomedOut);
	ViewOverlayMask newOverlays = OverlaysFor(state, overlays, zoomedOut);
	_viewState 			= state;
	_viewOverlayMask 	= overlays;
	_viewStateZoomedOut = zoomedOut;
	if ( newState == oldState && newOverlays == oldOverlays )
		return;

	[CATransaction begin];
	[CATransaction setAnimationDuration:0.5];

	_locatorLayer.hidden  = (newOverlays & VIEW_OVERLAY_LOCATOR) == 0;
	_gpsTraceLayer.hidden = (newOverlays & VIEW_OVERLAY_GPSTRACE) == 0;
    _noNameLayer.hidden   = (newOverlays & VIEW_OVERLAY_NONAME) == 0;

	switch (newState) {
		case MAPVIEW_EDITOR:
			_editorLayer.hidden = NO;
			_aerialLayer.hidden = YES;
			_mapnikLayer.hidden = YES;
			_userInstructionLabel.hidden = YES;
			_editorLayer.whiteText = YES;
			break;
		case MAPVIEW_EDITORAERIAL:
			_aerialLayer.aerialService = _customAerials.currentAerial;
			_editorLayer.hidden = NO;
			_aerialLayer.hidden = NO;
			_mapnikLayer.hidden = YES;
			_userInstructionLabel.hidden = YES;
			_aerialLayer.opacity = 0.75;
			_editorLayer.whiteText = YES;
			break;
		case MAPVIEW_AERIAL:
			_aerialLayer.aerialService = _customAerials.currentAerial;
			_editorLayer.hidden = YES;
			_aerialLayer.hidden = NO;
			_mapnikLayer.hidden = YES;
			_userInstructionLabel.hidden = YES;
			_aerialLayer.opacity = 1.0;
			break;
		case MAPVIEW_MAPNIK:
			_editorLayer.hidden = YES;
			_aerialLayer.hidden = YES;
			_mapnikLayer.hidden = NO;
			_userInstructionLabel.hidden = _viewState != MAPVIEW_EDITOR && _viewState != MAPVIEW_EDITORAERIAL;
			if ( !_userInstructionLabel.hidden )
				_userInstructionLabel.text = NSLocalizedString(@"Zoom to Edit",nil);
			break;
		case MAPVIEW_NONE:
			// shouldn't occur
			_editorLayer.hidden = YES;
			_aerialLayer.hidden = YES;
			_mapnikLayer.hidden = YES;
			break;
	}
	[self updateNotesFromServerWithDelay:0];

	[CATransaction commit];

	// enable/disable editing buttons based on visibility
	[_mainViewController updateUndoRedoButtonState];
	[self updateAerialAttributionButton];
}
-(MapViewState)viewState
{
	return _viewState;
}

-(void)setAerialTileService:(AerialService *)service
{
	_aerialLayer.aerialService = service;
	[self updateAerialAttributionButton];
}

-(void)setEnableBirdsEye:(BOOL)enableBirdsEye
{
	if ( _enableBirdsEye != enableBirdsEye ) {
		_enableBirdsEye = enableBirdsEye;
		if ( !enableBirdsEye ) {
			// remove birdsEye
			[self rotateBirdsEyeBy:-_birdsEyeRotation];
		}
	}
}
-(void)setEnableRotation:(BOOL)enableRotation
{
	if ( _enableRotation != enableRotation ) {
		_enableRotation = enableRotation;
		if ( !enableRotation ) {
			// remove rotation
			CGPoint centerPoint = CGRectCenter(self.bounds);
			CGFloat angle = OSMTransformRotation( _screenFromMapTransform );
			[self rotateBy:-angle aroundScreenPoint:centerPoint];
		}
	}
}
-(void)setEnableUnnamedRoadHalo:(BOOL)enableUnnamedRoadHalo
{
	if ( _enableUnnamedRoadHalo != enableUnnamedRoadHalo ) {
		_enableUnnamedRoadHalo = enableUnnamedRoadHalo;
		[_editorLayer.mapData clearCachedProperties];	// reset layers associated with objects
		[_editorLayer setNeedsLayout];
	}
}
-(void)setEnableGpxLogging:(BOOL)enableBreadCrumb
{
	if ( _enableGpxLogging != enableBreadCrumb ) {
		_enableGpxLogging = enableBreadCrumb;

		_gpxLayer.hidden = !self.enableGpxLogging;

		_locationManager.allowsBackgroundLocationUpdates = self.gpsInBackground && self.enableGpxLogging;
	}
}

-(void)setEnableTurnRestriction:(BOOL)enableTurnRestriction
{
	if ( _enableTurnRestriction != enableTurnRestriction ) {
		_enableTurnRestriction = enableTurnRestriction;
		[_editorLayer.mapData clearCachedProperties];    // reset layers associated with objects
		[_editorLayer setNeedsLayout];
	}
}


#pragma mark Coordinate Transforms

-(void)setScreenFromMapTransform:(OSMTransform)t
{
	if ( OSMTransformEqual(t, _screenFromMapTransform) )
		return;

#if TARGET_OS_IPHONE
	// save pushpinView coordinates
	CLLocationCoordinate2D pp = { 0 };
	if ( _pushpinView ) {
		pp = [self longitudeLatitudeForScreenPoint:_pushpinView.arrowPoint birdsEye:YES];
	}
#endif

#if 1
	// Wrap around if we translate too far
	OSMPoint unitX = UnitX(t);
	OSMPoint unitY = { -unitX.y, unitX.x };
	OSMPoint tran = Translation(t);
	double dx = Dot(tran, unitX);	// translation distance in x direction
	double dy = Dot(tran, unitY);
	double scale = OSMTransformScaleX(t);
	double mapSize = 256 * scale;
	if ( dx > 0 ) {
		double mul = ceil(dx/mapSize);
		t = OSMTransformTranslate(t, -mul*mapSize/scale, 0);
	} else if ( dx < -mapSize ) {
		double mul = floor(-dx/mapSize);
		t = OSMTransformTranslate(t, mul*mapSize/scale, 0);
	}
	if ( dy > 0 ) {
		double mul = ceil(dy/mapSize);
		t = OSMTransformTranslate(t, 0, -mul*mapSize/scale);
	} else if ( dy < -mapSize ) {
		double mul = floor(-dy/mapSize);
		t = OSMTransformTranslate(t, 0, mul*mapSize/scale);
	}
#endif

	// update transform
	_screenFromMapTransform = t;

	// determine if we've zoomed out enough to disable editing
	OSMRect bbox = [self screenLongitudeLatitude];
	double area = SurfaceArea(bbox);
	BOOL isZoomedOut = area > 2.0*1000*1000;
	if ( !_editorLayer.hidden && !_editorLayer.atVisibleObjectLimit && area < 200.0*1000*1000 )
		isZoomedOut = NO;
	self.viewStateZoomedOut = isZoomedOut;

	[self updateMouseCoordinates];
	[self updateUserLocationIndicator:nil];

	[self updateCountryCodeForLocationUsingNominatim];

#if TARGET_OS_IPHONE
	// update pushpin location
	if ( _pushpinView ) {
		_pushpinView.arrowPoint = [self screenPointForLatitude:pp.latitude longitude:pp.longitude birdsEye:YES];
	}
#endif
}

+(OSMRect)mapRectForLatLonRect:(OSMRect)latLon
{
	OSMRect rc = latLon;
	OSMPoint p1 = MapPointForLatitudeLongitude( rc.origin.y+rc.size.height, rc.origin.x );	// latitude increases opposite of map
	OSMPoint p2 = MapPointForLatitudeLongitude( rc.origin.y, rc.origin.x+rc.size.width );
	rc = OSMRectMake( p1.x, p1.y, p2.x-p1.x, p2.y-p1.y);	// map size
	return rc;
}


-(OSMTransform)screenFromMapTransform
{
	return _screenFromMapTransform;
}
-(OSMTransform)mapFromScreenTransform
{
	return OSMTransformInvert( _screenFromMapTransform );
}

-(OSMPoint)mapPointFromScreenPoint:(OSMPoint)point birdsEye:(BOOL)birdsEye
{
	if ( _birdsEyeRotation && birdsEye ) {
		CGPoint center = CGRectCenter(self.layer.bounds);
		point = FromBirdsEye( point, center, _birdsEyeDistance, _birdsEyeRotation );
	}
	point = OSMPointApplyTransform( point, self.mapFromScreenTransform );
	return point;
}

-(OSMPoint)screenPointFromMapPoint:(OSMPoint)point birdsEye:(BOOL)birdsEye
{
	point = OSMPointApplyTransform( point, _screenFromMapTransform );
	if ( _birdsEyeRotation && birdsEye ) {
		CGPoint center = CGRectCenter( self.layer.bounds );
		point = ToBirdsEye( point, center, _birdsEyeDistance, _birdsEyeRotation );
	}
	return point;
}

-(CGPoint)wrapScreenPoint:(CGPoint)pt
{
	if ( YES /*fabs(_screenFromMapTransform.a) < 16 && fabs(_screenFromMapTransform.c) < 16*/ ) {
		// only need to do this if we're zoomed out all the way: pick the best world map on which to display location

		CGRect rc = self.layer.bounds;
		OSMPoint unitX = UnitX(_screenFromMapTransform);
		OSMPoint unitY = { -unitX.y, unitX.x };
		double mapSize = 256 * OSMTransformScaleX(_screenFromMapTransform);
		if ( pt.x >= rc.origin.x+rc.size.width ) {
			pt.x -= mapSize*unitX.x;
			pt.y -= mapSize*unitX.y;
		} else if ( pt.x < rc.origin.x ) {
			pt.x += mapSize*unitX.x;
			pt.y += mapSize*unitX.y;
		}
		if ( pt.y >= rc.origin.y+rc.size.height ) {
			pt.x -= mapSize*unitY.x;
			pt.y -= mapSize*unitY.y;
		} else if ( pt.y < rc.origin.y ) {
			pt.x += mapSize*unitY.x;
			pt.y += mapSize*unitY.y;
		}
	}
	return pt;
}

-(OSMRect)mapRectFromScreenRect:(OSMRect)rect
{
	return OSMRectApplyTransform( rect, self.mapFromScreenTransform );
}
-(OSMRect)screenRectFromMapRect:(OSMRect)rect
{
	return OSMRectApplyTransform(rect, self.screenFromMapTransform);
}

-(CLLocationCoordinate2D)longitudeLatitudeForScreenPoint:(CGPoint)point birdsEye:(BOOL)birdsEye
{
	OSMPoint mapPoint = [self mapPointFromScreenPoint:OSMPointMake(point.x, point.y) birdsEye:birdsEye];
	OSMPoint coord = LongitudeLatitudeFromMapPoint(mapPoint);
	CLLocationCoordinate2D loc = { coord.y, coord.x };
	return loc;
}


-(double)metersPerPixel
{
	OSMRect screenRect = OSMRectFromCGRect( self.layer.bounds );
	OSMRect rc = [self mapRectFromScreenRect:screenRect];
	OSMPoint southwest = { rc.origin.x, rc.origin.y + rc.size.height };
	OSMPoint northeast = { rc.origin.x + rc.size.width, rc.origin.y };
	southwest = LongitudeLatitudeFromMapPoint(southwest);
	northeast = LongitudeLatitudeFromMapPoint(northeast);
	// if the map is zoomed to the top/bottom boundary then the y-axis will be crazy
	if ( southwest.y > northeast.y ) {
		northeast.y = southwest.y;
		screenRect.size.height = 0;
	}
	double meters = GreatCircleDistance( southwest, northeast );
	double pixels = hypot(screenRect.size.width,screenRect.size.height);
	return meters/pixels;
}

-(OSMRect)boundingScreenRectForMapRect:(OSMRect)mapRect
{
	OSMRect rc = mapRect;
	OSMPoint corners[] = {
		rc.origin.x, rc.origin.y,
		rc.origin.x + rc.size.width, rc.origin.y,
		rc.origin.x + rc.size.width, rc.origin.y + rc.size.height,
		rc.origin.x, rc.origin.y + rc.size.height
	};
	for ( int i = 0; i < 4; ++i ) {
		corners[i] = [self screenPointFromMapPoint:corners[i] birdsEye:NO];
	}
	double minX = corners[0].x;
	double minY = corners[0].y;
	double maxX = minX;
	double maxY = minY;
	for ( int i = 1; i < 4; ++i ) {
		minX = MIN( minX, corners[i].x );
		maxX = MAX( maxX, corners[i].x );
		minY = MIN( minY, corners[i].y );
		maxY = MAX( maxY, corners[i].y );
	}
	rc = OSMRectMake( minX, minY, maxX-minX, maxY-minY);
	return rc;
}

-(OSMRect)boundingMapRectForScreenRect:(OSMRect)screenRect
{
	OSMRect rc = screenRect;
	OSMPoint corners[] = {
		rc.origin.x, rc.origin.y,
		rc.origin.x + rc.size.width, rc.origin.y,
		rc.origin.x + rc.size.width, rc.origin.y + rc.size.height,
		rc.origin.x, rc.origin.y + rc.size.height
	};
	for ( int i = 0; i < 4; ++i ) {
		corners[i] = [self mapPointFromScreenPoint:corners[i] birdsEye:YES];
	}
	double minX = corners[0].x;
	double minY = corners[0].y;
	double maxX = minX;
	double maxY = minY;
	for ( int i = 1; i < 4; ++i ) {
		minX = MIN( minX, corners[i].x );
		maxX = MAX( maxX, corners[i].x );
		minY = MIN( minY, corners[i].y );
		maxY = MAX( maxY, corners[i].y );
	}
	rc = OSMRectMake( minX, minY, maxX-minX, maxY-minY);
	return rc;
}

-(OSMRect)boundingMapRectForScreen
{
	OSMRect rc = OSMRectFromCGRect( self.layer.bounds );
	return [self boundingMapRectForScreenRect:rc];
}

-(OSMRect)screenLongitudeLatitude
{
#if 1
	OSMRect rc = [self boundingMapRectForScreen];
#else
	OSMRect rc = [self mapRectFromScreenRect];
#endif
	OSMPoint southwest = { rc.origin.x, rc.origin.y + rc.size.height };
	OSMPoint northeast = { rc.origin.x + rc.size.width, rc.origin.y };
	southwest = LongitudeLatitudeFromMapPoint(southwest);
	northeast = LongitudeLatitudeFromMapPoint(northeast);
	rc.origin.x = southwest.x;
	rc.origin.y = southwest.y;
	rc.size.width = northeast.x - southwest.x;
	rc.size.height = northeast.y - southwest.y;
	if ( rc.size.width < 0 ) // crossed 180 degrees longitude
		rc.size.width += 360;
	if ( rc.size.height < 0 )
		rc.size.height += 180;
	return rc;
}

-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude birdsEye:(BOOL)birdsEye
{
	OSMPoint pt = MapPointForLatitudeLongitude( latitude, longitude );
	pt = [self screenPointFromMapPoint:pt birdsEye:birdsEye];
	return CGPointFromOSMPoint(pt);
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude
{
	CGPoint point = [self screenPointForLatitude:latitude longitude:longitude birdsEye:NO];
	CGPoint center = _crossHairs.position;
	CGPoint delta = { center.x - point.x, center.y - point.y };
	[self adjustOriginBy:delta];
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude scale:(double)scale
{
	// translate
	[self setTransformForLatitude:latitude longitude:longitude];

	double ratio = scale / OSMTransformScaleX(_screenFromMapTransform);
	[self adjustZoomBy:ratio aroundScreenPoint:_crossHairs.position];
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude width:(double)widthDegrees
{
	double scale = 360/(widthDegrees / 2);
	[self setTransformForLatitude:latitude longitude:longitude scale:scale];
}

-(void)setMapLocation:(MapLocation *)location
{
	double zoom = location.zoom ?: 18.0;
	double scale = pow(2,zoom);
	[self setTransformForLatitude:location.latitude longitude:location.longitude scale:scale];
	if ( location.viewState != MAPVIEW_NONE ) {
		self.viewState = location.viewState;
	}
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude zoom:(double)zoom
{
	double scale = pow(2,zoom);
	[self setTransformForLatitude:latitude longitude:longitude scale:scale];
}

-(double)zoom
{
	double scaleX = OSMTransformScaleX( _screenFromMapTransform );
	return log2(scaleX);
}


-(CGPoint)pointOnObject:(OsmBaseObject *)object forPoint:(CGPoint)point
{
	CLLocationCoordinate2D latLon = [self longitudeLatitudeForScreenPoint:point birdsEye:YES];
	OSMPoint latLon2 = [object pointOnObjectForPoint:OSMPointMake(latLon.longitude,latLon.latitude)];
	CGPoint pos = [self screenPointForLatitude:latLon2.y longitude:latLon2.x birdsEye:YES];
	return pos;
}

#pragma mark Discard stale data

-(void)discardStaleData
{
	if ( self.enableAutomaticCacheManagement ) {
		OsmMapData * mapData = self.editorLayer.mapData;
		BOOL changed = [mapData discardStaleData];
		if ( changed ) {
			[self flashMessage:NSLocalizedString(@"Cache trimmed",nil)];
			[self.editorLayer updateMapLocation];	// download data if necessary
		}
	}
}

#pragma mark Progress indicator

-(void)progressIncrement
{
	assert( _progressActive >= 0 );
	_progressActive++;
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

- (GPS_STATE)gpsState
{
	return _gpsState;
}
- (void)setGpsState:(GPS_STATE)gpsState
{
	if ( gpsState != _gpsState ) {
		// update collection of GPX points
		if ( _gpsState == GPS_STATE_NONE && gpsState != GPS_STATE_NONE ) {
			[_gpxLayer startNewTrack];
		} else if ( gpsState == GPS_STATE_NONE ) {
			[_gpxLayer endActiveTrack];
		}

		if ( gpsState == GPS_STATE_HEADING ) {
			// rotate to heading
			CGPoint center = CGRectCenter(self.bounds);
			double screenAngle = OSMTransformRotation( _screenFromMapTransform );
			double heading = [self headingForCLHeading:_locationManager.heading];
			[self animateRotationBy:-(screenAngle+heading) aroundPoint:center];
		} else if ( gpsState == GPS_STATE_LOCATION ) {
			// orient toward north
			CGPoint center = CGRectCenter(self.bounds);
			double rotation = OSMTransformRotation( _screenFromMapTransform );
			[self animateRotationBy:-rotation aroundPoint:center];
		} else {
			// keep whatever rotation we had
		}

		if ( gpsState == GPS_STATE_NONE ) {
			_centerOnGPSButton.hidden = YES;
			_voiceAnnouncement.enabled = NO;
		} else {
			_voiceAnnouncement.enabled = YES;
		}

		_gpsState = gpsState;
		if ( _gpsState != GPS_STATE_NONE ) {
			self.locating = YES;
		} else {
			self.locating = NO;
		}
	}
}

-(void)setUserOverrodeLocationPosition:(BOOL)userOverrodeLocationPosition
{
	_userOverrodeLocationPosition 	= userOverrodeLocationPosition;
	_centerOnGPSButton.hidden		= !userOverrodeLocationPosition || _gpsState == GPS_STATE_NONE;
}
-(void)setUserOverrodeLocationZoom:(BOOL)userOverrodeLocationZoom
{
	_userOverrodeLocationZoom = userOverrodeLocationZoom;
	_centerOnGPSButton.hidden = !userOverrodeLocationZoom || _gpsState == GPS_STATE_NONE;
}


-(BOOL)gpsInBackground
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_GPX_BACKGROUND_TRACKING];
}
-(void)setGpsInBackground:(BOOL)gpsInBackground
{
	[[NSUserDefaults standardUserDefaults] setBool:gpsInBackground forKey:USER_DEFAULTS_GPX_BACKGROUND_TRACKING];

	_locationManager.allowsBackgroundLocationUpdates = gpsInBackground && self.enableGpxLogging;

	if ( gpsInBackground ) {
		// ios 8 and later:
		if ( [_locationManager respondsToSelector:@selector(requestAlwaysAuthorization)] ) {
			[_locationManager  requestAlwaysAuthorization];
		}
	}
}

-(void)setLocating:(BOOL)locating
{
	if ( _locating == locating )
		return;
	_locating = locating;

	if ( locating ) {
		
		CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
		if ( status == kCLAuthorizationStatusRestricted || status == kCLAuthorizationStatusDenied ) {
			[AppDelegate askUserToAllowLocationAccess:self.mainViewController];
            
			self.gpsState = GPS_STATE_NONE;
			return;
		}

		// ios 8 and later:
		if ( [_locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)] ) {
			[_locationManager requestWhenInUseAuthorization];
		}

		self.userOverrodeLocationPosition	= NO;
		self.userOverrodeLocationZoom		= NO;
		[_locationManager startUpdatingLocation];
#if TARGET_OS_IPHONE
		[_locationManager startUpdatingHeading];
#endif
	} else {
		[_locationManager stopUpdatingLocation];
#if TARGET_OS_IPHONE
		[_locationManager stopUpdatingHeading];
#endif
		[_locationBallLayer removeFromSuperlayer];
		_locationBallLayer = nil;
	}
}

-(IBAction)centerOnGPS:(id)sender
{
	if ( _gpsState == GPS_STATE_NONE )
		return;

	self.userOverrodeLocationPosition = NO;
	CLLocation * location = _locationManager.location;
	[self setTransformForLatitude:location.coordinate.latitude longitude:location.coordinate.longitude];
}

-(IBAction)compassPressed:(id)sender
{
	switch ( self.gpsState ) {
		case GPS_STATE_HEADING:
			self.gpsState = GPS_STATE_LOCATION;
			break;
		case GPS_STATE_LOCATION:
			self.gpsState = GPS_STATE_HEADING;
			break;
		case GPS_STATE_NONE:
			[self rotateToNorth];
			break;
	}
}

- (void)updateUserLocationIndicator:(CLLocation *)location
{
	if ( _locationBallLayer ) {
		// set new position
		CLLocationCoordinate2D coord = location ? location.coordinate : _locationManager.location.coordinate;
		CGPoint point = [self screenPointForLatitude:coord.latitude longitude:coord.longitude birdsEye:YES];
		point = [self wrapScreenPoint:point];
		_locationBallLayer.position = point;

		// set location accuracy
		CLLocationAccuracy meters = _locationManager.location.horizontalAccuracy;
		CGFloat pixels = meters / [self metersPerPixel];
		if ( pixels == 0.0 )
			pixels = 100.0;
		_locationBallLayer.radiusInPixels = pixels;
	}
}

- (double)headingForCLHeading:(CLHeading *)clHeading
{
	double heading = clHeading.trueHeading * M_PI / 180;
	switch ( [[UIApplication sharedApplication] statusBarOrientation] ) {
		case UIDeviceOrientationPortraitUpsideDown:
			heading += M_PI;
			break;
		case UIDeviceOrientationLandscapeLeft:
			heading += M_PI/2;
			break;
		case UIDeviceOrientationLandscapeRight:
			heading -= M_PI/2;
			break;
		case UIDeviceOrientationPortrait:
		default:
			break;
	}
	return heading;
}

- (void)updateHeadingSmoothed:(double)heading accuracy:(double)accuracy
{
	double screenAngle = OSMTransformRotation( _screenFromMapTransform );
	
	if ( _gpsState == GPS_STATE_HEADING ) {
		// rotate to new heading
		CGPoint center = CGRectCenter( self.bounds );
		double delta = -(heading + screenAngle);
		[self rotateBy:delta aroundScreenPoint:center];
	} else if ( _locationBallLayer ) {
		// rotate location ball
		_locationBallLayer.headingAccuracy	= accuracy * (M_PI / 180);
		_locationBallLayer.showHeading		= YES;
		_locationBallLayer.heading			= heading + screenAngle - M_PI/2;
	}
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
	static double smoothHeading = 0.0;
	double accuracy = newHeading.headingAccuracy;
	double heading = [self headingForCLHeading:newHeading];

	[[DisplayLink shared] addName:@"smoothHeading" block:^{
		double delta = heading - smoothHeading;
		if ( delta > M_PI ) {
			delta -= 2*M_PI;
		} else if ( delta < -M_PI ) {
			delta += 2*M_PI;
		}
		delta *= 0.15;
		if ( fabs(delta) < 0.001 ) {
			smoothHeading = heading;
		} else {
			smoothHeading += delta;
		}
		[self updateHeadingSmoothed:smoothHeading accuracy:accuracy];
		if ( heading == smoothHeading ) {
			[[DisplayLink shared] removeName:@"smoothHeading"];
		}
	}];
}

- (void)locationUpdatedTo:(CLLocation *)newLocation
{
	if ( _gpsState == GPS_STATE_NONE ) {
		// sometimes we get a notification after turning off notifications
		DLog(@"discard location notification");
		return;
	}

	if ( [newLocation.timestamp compare:[NSDate dateWithTimeIntervalSinceNow:-10.0]] < 0 ) {
		// its old data
		DLog(@"discard old GPS data: %@, %@\n",newLocation.timestamp, [NSDate date]);
		return;
	}

	// check if we moved an appreciable distance
	double delta = hypot( newLocation.coordinate.latitude - _currentLocation.coordinate.latitude,
						  newLocation.coordinate.longitude - _currentLocation.coordinate.longitude);
	delta *= MetersPerDegree( newLocation.coordinate.latitude );
	if ( _locationBallLayer && delta < 0.1 && fabs(newLocation.horizontalAccuracy - _currentLocation.horizontalAccuracy) < 1.0 )
		return;
	_currentLocation = [newLocation copy];

	if ( _voiceAnnouncement && !_editorLayer.hidden ) {
		[_voiceAnnouncement announceForLocation:newLocation.coordinate];
	}

	if ( _gpxLayer.activeTrack ) {
		[_gpxLayer addPoint:newLocation];
	}

	if ( self.gpsState == GPS_STATE_NONE ) {
		self.locating = NO;
	}

#if TARGET_OS_IPHONE
	CLLocationCoordinate2D pp = [self longitudeLatitudeForScreenPoint:_pushpinView.arrowPoint birdsEye:NO];
#endif

	if ( !_userOverrodeLocationPosition ) {
		// move view to center on new location
		if ( _userOverrodeLocationZoom ) {
			[self setTransformForLatitude:newLocation.coordinate.latitude longitude:newLocation.coordinate.longitude];
		} else {
			double widthDegrees = 20 /*meters*/ / EarthRadius * 360;
			[self setTransformForLatitude:newLocation.coordinate.latitude longitude:newLocation.coordinate.longitude width:widthDegrees];
		}
	}
#if TARGET_OS_IPHONE
	_pushpinView.arrowPoint = [self screenPointForLatitude:pp.latitude longitude:pp.longitude birdsEye:NO];
#endif

	if ( _locationBallLayer == nil ) {
		_locationBallLayer 				= [LocationBallLayer new];
		_locationBallLayer.zPosition 	= Z_BALL;
		_locationBallLayer.heading 		= 0.0;
		_locationBallLayer.showHeading 	= YES;
		[self.layer addSublayer:_locationBallLayer];
	}
	[self updateUserLocationIndicator:newLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
	for ( CLLocation * location in locations ) {
		[self locationUpdatedTo:location];
	}
}

-(void)locationManagerDidPauseLocationUpdates:(CLLocationManager *)manager
{
	NSLog(@"GPS paused by iOS\n");
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
	MainViewController * controller = self.mainViewController;
	if ( error.code == kCLErrorDenied ) {
		[controller setGpsState:GPS_STATE_NONE];
		if ( ![self isLocationSpecified] ) {
			// go home
			[self setTransformForLatitude:47.6858 longitude:-122.1917 width:0.01];
		}
		NSString * text = [NSString stringWithFormat:NSLocalizedString(@"Ensure Location Services is enabled and you have granted this application access.\n\nError: %@",nil),
						   error ? error.localizedDescription : NSLocalizedString(@"Location services timed out.",nil)];
		text = [NSLocalizedString(@"The current location cannot be determined: ",nil) stringByAppendingString:text];
		error = [NSError errorWithDomain:@"Location" code:100 userInfo:@{ NSLocalizedDescriptionKey : text} ];
		[self presentError:error flash:NO];
	} else {
		// driving through a tunnel or something
		NSString * text = NSLocalizedString(@"Location unavailable",nil);
		error = [NSError errorWithDomain:@"Location" code:100 userInfo:@{ NSLocalizedDescriptionKey : text} ];
		[self presentError:error flash:YES];
	}
}


#pragma mark Undo/Redo

-(void)placePushpinForSelection
{
	OsmBaseObject * selection = _editorLayer.selectedPrimary;
	if ( selection == nil )
		return;
	OSMPoint loc = selection.selectionPoint;
	CGPoint point = [self screenPointForLatitude:loc.y longitude:loc.x birdsEye:YES];
	[self placePushpinAtPoint:point object:selection];
	
	if ( !CGRectContainsPoint( self.bounds, _pushpinView.arrowPoint ) ) {
		// need to zoom to location
		[self setTransformForLatitude:loc.y longitude:loc.x];
	}
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
	[_editorLayer setNeedsLayout];
}

- (IBAction)redo:(id)sender
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.hidden ) {
		[self flashMessage:NSLocalizedString(@"Editing layer not visible",nil)];
		return;
	}
	[self removePin];
#endif

	[_editorLayer.mapData redo];
	[_editorLayer setNeedsLayout];
}


#pragma mark Resize & movement

-(BOOL)isLocationSpecified
{
	return !OSMTransformEqual( _screenFromMapTransform, OSMTransformIdentity() );
}


-(void)updateMouseCoordinates
{
}

-(void)adjustOriginBy:(CGPoint)delta
{
	if ( delta.x == 0.0 && delta.y == 0.0 )
		return;

	[self refreshNoteButtonsFromDatabase];

	OSMTransform o = OSMTransformMakeTranslation(delta.x, delta.y);
	OSMTransform t = OSMTransformConcat( _screenFromMapTransform, o );
	self.screenFromMapTransform = t;
}

-(void)adjustZoomBy:(CGFloat)ratio aroundScreenPoint:(CGPoint)zoomCenter
{
	if ( _isRotateObjectMode )
		return;

	const double maxZoomIn = 1 << 30;
	if ( ratio == 1.0 )
		return;
	double scale = OSMTransformScaleX(_screenFromMapTransform);
	if ( ratio * scale < 1.0 ) {
		ratio = 1.0 / scale;
	}
	if ( ratio * scale > maxZoomIn ) {
		ratio = maxZoomIn / scale;
	}

	[self refreshNoteButtonsFromDatabase];

	OSMPoint offset = [self mapPointFromScreenPoint:OSMPointFromCGPoint(zoomCenter) birdsEye:NO];
	OSMTransform t = _screenFromMapTransform;
	t = OSMTransformTranslate( t, offset.x, offset.y );
	t = OSMTransformScale( t, ratio );
	t = OSMTransformTranslate( t, -offset.x, -offset.y );
	self.screenFromMapTransform = t;
}

-(void)rotateBy:(CGFloat)angle aroundScreenPoint:(CGPoint)zoomCenter
{
	if ( angle == 0.0 )
		return;

	[self refreshNoteButtonsFromDatabase];

	OSMPoint offset = [self mapPointFromScreenPoint:OSMPointFromCGPoint(zoomCenter) birdsEye:NO];
	OSMTransform t = _screenFromMapTransform;
	t = OSMTransformTranslate( t, offset.x, offset.y );
	t = OSMTransformRotate( t, angle );
	t = OSMTransformTranslate( t, -offset.x, -offset.y );
	self.screenFromMapTransform = t;

	double screenAngle = OSMTransformRotation( _screenFromMapTransform );
	_compassButton.transform = CGAffineTransformMakeRotation(screenAngle);
	if ( _locationBallLayer ) {
		if ( _gpsState == GPS_STATE_HEADING && fabs(_locationBallLayer.heading - -M_PI/2) < 0.0001 ) {
			// don't pin location ball to North until we've animated our rotation to north
			_locationBallLayer.heading = -M_PI/2;
		} else {
			double heading = [self headingForCLHeading:_locationManager.heading];
			_locationBallLayer.heading = screenAngle + heading - M_PI/2;
		}
	}
}

static NSString * const DisplayLinkHeading	= @"Heading";

- (void)animateRotationBy:(double)deltaHeading aroundPoint:(CGPoint)center
{
	// don't rotate the long way around
	while ( deltaHeading < -M_PI )
		deltaHeading += 2*M_PI;
	while ( deltaHeading > M_PI )
		deltaHeading -= 2*M_PI;
	
	if ( fabs(deltaHeading) < 0.00001 )
		return;
	
	CFTimeInterval startTime = CACurrentMediaTime();
	
	double duration = 0.4;
	__weak MapView * weakSelf = self;
	__block double prevHeading = 0;
	__weak DisplayLink * displayLink = [DisplayLink shared];
	[displayLink addName:DisplayLinkHeading block:^{
		MapView * myself = weakSelf;
		if ( myself ) {
			CFTimeInterval elapsedTime = CACurrentMediaTime() - startTime;
			if ( elapsedTime > duration ) {
				elapsedTime = duration;	// don't want to over-rotate
			}
			// Rotate using an ease-in/out curve. This ensures that small changes in direction don't cause jerkiness.
			// result = interpolated value, t = current time, b = initial value, c = delta value, d = duration
#if 1
			double (^easeInOutQuad)( double t, double b, double c, double d ) = ^( double t, double b, double c, double d ) {
				t /= d/2;
				if (t < 1) return c/2*t*t + b;
				t--;
				return -c/2 * (t*(t-2) - 1) + b;
			};
#else
			double (^easeInOutQuad)( double t, double b, double c, double d ) = ^( double t, double b, double c, double d ) {
				return b + c*(t/d);
			};
#endif
			double miniHeading = easeInOutQuad( elapsedTime, 0, deltaHeading, duration);
			[myself rotateBy:miniHeading-prevHeading aroundScreenPoint:center];
			prevHeading = miniHeading;
			if ( elapsedTime >= duration ) {
				[displayLink removeName:DisplayLinkHeading];
			}
		}
	}];
}

-(void)rotateBirdsEyeBy:(CGFloat)angle
{
	// limit maximum rotation
	OSMTransform t = _screenFromMapTransform;
	double maxRotation = 65 * (M_PI/180);
#if TRANSFORM_3D
	double currentRotation = atan2( t.m23, t.m22 );
#else
	double currentRotation = _birdsEyeRotation;
#endif
	if ( currentRotation+angle > maxRotation )
		angle = maxRotation - currentRotation;
	if ( currentRotation+angle < 0 )
		angle = -currentRotation;

	CGPoint center = CGRectCenter( self.bounds );
	OSMPoint offset = [self mapPointFromScreenPoint:OSMPointFromCGPoint(center) birdsEye:NO];

	t = OSMTransformTranslate( t, offset.x, offset.y );
#if TRANSFORM_3D
	t = CATransform3DRotate(t, delta, 1.0, 0.0, 0.0);
#else
	_birdsEyeRotation += angle;
#endif
	t = OSMTransformTranslate( t, -offset.x, -offset.y );
	self.screenFromMapTransform = t;

	if ( _locationBallLayer ) {
		[self updateUserLocationIndicator:nil];
	}
}

-(void)rotateToNorth
{
	// Rotate to face North
	CGPoint center = CGRectCenter(self.bounds);
	double rotation = OSMTransformRotation( _screenFromMapTransform );
	[self animateRotationBy:-rotation aroundPoint:center];
}

#pragma mark Key presses

/**
 Offers the option to either merge tags or replace them with the copied tags.
 @param sender nil
 */
-(IBAction)paste:(id)sender
{
    NSDictionary * copyPasteTags = [[NSUserDefaults standardUserDefaults] objectForKey:@"copyPasteTags"];
    if ( copyPasteTags.count == 0 ) {
		[self showAlert:NSLocalizedString(@"No tags to paste",nil) message:nil];
		return;
    }

	if ( _editorLayer.selectedPrimary.tags.count > 0 ) {
		NSString * question = [NSString stringWithFormat:NSLocalizedString(@"Pasting %ld tag(s)",nil), (long)copyPasteTags.count];
		UIAlertController * alertPaste = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Paste",nil) message:question preferredStyle:UIAlertControllerStyleAlert];
		[alertPaste addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
		[alertPaste addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Merge Tags",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * alertAction) {
			[_editorLayer pasteTagsMerge:_editorLayer.selectedPrimary];
			[self refreshPushpinText];
		}]];
		[alertPaste addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Replace Tags",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * alertAction) {
			[_editorLayer pasteTagsReplace:_editorLayer.selectedPrimary];
			[self refreshPushpinText];
		}]];
		[self.mainViewController presentViewController:alertPaste animated:YES completion:nil];
	} else {
		[_editorLayer pasteTagsReplace:_editorLayer.selectedPrimary];
		[self refreshPushpinText];
	}
}

-(IBAction)delete:(id)sender
{
	void(^deleteHandler)(UIAlertAction * action) = ^(UIAlertAction * action) {
		NSString * error = nil;
		EditAction canDelete = [_editorLayer canDeleteSelectedObject:&error];
		if ( canDelete ) {
			canDelete();
			CGPoint pos = _pushpinView.arrowPoint;
			[self removePin];
			if ( _editorLayer.selectedPrimary ) {
				pos = [self pointOnObject:_editorLayer.selectedPrimary forPoint:pos];
				[self placePushpinAtPoint:pos object:_editorLayer.selectedPrimary];
			}
		} else {
			[self showAlert:NSLocalizedString(@"Delete failed",nil) message:error];
		}
	};


	UIAlertController *	alertDelete;
	if ( _editorLayer.selectedRelation.isMultipolygon && _editorLayer.selectedPrimary.isWay ) {
		// delete way from relation
		alertDelete = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete",nil) message:NSLocalizedString(@"Member of multipolygon relation",nil) preferredStyle:UIAlertControllerStyleActionSheet];
		[alertDelete addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
		[alertDelete addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete completely",nil) style:UIAlertActionStyleDefault handler:deleteHandler]];
		[alertDelete addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Detach from relation",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			NSString * error = nil;
			EditAction canRemove = [_editorLayer.mapData canRemoveObject:_editorLayer.selectedPrimary fromRelation:_editorLayer.selectedRelation error:&error];
			if ( canRemove ) {
				canRemove();
				_editorLayer.selectedRelation = nil;
				[self refreshPushpinText];
			} else {
				[self showAlert:NSLocalizedString(@"Delete failed",nil) message:error];
			}
		}]];

		// compute location for action sheet to originate
		CGRect button = self.editControl.bounds;
		CGFloat segmentWidth = button.size.width / self.editControl.numberOfSegments;	// hack because we can't get the frame for an individual segment
		button.origin.x += button.size.width - 2*segmentWidth;
		button.size.width = segmentWidth;
		alertDelete.popoverPresentationController.sourceView = self.editControl;
		alertDelete.popoverPresentationController.sourceRect = button;

	} else {
		// regular delete
		NSString * name = [_editorLayer.selectedPrimary friendlyDescription];
		NSString * question = [NSString stringWithFormat:@"Delete %@?",name];
		alertDelete = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete",nil) message:question preferredStyle:UIAlertControllerStyleAlert];
		[alertDelete addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
		[alertDelete addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Delete",nil) style:UIAlertActionStyleDestructive handler:deleteHandler]];
	}
	[self.mainViewController presentViewController:alertDelete animated:YES completion:nil];
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


#pragma mark Edit Actions

typedef enum {
	// used by edit control:
	ACTION_EDITTAGS,
	ACTION_ADDNOTE,
	ACTION_DELETE,
	ACTION_MORE,
	// used for action sheet edits:
	ACTION_SPLIT,
	ACTION_RECTANGULARIZE,
	ACTION_STRAIGHTEN,
	ACTION_REVERSE,
	ACTION_DUPLICATE,
	ACTION_ROTATE,
	ACTION_JOIN,
	ACTION_DISCONNECT,
	ACTION_CIRCULARIZE,
	ACTION_COPYTAGS,
	ACTION_PASTETAGS,
	ACTION_RESTRICT,
	ACTION_CREATE_RELATION
} EDIT_ACTION;

NSString * ActionTitle( EDIT_ACTION action, BOOL abbrev )
{
	switch (action) {
		case ACTION_SPLIT:			return NSLocalizedString(@"Split",nil);
		case ACTION_RECTANGULARIZE:	return NSLocalizedString(@"Make Rectangular",nil);
		case ACTION_STRAIGHTEN:		return NSLocalizedString(@"Straighten",nil);
		case ACTION_REVERSE:		return NSLocalizedString(@"Reverse",nil);
		case ACTION_DUPLICATE:		return NSLocalizedString(@"Duplicate",nil);
		case ACTION_ROTATE:			return NSLocalizedString(@"Rotate",nil);
		case ACTION_CIRCULARIZE:	return NSLocalizedString(@"Make Circular",nil);
		case ACTION_JOIN:			return NSLocalizedString(@"Join",nil);
		case ACTION_DISCONNECT:		return NSLocalizedString(@"Disconnect",nil);
		case ACTION_COPYTAGS:		return NSLocalizedString(@"Copy Tags",nil);
		case ACTION_PASTETAGS:		return NSLocalizedString(@"Paste",nil);
		case ACTION_EDITTAGS:		return NSLocalizedString(@"Tags", nil);
		case ACTION_ADDNOTE:		return NSLocalizedString(@"Add Note", nil);
		case ACTION_DELETE:			return NSLocalizedString(@"Delete",nil);
		case ACTION_MORE:			return NSLocalizedString(@"More...",nil);
		case ACTION_RESTRICT:		return abbrev ? NSLocalizedString(@"Restrict", nil) : NSLocalizedString(@"Turn Restrictions", nil);
		case ACTION_CREATE_RELATION:return NSLocalizedString(@"Create Relation", nil);
	};
	return nil;
}

- (void)updateEditControl
{
	BOOL show = _pushpinView || _editorLayer.selectedPrimary;
	_editControl.hidden = !show;
	if ( show ) {
		if ( _editorLayer.selectedPrimary == nil ) {
			// brand new node
			if ( _editorLayer.canPasteTags )
				self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_ADDNOTE), @(ACTION_PASTETAGS) ];
			else
				self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_ADDNOTE) ];
		} else {
			if ( _editorLayer.selectedPrimary.isRelation )
				if ( _editorLayer.selectedPrimary.isRelation.isRestriction )
					self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS), @(ACTION_RESTRICT) ];
				else if ( _editorLayer.selectedPrimary.isRelation.isMultipolygon )
					self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS), @(ACTION_MORE) ];
				else
					self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS) ];
				else
					self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS), @(ACTION_DELETE), @(ACTION_MORE) ];
		}
		[_editControl removeAllSegments];
		for ( NSNumber * action in _editControlActions ) {
			NSString * title = ActionTitle( (EDIT_ACTION)action.integerValue, YES );
			[_editControl insertSegmentWithTitle:title atIndex:_editControl.numberOfSegments animated:NO];
		}
	}
}

- (void)presentEditActionSheet:(id)sender
{
	NSArray * actionList = nil;
	if ( _editorLayer.selectedWay ) {
		if ( _editorLayer.selectedNode ) {
			// node in way
			NSArray<OsmWay *> * parentWays = [_editorLayer.mapData waysContainingNode:_editorLayer.selectedNode];
            BOOL disconnect		= parentWays.count > 1 || _editorLayer.selectedNode.hasInterestingTags;
			BOOL split 			= _editorLayer.selectedWay.isClosed || (_editorLayer.selectedNode != _editorLayer.selectedWay.nodes[0] && _editorLayer.selectedNode != _editorLayer.selectedWay.nodes.lastObject);
			BOOL join 			= parentWays.count > 1;
			BOOL restriction	= _enableTurnRestriction && _editorLayer.selectedWay.tags[@"highway"] && parentWays.count > 1;
			
			NSMutableArray * a = [NSMutableArray arrayWithObjects:@(ACTION_COPYTAGS), nil];
            
			if ( disconnect )
				[a addObject:@(ACTION_DISCONNECT)];
			if ( split )
				[a addObject:@(ACTION_SPLIT)];
			if ( join )
				[a addObject:@(ACTION_JOIN)];
			[a addObject:@(ACTION_ROTATE)];
			if ( restriction )
				[a addObject:@(ACTION_RESTRICT)];
			actionList = [NSArray arrayWithArray:a];
		} else {
			if ( _editorLayer.selectedWay.isClosed ) {
				// polygon
				actionList = @[ @(ACTION_COPYTAGS), @(ACTION_RECTANGULARIZE), @(ACTION_CIRCULARIZE), @(ACTION_ROTATE), @(ACTION_DUPLICATE), @(ACTION_REVERSE), @(ACTION_CREATE_RELATION) ];
			} else {
				// line
				actionList = @[ @(ACTION_COPYTAGS), @(ACTION_STRAIGHTEN), @(ACTION_REVERSE), @(ACTION_DUPLICATE), @(ACTION_CREATE_RELATION) ];
			}
		}
	} else if ( _editorLayer.selectedNode ) {
		// node
		actionList = @[ @(ACTION_COPYTAGS), @(ACTION_DUPLICATE) ];
	} else if ( _editorLayer.selectedRelation ) {
		// relation
		if ( _editorLayer.selectedRelation.isMultipolygon ) {
			actionList = @[ @(ACTION_COPYTAGS), @(ACTION_ROTATE), @(ACTION_DUPLICATE) ];
		} else {
			actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS) ];
		}
	} else {
		// nothing selected
		return;
	}
	UIAlertController * actionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Perform Action",nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	for ( NSNumber * value in actionList ) {
		NSString * title = ActionTitle( (EDIT_ACTION)value.integerValue, NO );
		[actionSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			[self performEditAction:(EDIT_ACTION)value.integerValue];
		}]];
	}
	[actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
	[self.mainViewController presentViewController:actionSheet animated:YES completion:nil];

	// compute location for action sheet to originate
	CGRect button = self.editControl.bounds;
	CGFloat segmentWidth = button.size.width / self.editControl.numberOfSegments;	// hack because we can't get the frame for an individual segment
	button.origin.x += button.size.width - segmentWidth;
	button.size.width = segmentWidth;
	actionSheet.popoverPresentationController.sourceView = self.editControl;
	actionSheet.popoverPresentationController.sourceRect = button;
}


-(IBAction)editControlAction:(id)sender
{
	// get the selected button: has to be done before modifying the node/way selection
	UISegmentedControl * segmentedControl = (UISegmentedControl *) sender;
	NSInteger segment = segmentedControl.selectedSegmentIndex;

	if ( segment < _editControlActions.count ) {
		NSNumber * actionNum = _editControlActions[ segment ];
		EDIT_ACTION action = (EDIT_ACTION)actionNum.integerValue;

		// if trying to edit a node in a way that has no tags assume user wants to edit the way instead
		switch ( action ) {
			case ACTION_RECTANGULARIZE:
			case ACTION_STRAIGHTEN:
			case ACTION_REVERSE:
			case ACTION_DUPLICATE:
			case ACTION_ROTATE:
			case ACTION_CIRCULARIZE:
			case ACTION_COPYTAGS:
			case ACTION_PASTETAGS:
			case ACTION_EDITTAGS:
			case ACTION_CREATE_RELATION:
				if ( self.editorLayer.selectedWay &&
					self.editorLayer.selectedNode &&
					self.editorLayer.selectedNode.tags.count == 0 &&
					self.editorLayer.selectedWay.tags.count == 0 &&
					!self.editorLayer.selectedWay.isMultipolygonMember )
				{
					// promote the selection to the way
					self.editorLayer.selectedNode = nil;
					[self refreshPushpinText];
				}
				break;
			case ACTION_SPLIT:
			case ACTION_JOIN:
			case ACTION_DISCONNECT:
			case ACTION_RESTRICT:
			case ACTION_ADDNOTE:
			case ACTION_DELETE:
			case ACTION_MORE:
				break;
		}

		[self performEditAction:action];
	}
	segmentedControl.selectedSegmentIndex = UISegmentedControlNoSegment;
}

-(void)performEditAction:(EDIT_ACTION)action
{
	NSString * error = nil;
	switch (action) {
		case ACTION_COPYTAGS:
			if ( ! [_editorLayer copyTags:_editorLayer.selectedPrimary] )
				error = NSLocalizedString(@"The object does contain any tags",nil);
			break;
		case ACTION_PASTETAGS:
			if ( _editorLayer.selectedPrimary == nil ) {
				// pasting to brand new object, so we need to create it first
				[self setTagsForCurrentObject:@{}];
			}
			if ( _editorLayer.selectedWay && _editorLayer.selectedNode && _editorLayer.selectedWay.tags.count == 0 ) {
				// if trying to edit a node in a way that has no tags assume user wants to edit the way instead
				_editorLayer.selectedNode = nil;
				[self refreshPushpinText];
			}
            [self paste:nil];
			break;
		case ACTION_DUPLICATE:
			{
				CGPoint delta = { _crossHairs.position.x - _pushpinView.arrowPoint.x,
								  _crossHairs.position.y - _pushpinView.arrowPoint.y };
				OSMPoint offset;
				if ( hypot( delta.x, delta.y ) > 20 ) {
					// move to position of crosshairs
					CLLocationCoordinate2D p1 = [self longitudeLatitudeForScreenPoint:_pushpinView.arrowPoint birdsEye:YES];
					CLLocationCoordinate2D p2 = [self longitudeLatitudeForScreenPoint:_crossHairs.position birdsEye:YES];
					offset = OSMPointMake( p2.longitude - p1.longitude, p2.latitude - p1.latitude );
				} else {
					offset = OSMPointMake( 0.00005, -0.00005 );
				}
				OsmBaseObject * newObject = [_editorLayer duplicateObject:_editorLayer.selectedPrimary withOffset:offset];
				if ( newObject == nil ) {
					error = NSLocalizedString(@"Could not duplicate object",nil);
				} else {
					_editorLayer.selectedNode		= newObject.isNode;
					_editorLayer.selectedWay		= newObject.isWay;
					_editorLayer.selectedRelation	= newObject.isRelation;
					[self placePushpinForSelection];
				}
			}
			break;
		case ACTION_ROTATE:
			if ( _editorLayer.selectedWay == nil && !_editorLayer.selectedRelation.isMultipolygon ) {
				error = NSLocalizedString(@"Only ways/multipolygons can be rotated", nil);
			} else {
				[self startObjectRotation];
			}
			break;
		case ACTION_RECTANGULARIZE:
			{
				if ( _editorLayer.selectedWay.ident.longLongValue >= 0  &&  !OSMRectContainsRect( self.screenLongitudeLatitude, _editorLayer.selectedWay.boundingBox ) ) {
					error = NSLocalizedString(@"The selected way must be completely visible", nil);	// avoid bugs where nodes are deleted from other objects
				} else {
					EditAction rect = [_editorLayer.mapData canOrthogonalizeWay:_editorLayer.selectedWay error:&error];
					if ( rect )
						rect();
				}
			}
			break;
		case ACTION_REVERSE:
			{
				EditAction reverse = [_editorLayer.mapData canReverseWay:_editorLayer.selectedWay error:&error];
				if ( reverse )
					reverse();
			}
			break;
		case ACTION_JOIN:
			{
				EditAction join = [_editorLayer.mapData canJoinWay:_editorLayer.selectedWay atNode:_editorLayer.selectedNode error:&error];
				if ( join )
					join();
			}
			break;
		case ACTION_DISCONNECT:
			{
				EditActionReturnNode disconnect = [_editorLayer.mapData canDisconnectWay:_editorLayer.selectedWay atNode:_editorLayer.selectedNode error:&error];
				if ( disconnect ) {
					_editorLayer.selectedNode = disconnect();
					[self placePushpinForSelection];
				}
			}
			break;
		case ACTION_SPLIT:
			{
				EditActionReturnWay split = [_editorLayer.mapData canSplitWay:_editorLayer.selectedWay atNode:_editorLayer.selectedNode error:&error];
				if ( split )
					split();
			}
			break;
		case ACTION_STRAIGHTEN:
			{
				if ( _editorLayer.selectedWay.ident.longLongValue >= 0  &&  !OSMRectContainsRect( self.screenLongitudeLatitude, _editorLayer.selectedWay.boundingBox ) ) {
					error = NSLocalizedString(@"The selected way must be completely visible", nil);	// avoid bugs where nodes are deleted from other objects
				} else {
					EditAction straighten = [_editorLayer.mapData canStraightenWay:_editorLayer.selectedWay error:&error];
					if ( straighten )
						straighten();
				}
			}
			break;
		case ACTION_CIRCULARIZE:
			{
				EditAction circle = [_editorLayer.mapData canCircularizeWay:_editorLayer.selectedWay error:&error];
				if ( circle )
					circle();
			}
			break;
		case ACTION_EDITTAGS:
			[self presentTagEditor:nil];
			break;
		case ACTION_ADDNOTE:
			{
				CLLocationCoordinate2D pos = [self longitudeLatitudeForScreenPoint:_pushpinView.arrowPoint birdsEye:YES];
				OsmNote * note = [[OsmNote alloc] initWithLat:pos.latitude lon:pos.longitude];
				[self.mainViewController performSegueWithIdentifier:@"NotesSegue" sender:note];
				[self removePin];
			}
			break;
		case ACTION_DELETE:
			[self delete:nil];
			break;
		case ACTION_MORE:
			[self presentEditActionSheet:nil];
			break;
		case ACTION_RESTRICT:
			[self restrictOptionSelected];
			break;
		case ACTION_CREATE_RELATION:
			{
				void (^create)(NSString * type) = ^(NSString * type){
					OsmRelation * relation = [_editorLayer.mapData createRelation];
					NSMutableDictionary * tags = [_editorLayer.selectedPrimary.tags mutableCopy];
					if ( tags == nil )
						tags = [NSMutableDictionary new];
					tags[ @"type"] = type;
					[_editorLayer.mapData setTags:tags forObject:relation];
					[_editorLayer.mapData setTags:nil forObject:_editorLayer.selectedPrimary];

					EditAction add = [_editorLayer.mapData canAddObject:_editorLayer.selectedPrimary toRelation:relation withRole:@"outer" error:nil];
					add();
					_editorLayer.selectedNode = nil;
					_editorLayer.selectedWay = nil;
					_editorLayer.selectedRelation = relation;
					[self.editorLayer setNeedsLayout];
					[self refreshPushpinText];
					[self showAlert:NSLocalizedString(@"Adding members:",nil)
							message:NSLocalizedString(@"To add another member to the relation 'long press' on the way to be added",nil)];
				};
				UIAlertController * actionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Create Relation Type",nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
				[actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Multipolygon", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action2) {
					create(@"multipolygon");
				}]];
				[actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];

				// compute location for action sheet to originate. This will be the uppermost node in the polygon
				OSMRect box = _editorLayer.selectedPrimary.boundingBox;
				box = [MapView mapRectForLatLonRect:box];
				OSMRect rc = [self boundingScreenRectForMapRect:box];
				actionSheet.popoverPresentationController.sourceView = self;
				actionSheet.popoverPresentationController.sourceRect = CGRectFromOSMRect(rc);
				[self.mainViewController presentViewController:actionSheet animated:YES completion:nil];
				return;
			}
			break;
	}
	if ( error ) {
		[self showAlert:error message:nil];
	}

	[self.editorLayer setNeedsLayout];
	[self refreshPushpinText];
}

-(IBAction)presentTagEditor:(id)sender
{
	[self.mainViewController performSegueWithIdentifier:@"poiSegue" sender:nil];
}


// Turn restriction panel
-(void)restrictOptionSelected
{
	void (^showRestrictionEditor)(void) = ^{
		TurnRestrictController * myVc = [_mainViewController.storyboard instantiateViewControllerWithIdentifier:@"TurnRestrictController"];
		myVc.centralNode 			= self.editorLayer.selectedNode;
		myVc.parentViewCenter		= CGRectCenter(self.layer.bounds);
		myVc.screenFromMapTransform = _screenFromMapTransform;
		myVc.modalPresentationStyle = UIModalPresentationOverCurrentContext;
		[_mainViewController presentViewController:myVc animated:YES completion:nil];

		// if GPS is running don't keep moving around
		self.userOverrodeLocationPosition = YES;

		// scroll view so intersection stays visible
		CGRect rc = myVc.viewWithTitle.frame;
		int mid = rc.origin.y/2;
		CGPoint pt = self.pushpinView.arrowPoint;
		CGPoint delta = { self.bounds.size.width/2 - pt.x, mid - pt.y };
		[self adjustOriginBy:delta];
	};

	// check if this is a fancy relation type we don't support well
	void (^restrictionEditWarning)(OsmNode *) = ^(OsmNode * viaNode) {
		BOOL warn = NO;
		for ( OsmRelation * relation in viaNode.parentRelations ) {
			if ( relation.isRestriction ) {
				NSString * type = relation.tags[ @"type" ];
				if ( [type hasPrefix:@"restriction:"] || relation.tags[@"except"] ) {
					warn = YES;
				}
			}
		}
		if ( warn ) {
			UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"Unsupported turn restriction type"
																			message:@"One or more turn restrictions connected to this node have extended properties that will not be displayed.\n\n"
										 											@"Modififying these restrictions may destroy important information."
																	 preferredStyle:UIAlertControllerStyleAlert];
			[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Edit restrictions",nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * action) {
				showRestrictionEditor();
			}]];
			[alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self.mainViewController presentViewController:alert animated:YES completion:nil];
		} else {
			showRestrictionEditor();
		}
	};


	// if we currently have a relation selected then select the via node instead
	if ( self.editorLayer.selectedPrimary.isRelation ) {
		OsmRelation * relation = self.editorLayer.selectedPrimary.isRelation;
		OsmWay * fromWay = [relation memberByRole:@"from"].ref;
		OsmNode * viaNode = [relation memberByRole:@"via"].ref;
		
		if ( ![viaNode isKindOfClass:[OsmNode class]] ) {
			// not supported yet
			[self showAlert:NSLocalizedString(@"Unsupported turn restriction type",nil)
					message:NSLocalizedString(@"This app does not yet support editing turn restrictions without a node as the 'via' member",nil)];
			return;
		}
		
		self.editorLayer.selectedWay = [fromWay isKindOfClass:[OsmWay class]] ? fromWay : nil;
		self.editorLayer.selectedNode = [viaNode isKindOfClass:[OsmNode class]] ? viaNode : nil;
		if ( self.editorLayer.selectedNode ) {
			[self placePushpinForSelection];
			restrictionEditWarning( self.editorLayer.selectedNode );
		}

	} else if ( self.editorLayer.selectedPrimary.isNode ) {
		restrictionEditWarning( self.editorLayer.selectedNode );
	}
}


#if 0 // Used to clean up data corruption bug: if a node appears in a way twice consequetively remove the 2nd instance
- (void)deleteDuplicateNodes
{
	[_editorLayer.mapData enumerateObjectsUsingBlock:^(OsmBaseObject *obj) {
		OsmWay * way = obj.isWay;
		if ( way ) {
		retry:
			if ( way.hasDuplicatedNode ) {
				NSLog(@"way %@ has duplicate nodes",way.ident);
				OsmNode * prev = nil;
				NSInteger index = 0;
				for ( OsmNode * node in way.nodes ) {
					if ( node == prev ) {
						[_editorLayer.mapData deleteNodeInWay:way index:index];
						goto retry;
					}
					prev = node;
					++index;
				}
			}
		}
	}];
}
#endif


#pragma mark PushPin


#if TARGET_OS_IPHONE

-(CGPoint)pushpinPosition
{
	return _pushpinView ? _pushpinView.arrowPoint : CGPointMake(nan(""), nan(""));
}

-(OsmBaseObject *)dragConnectionForNode:(OsmNode *)node segment:(NSInteger *)segment
{
	assert( node.isNode );
	assert( _editorLayer.selectedWay );

	OsmWay * way = _editorLayer.selectedWay;

	NSArray<OsmBaseObject *> * ignoreList = nil;
	NSInteger index = [way.nodes indexOfObject:node];
	NSArray<OsmWay *> * parentWays = node.wayCount == 1 ? @[ way ] : [_editorLayer.mapData waysContainingNode:node];
	if ( way.nodes.count < 3 ) {
		ignoreList = [parentWays arrayByAddingObjectsFromArray:(id)way.nodes];
	} else if ( index == 0 ) {
		// if end-node then okay to connect to self-nodes except for adjacent
		ignoreList = [parentWays arrayByAddingObjectsFromArray:(id)@[ way.nodes[0], way.nodes[1], way.nodes[2] ]];
	} else if ( index == way.nodes.count-1 ) {
		// if end-node then okay to connect to self-nodes except for adjacent
		ignoreList = [parentWays arrayByAddingObjectsFromArray:(id)@[ way.nodes[index], way.nodes[index-1], way.nodes[index-2] ]];
	} else {
		// if middle node then never connect to self
		ignoreList = [parentWays arrayByAddingObjectsFromArray:(id)way.nodes];
	}
	OsmBaseObject * hit = [_editorLayer osmHitTest:_pushpinView.arrowPoint
											radius:DragConnectHitTestRadius
									 isDragConnect:YES
										ignoreList:ignoreList
										   segment:segment];
	return hit;
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

	_confirmDrag = NO;

	_pushpinView = [PushPinView new];
	_pushpinView.text = object ? object.friendlyDescription : NSLocalizedString(@"(new object)",nil);
	_pushpinView.layer.zPosition = Z_PUSHPIN;

	_pushpinView.arrowPoint = point;

	__weak MapView * weakSelf = self;
	if ( object ) {
		_pushpinView.dragCallback = ^(UIGestureRecognizerState state, CGFloat dx, CGFloat dy, UIGestureRecognizer * gesture ) {
			MapView * strongSelf = weakSelf;
			if ( strongSelf == nil )
				return;
			switch ( state ) {
				case UIGestureRecognizerStateBegan:
					[strongSelf.editorLayer.mapData beginUndoGrouping];
					_pushpinDragTotalMove	= CGPointMake(0,0);
					_gestureDidMove			= NO;
					break;

				case UIGestureRecognizerStateCancelled:
				case UIGestureRecognizerStateFailed:
					DLog(@"Gesture ended with cancel/fail\n");
					// fall through so we properly terminate gesture
				case UIGestureRecognizerStateEnded:
					{
						[strongSelf.editorLayer.mapData endUndoGrouping];
						[[DisplayLink shared] removeName:@"dragScroll"];

						BOOL isRotate = strongSelf->_isRotateObjectMode;
						if ( isRotate ) {
							[strongSelf endObjectRotation];
						}
						[strongSelf unblinkObject];

						if ( object.isWay ) {
							[strongSelf->_editorLayer.mapData updateParentMultipolygonRelationRolesForWay:object.isWay];
						} else if ( strongSelf.editorLayer.selectedWay && object.isNode ) {
							[strongSelf->_editorLayer.mapData updateParentMultipolygonRelationRolesForWay:strongSelf.editorLayer.selectedWay];
						}

						if ( strongSelf.editorLayer.selectedWay && object.isNode ) {
							// dragging a node that is part of a way
							OsmNode * dragNode = object.isNode;
							OsmWay  * dragWay = strongSelf.editorLayer.selectedWay;
							NSInteger segment;
							OsmBaseObject * hit = [strongSelf dragConnectionForNode:dragNode segment:&segment];
							if ( hit.isNode ) {
								// replace dragged node with hit node
								NSString * error = nil;
								EditActionReturnNode merge = [strongSelf.editorLayer.mapData canMergeNode:dragNode intoNode:hit.isNode error:&error];
								if ( merge == nil ) {
									[strongSelf showAlert:error message:nil];
									return;
								}
								hit = merge();
								if ( dragWay.isArea ) {
									strongSelf.editorLayer.selectedNode = nil;
									CGPoint pt = [strongSelf screenPointForLatitude:hit.isNode.lat longitude:hit.isNode.lon birdsEye:YES];
									[strongSelf placePushpinAtPoint:pt object:dragWay];
								} else {
									strongSelf.editorLayer.selectedNode = hit.isNode;
									[strongSelf placePushpinForSelection];
								}
							} else if ( hit.isWay ) {
								// add new node to hit way
								OSMPoint pt = [hit pointOnObjectForPoint:dragNode.location];
								[strongSelf.editorLayer.mapData setLongitude:pt.x latitude:pt.y forNode:dragNode];
								NSString * error = nil;
								EditActionWithNode add = [strongSelf.editorLayer canAddNodeToWay:hit.isWay atIndex:segment+1 error:&error];
								if ( add ) {
									add(dragNode);
								} else {
									[strongSelf showAlert:NSLocalizedString(@"Error connecting to way",nil) message:error];
								}
							}
							return;
						}
						if ( isRotate )
							break;
						if ( strongSelf.editorLayer.selectedWay && strongSelf.editorLayer.selectedWay.tags.count == 0 && strongSelf.editorLayer.selectedWay.parentRelations.count == 0 )
							break;
						if ( strongSelf.editorLayer.selectedWay && strongSelf.editorLayer.selectedNode )
							break;
						if ( strongSelf->_confirmDrag ) {
							strongSelf->_confirmDrag = NO;

							UIAlertController *	alertMove = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Confirm move",nil) message:NSLocalizedString(@"Move selected object?",nil) preferredStyle:UIAlertControllerStyleAlert];
							[alertMove addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Undo",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
								// cancel move
								[strongSelf->_editorLayer.mapData undo];
								[strongSelf->_editorLayer.mapData removeMostRecentRedo];
								strongSelf->_editorLayer.selectedNode = nil;
								strongSelf->_editorLayer.selectedWay = nil;
								strongSelf->_editorLayer.selectedRelation = nil;
								[strongSelf removePin];
								[strongSelf->_editorLayer setNeedsLayout];
							}]];
							[alertMove addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Move",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
								// okay
							}]];
							[strongSelf.mainViewController presentViewController:alertMove animated:YES completion:nil];
						}
					}
					break;
					
				case UIGestureRecognizerStateChanged:
					{
						// define the drag function
						void (^dragObject)(CGFloat dragx, CGFloat dragy) = ^(CGFloat dragx, CGFloat dragy) {
							// don't accumulate undo moves
							strongSelf->_pushpinDragTotalMove.x += dragx;
							strongSelf->_pushpinDragTotalMove.y += dragy;
							if ( strongSelf->_gestureDidMove ) {
								[strongSelf.editorLayer.mapData endUndoGrouping];
								strongSelf.silentUndo = YES;
								NSDictionary * dict = [strongSelf.editorLayer.mapData undo];
								strongSelf.silentUndo = NO;
								[strongSelf.editorLayer.mapData beginUndoGrouping];
								if ( dict ) {
									// maintain the original pin location:
									[strongSelf.editorLayer.mapData registerUndoCommentContext:dict];
								}
							}
							strongSelf->_gestureDidMove = YES;

							// move all dragged nodes
							if ( strongSelf->_isRotateObjectMode ) {
								// rotate object
								double delta = -(strongSelf->_pushpinDragTotalMove.x + strongSelf->_pushpinDragTotalMove.y) / 100;
								CGPoint axis = [strongSelf screenPointForLatitude:strongSelf->_rotateObjectCenter.y longitude:strongSelf->_rotateObjectCenter.x birdsEye:YES];
								for ( OsmNode * node in object.isNode ? strongSelf.editorLayer.selectedWay.nodeSet : object.nodeSet ) {
									CGPoint pt = [strongSelf screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
									OSMPoint diff = { pt.x - axis.x, pt.y - axis.y };
									double radius = hypot( diff.x, diff.y );
									double angle = atan2( diff.y, diff.x );
									angle += delta;
									OSMPoint new = { axis.x + radius * cos(angle), axis.y + radius * sin(angle) };
									CGPoint dist = { new.x - pt.x, -(new.y - pt.y) };
									[strongSelf.editorLayer adjustNode:node byDistance:dist];
								}

							} else {
								// drag object
								CGPoint delta = { strongSelf->_pushpinDragTotalMove.x, -strongSelf->_pushpinDragTotalMove.y };
								for ( OsmNode * node in object.nodeSet ) {
									[strongSelf.editorLayer adjustNode:node byDistance:delta];
								}
							}

							// do hit testing for connecting to other objects
							if ( strongSelf.editorLayer.selectedWay && object.isNode ) {
								NSInteger segment;
								OsmBaseObject * hit = [strongSelf dragConnectionForNode:(id)object segment:&segment];
								if ( hit.isWay || hit.isNode ) {
									[strongSelf blinkObject:hit segment:segment];
								} else {
									[strongSelf unblinkObject];
								}
							}
						};

						// scroll screen if too close to edge
						const CGFloat MinDistanceSide = 40.0;
						const CGFloat MinDistanceTop = MinDistanceSide + 10.0;
						const CGFloat MinDistanceBottom = MinDistanceSide + 120.0;
						CGPoint arrow = strongSelf.pushpinView.arrowPoint;
						CGRect screen = strongSelf.bounds;
						const CGFloat SCROLL_SPEED = 10.0;
						CGFloat scrollx = 0, scrolly = 0;

						if ( arrow.x < screen.origin.x + MinDistanceSide )
							scrollx = -SCROLL_SPEED;
						else if ( arrow.x > screen.origin.x + screen.size.width - MinDistanceSide )
							scrollx = SCROLL_SPEED;
						if ( arrow.y < screen.origin.y + MinDistanceTop )
							scrolly = -SCROLL_SPEED;
						else if ( arrow.y > screen.origin.y + screen.size.height - MinDistanceBottom )
							scrolly = SCROLL_SPEED;

						if ( scrollx || scrolly ) {

							// if we're dragging at a diagonal then scroll diagonally as well, in the direction the user is dragging
							CGPoint center = CGRectCenter(strongSelf.bounds);
							OSMPoint v = UnitVector(Sub(OSMPointFromCGPoint(arrow),OSMPointFromCGPoint(center)));
							scrollx = SCROLL_SPEED * v.x;
							scrolly = SCROLL_SPEED * v.y;

							// scroll the screen to keep pushpin centered
							DisplayLink * displayLink = [DisplayLink shared];
							__block NSTimeInterval prevTime = CACurrentMediaTime();
							[displayLink addName:@"dragScroll" block:^{
								NSTimeInterval now = CACurrentMediaTime();
								NSTimeInterval duration = now - prevTime;
								prevTime = now;
								CGFloat sx = scrollx * duration * 60.0;	// scale to 60 FPS assumption, need to move farther if framerate is slow
								CGFloat sy = scrolly * duration * 60.0;
								[strongSelf adjustOriginBy:CGPointMake(-sx,-sy)];
								dragObject( sx, sy );
								// update position of pushpin
								CGPoint pt = CGPointWithOffset( weakSelf.pushpinView.arrowPoint, sx, sy );
								strongSelf.pushpinView.arrowPoint = pt;
								// update position of blink layer
								pt = CGPointWithOffset( _blinkLayer.position, -sx, -sy );
								strongSelf->_blinkLayer.position = pt;
							}];
						} else {
							[[DisplayLink shared] removeName:@"dragScroll"];
						}

						// move the object
						dragObject( dx, dy );
					}
					break;
				default:
					break;
			}
		};
	}

	[self updateEditControl];

	if ( object == nil ) {
		CALayer * layer = _pushpinView.placeholderLayer;
		if ( layer.sublayers.count == 0 ) {
#if 0
			layer.contents			= (id)[UIImage imageNamed:@"new_object"].CGImage;
			layer.contentsScale 	= UIScreen.mainScreen.scale;
			layer.bounds        	= CGRectMake(0, 0, 20, 20);
#else
			layer.bounds        	= CGRectMake(0, 0, 24, 24);
			layer.cornerRadius  	= layer.bounds.size.width/2;
			layer.backgroundColor	= [UIColor colorWithRed:0.0 green:150/255.0 blue:1.0 alpha:1.0].CGColor;
			layer.masksToBounds   	= YES;
			layer.borderColor	 	= UIColor.whiteColor.CGColor;
			layer.borderWidth	 	= 1.0;
			layer.contentsScale 	= UIScreen.mainScreen.scale;
			// shadow
			layer.shadowColor		= UIColor.blackColor.CGColor;
			layer.shadowOffset		= CGSizeMake(3,3);
			layer.shadowRadius		= 3;
			layer.shadowOpacity		= 0.5;
			layer.masksToBounds		= NO;

			CATextLayer * text = [CATextLayer new];
			text.foregroundColor	= UIColor.whiteColor.CGColor;
			text.foregroundColor	= [UIColor colorWithRed:0 green:0 blue:0.5 alpha:1.0].CGColor;
			text.foregroundColor	= UIColor.whiteColor.CGColor;
			text.string				= @"?";
			text.fontSize			= 18;
			text.font				= (__bridge CFTypeRef)[UIFont boldSystemFontOfSize:text.fontSize];
			text.alignmentMode		= kCAAlignmentCenter;
			text.bounds				= layer.bounds;
			text.position			= CGPointMake(0,1);
			text.anchorPoint		= CGPointZero;
			text.contentsScale 		= UIScreen.mainScreen.scale;
			[layer addSublayer:text];
#endif
		}
	}
	
	[self addSubview:_pushpinView];

	if ( object == nil ) {
		// do animation if creating a new object
		[_pushpinView animateMoveFrom:CGPointMake(self.bounds.origin.x+self.bounds.size.width,self.bounds.origin.y)];
	}
}

- (void)refreshPushpinText
{
	NSString * text = _editorLayer.selectedPrimary.friendlyDescription;
	text = text ?: NSLocalizedString(@"(new object)",nil);
	_pushpinView.text = text;
}

-(void)extendSelectedWayToPoint:(CGPoint)newPoint
{
	if ( !_pushpinView )
		return;
	OsmWay * way = _editorLayer.selectedWay;
	OsmNode * node = _editorLayer.selectedNode;
	CGPoint arrowPoint = _pushpinView.arrowPoint;

	if ( way && !node ) {
		// insert a new node into way at point
		CLLocationCoordinate2D pt = [self longitudeLatitudeForScreenPoint:arrowPoint birdsEye:YES];
		OSMPoint pt2 = { pt.longitude, pt.latitude };
		NSInteger segment = [way segmentClosestToPoint:pt2];
		NSString * error = nil;
		EditActionWithNode add = [_editorLayer canAddNodeToWay:way atIndex:segment+1 error:&error];
		if ( add ) {
			OsmNode * newNode = [_editorLayer createNodeAtPoint:arrowPoint];
			add(newNode);
			_editorLayer.selectedNode = newNode;
			[self placePushpinForSelection];
		} else {
			[self showAlert:NSLocalizedString(@"Error",nil) message:error];
		}

	} else {

		if ( node && way && way.nodes.count && (way.isClosed || (node != way.nodes[0] && node != way.nodes.lastObject)) ) {
			// both a node and way are selected but selected node is not an endpoint (or way is closed), so we will create a new way from that node
			way = [_editorLayer createWayWithNode:node];
		} else {
			if ( node == nil ) {
				node = [_editorLayer createNodeAtPoint:arrowPoint];
			}
			if ( way == nil ) {
				way = [_editorLayer createWayWithNode:node];
			}
		}
		NSInteger prevIndex = [way.nodes indexOfObject:node];
		NSInteger nextIndex = prevIndex;
		if ( nextIndex == way.nodes.count - 1 )
			++nextIndex;
		// add new node at point
		OsmNode * prevPrevNode = way.nodes.count >= 2 ? way.nodes[way.nodes.count-2] : nil;
		CGPoint prevPrevPoint = prevPrevNode ? [self screenPointForLatitude:prevPrevNode.lat longitude:prevPrevNode.lon birdsEye:YES] : CGPointMake(0,0);

		if ( hypot( arrowPoint.x-newPoint.x, arrowPoint.y-newPoint.y) > 10.0 &&
			(prevPrevNode==nil || hypot( prevPrevPoint.x-newPoint.x, prevPrevPoint.y-newPoint.y) > 10.0 ) )
		{
			// it's far enough from previous point to use
		} else {

			// compute a good place for next point
			if ( way.nodes.count < 2 ) {
				// create 2nd point in the direction of the center of the screen
				BOOL vert = fabs(arrowPoint.x - newPoint.x) < fabs(arrowPoint.y - newPoint.y);
				if ( vert ) {
					newPoint.x = arrowPoint.x;
					newPoint.y = fabs(newPoint.y-arrowPoint.y) < 30 ? arrowPoint.y + 60 : 2*newPoint.y - arrowPoint.y;
				} else {
					newPoint.x = fabs(newPoint.x-arrowPoint.x) < 30 ? arrowPoint.x + 60 : 2*newPoint.x - arrowPoint.x;
					newPoint.y = arrowPoint.y;
				}
			} else if ( way.nodes.count == 2 ) {
				// create 3rd point 90 degrees from first 2
				OsmNode * n1 = way.nodes[1-prevIndex];
				CGPoint p1 = [self screenPointForLatitude:n1.lat longitude:n1.lon birdsEye:YES];
				CGPoint delta = { p1.x - arrowPoint.x, p1.y - arrowPoint.y };
				double len = hypot( delta.x, delta.y );
				if ( len > 100 ) {
					delta.x *= 100/len;
					delta.y *= 100/len;
				}
				OSMPoint np1 = { arrowPoint.x - delta.y, arrowPoint.y + delta.x };
				OSMPoint np2 = { arrowPoint.x + delta.y, arrowPoint.y - delta.x };
				if ( DistanceFromPointToPoint(np1, OSMPointFromCGPoint(newPoint)) < DistanceFromPointToPoint(np2, OSMPointFromCGPoint(newPoint)) )
					newPoint = CGPointMake(np1.x,np1.y);
				else
					newPoint = CGPointMake(np2.x, np2.y);
			} else {
				// create 4th point and beyond following angle of previous 3
				OsmNode * n1 = prevIndex == 0 ? way.nodes[1] : way.nodes[prevIndex-1];
				OsmNode * n2 = prevIndex == 0 ? way.nodes[2] : way.nodes[prevIndex-2];
				CGPoint p1 = [self screenPointForLatitude:n1.lat longitude:n1.lon birdsEye:YES];
				CGPoint p2 = [self screenPointForLatitude:n2.lat longitude:n2.lon birdsEye:YES];
				OSMPoint d1 = { arrowPoint.x - p1.x, arrowPoint.y - p1.y };
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
				newPoint = CGPointMake( arrowPoint.x + dist*cos(a1), arrowPoint.y + dist*sin(a1) );
			}
			// make sure selected point is on-screen
			CGRect rc = self.bounds;
			rc.origin.x += 20;
			rc.origin.y += 20;
			rc.size.width -= 40;
			rc.size.height -= 190+20;
			newPoint.x = MAX( newPoint.x, rc.origin.x );
			newPoint.x = MIN( newPoint.x, rc.origin.x+rc.size.width);
			newPoint.y = MAX( newPoint.y, rc.origin.y );
			newPoint.y = MIN( newPoint.y, rc.origin.y+rc.size.height);
		}

		if ( way.nodes.count >= 2 ) {
			OsmNode * start = prevIndex == 0 ? way.nodes.lastObject : way.nodes[0];
			CGPoint s = [self screenPointForLatitude:start.lat longitude:start.lon birdsEye:YES];
			double d = hypot( s.x - newPoint.x, s.y - newPoint.y );
			if ( d < 3.0 ) {
				// join first to last
				NSString * error = nil;
				EditActionWithNode action = [_editorLayer canAddNodeToWay:way atIndex:nextIndex error:&error];
				if ( action ) {
					action(start);
					_editorLayer.selectedWay = way;
					_editorLayer.selectedNode = nil;
					[self placePushpinAtPoint:s object:way];
				} else {
					// don't bother showing an error message
				}
				return;
			}
		}


		NSString * error = nil;
		EditActionWithNode addNodeToWay = [_editorLayer canAddNodeToWay:way atIndex:nextIndex error:&error];
		if ( !addNodeToWay ) {
			[self showAlert:NSLocalizedString(@"Can't extend way",nil) message:error];
			return;
		}
		OsmNode * node2 = [_editorLayer createNodeAtPoint:newPoint];
		_editorLayer.selectedWay = way;		// set selection before perfoming add-node action so selection is recorded in undo stack
		_editorLayer.selectedNode = node2;
		addNodeToWay( node2 );
		[self placePushpinForSelection];
	}
}
#endif

-(void)dropPinAtPoint:(CGPoint)dropPoint
{
	if ( _editorLayer.hidden ) {
		[self flashMessage:NSLocalizedString(@"Editing layer not visible",nil)];
		return;
	}
	if ( _pushpinView ) {

		BOOL (^offscreenWarning)(void) = ^{
			if ( !CGRectContainsPoint( self.bounds, _pushpinView.arrowPoint ) ) {
				// pushpin is off screen
				[self flashMessage:NSLocalizedString(@"Selected object is off screen",nil)];
				return YES;
			} else {
				return NO;
			}
		};
		
		if ( _editorLayer.selectedWay && _editorLayer.selectedNode ) {
			// already editing a way so try to extend it
			NSInteger index = [_editorLayer.selectedWay.nodes indexOfObject:_editorLayer.selectedNode];
			if ( (_editorLayer.selectedWay.isClosed || !(index == 0 || index == _editorLayer.selectedWay.nodes.count-1)) && offscreenWarning() )
				return;
			[self extendSelectedWayToPoint:dropPoint];
		} else if ( _editorLayer.selectedPrimary == nil && _pushpinView ) {
			// just dropped a pin, so convert it into a way
			[self extendSelectedWayToPoint:dropPoint];
		} else if ( _editorLayer.selectedWay && _editorLayer.selectedNode == nil ) {
			// add a new node to a way at location of pushpin
			if ( offscreenWarning() )
				return;
			[self extendSelectedWayToPoint:dropPoint];
		} else if ( _editorLayer.selectedPrimary.isNode ) {
			// nothing selected, or just a single node selected, so drop a new pin
			goto drop_pin;
		}

	} else {

	drop_pin:
		// drop a new pin

		// remove current selection
		_editorLayer.selectedNode = nil;
		_editorLayer.selectedWay = nil;
		_editorLayer.selectedRelation = nil;

		[self placePushpinAtPoint:dropPoint object:nil];
	}
}

- (void)setTagsForCurrentObject:(NSDictionary *)tags
{
	if ( _editorLayer.selectedPrimary == nil ) {
		// create new object
		assert( _pushpinView );
		CGPoint point = _pushpinView.arrowPoint;
		OsmNode * node = [_editorLayer createNodeAtPoint:point];
		[_editorLayer.mapData setTags:tags forObject:node];
		_editorLayer.selectedNode = node;
		// create new pushpin for new object
		[self placePushpinForSelection];
	} else {
		// update current object
		OsmBaseObject * object = _editorLayer.selectedPrimary;
		[_editorLayer.mapData setTags:tags forObject:object];
		[self refreshPushpinText];
		[self refreshNoteButtonsFromDatabase];
	}
	[_editorLayer setNeedsLayout];
	_confirmDrag = NO;
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
	CGMutablePathRef path = CGPathCreateMutable();
	if ( object.isNode ) {
		OsmNode * node = (id)object;
		CGPoint center = [self screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
		CGRect rect = CGRectMake(center.x, center.y, 0, 0);
		rect = CGRectInset( rect, -10, -10 );
		CGPathAddEllipseInRect(path, NULL, rect);
	} else if ( object.isWay ) {
		OsmWay * way = (id)object;
		assert( way.nodes.count >= segment+2 );
		OsmNode * n1 = way.nodes[segment];
		OsmNode * n2 = way.nodes[segment+1];
		CGPoint p1 = [self screenPointForLatitude:n1.lat longitude:n1.lon birdsEye:YES];
		CGPoint p2 = [self screenPointForLatitude:n2.lat longitude:n2.lon birdsEye:YES];
		CGPathMoveToPoint(path, NULL, p1.x, p1.y);
		CGPathAddLineToPoint(path, NULL, p2.x, p2.y);
	} else {
		assert(NO);
	}
	_blinkLayer = [CAShapeLayer layer];
	_blinkLayer.path 		= path;
	_blinkLayer.fillColor	= nil;
	_blinkLayer.lineWidth	= 3.0;
	_blinkLayer.frame		= CGRectMake( 0, 0, self.bounds.size.width, self.bounds.size.height );
	_blinkLayer.zPosition	= Z_BLINK;
	_blinkLayer.strokeColor	= NSColor.blackColor.CGColor;

	CAShapeLayer * dots = [CAShapeLayer layer];
	dots.path 				= _blinkLayer.path;
	dots.fillColor			= nil;
	dots.lineWidth			= _blinkLayer.lineWidth;
	dots.bounds				= _blinkLayer.bounds;
	dots.position			= CGPointZero;
	dots.anchorPoint		= CGPointZero;
	dots.strokeColor		= NSColor.whiteColor.CGColor;
	dots.lineDashPhase 		= 0.0;
	dots.lineDashPattern 	= @[ @(4), @(4) ];
	[_blinkLayer addSublayer:dots];

	CABasicAnimation * dashAnimation = [CABasicAnimation animationWithKeyPath:@"lineDashPhase"];
	dashAnimation.fromValue		= @(0.0);
	dashAnimation.toValue		= @(-16.0);
	dashAnimation.duration		= 0.6;
	dashAnimation.repeatCount	= CGFLOAT_MAX;
	[dots addAnimation:dashAnimation forKey:@"linePhase"];
	CGPathRelease(path);

	[self.layer addSublayer:_blinkLayer];
}



#pragma mark Notes

-(void)updateNotesFromServerWithDelay:(CGFloat)delay
{
	if ( _viewOverlayMask & VIEW_OVERLAY_NOTES ) {
		OSMRect rc = [self screenLongitudeLatitude];
		[_notesDatabase updateRegion:rc withDelay:delay fixmeData:self.editorLayer.mapData completion:^{
			[self refreshNoteButtonsFromDatabase];
		}];
	} else {
		[self refreshNoteButtonsFromDatabase];
	}
}

-(void)refreshNoteButtonsFromDatabase
{
	dispatch_async(dispatch_get_main_queue(), ^{	// need this to disable implicit animation

		[UIView performWithoutAnimation:^{
			// if a button is no longer in the notes database then it got resolved and can go away
			NSMutableArray * remove = [NSMutableArray new];
			for ( NSNumber * tag in _notesViewDict ) {
				if ( [_notesDatabase noteForTag:tag.integerValue] == nil ) {
					[remove addObject:tag];
				}
			}
			for ( NSNumber * tag in remove ) {
				UIButton * button = _notesViewDict[tag];
				[_notesViewDict removeObjectForKey:tag];
				[button removeFromSuperview];
			}
			
			// update new and existing buttons
			[_notesDatabase enumerateNotes:^(OsmNote *note) {
				UIButton * button = _notesViewDict[ @(note.tagId) ];
				if ( _viewOverlayMask & VIEW_OVERLAY_NOTES ) {

					// hide unwanted keep right buttons
					if ( note.isKeepRight && [_notesDatabase isIgnored:note] ) {
						[button removeFromSuperview];
						return;
					}

					if ( button == nil ) {
						button = [UIButton buttonWithType:UIButtonTypeCustom];
						[button addTarget:self action:@selector(noteButtonPress:) forControlEvents:UIControlEventTouchUpInside];
						button.bounds					= CGRectMake(0, 0, 20, 20);
						button.layer.cornerRadius		= 5;
						button.layer.backgroundColor	= UIColor.blueColor.CGColor;
						button.layer.borderColor		= UIColor.whiteColor.CGColor;
						button.titleLabel.font			= [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
						button.titleLabel.textColor		= UIColor.whiteColor;
						button.titleLabel.textAlignment	= NSTextAlignmentCenter;
						NSString * title = note.isFixme ? @"F" : note.isWaypoint ? @"W" : note.isKeepRight ? @"R" : @"N";
						[button setTitle:title forState:UIControlStateNormal];
						button.tag = note.tagId;
						[self addSubview:button];
						[_notesViewDict setObject:button forKey:@(note.tagId)];
					}

					if ( [note.status isEqualToString:@"closed"] ) {
						[button removeFromSuperview];
					} else if ( note.isFixme && [self.editorLayer.mapData objectWithExtendedIdentifier:note.noteId].tags[@"fixme"] == nil ) {
						[button removeFromSuperview];
					} else {
						double offsetX = note.isKeepRight || note.isFixme ? 0.00001 : 0.0;
						CGPoint pos = [self screenPointForLatitude:note.lat longitude:note.lon+offsetX birdsEye:YES];
						if ( isinf(pos.x) || isinf(pos.y) )
							return;

						CGRect rc = button.bounds;
						rc = CGRectOffset( rc, pos.x-rc.size.width/2, pos.y-rc.size.height/2 );
						button.frame = rc;
					}
				} else {
					[button removeFromSuperview];
					[_notesViewDict removeObjectForKey:@(note.tagId)];
				}
			}];
		}];

		if ( (_viewOverlayMask & VIEW_OVERLAY_NOTES) == 0 ) {
			[_notesDatabase reset];
		}
	});
}

-(void)noteButtonPress:(id)sender
{
	UIButton * button = sender;
	OsmNote * note = [_notesDatabase noteForTag:button.tag];
	if ( note == nil )
		return;

	if ( note.isWaypoint || note.isKeepRight ) {
		if ( !_editorLayer.hidden ) {
			OsmBaseObject * object = [_editorLayer.mapData objectWithExtendedIdentifier:note.noteId];
			if ( object ) {
				_editorLayer.selectedNode		= object.isNode;
				_editorLayer.selectedWay		= object.isWay;
				_editorLayer.selectedRelation	= object.isRelation;

				OSMPoint pt = [object pointOnObjectForPoint:OSMPointMake(note.lon, note.lat)];
				CGPoint point = [self screenPointForLatitude:pt.y longitude:pt.x birdsEye:YES];
				[self placePushpinAtPoint:point object:object];
			}
		}
		OsmNoteComment * comment = note.comments.lastObject;
		NSString * title = note.isWaypoint ? @"Waypoint" : @"Keep Right";

		// use regular alertview
		NSString * text = comment.text;
		NSRange r1 = [text rangeOfString:@"<a "];
		if ( r1.length > 0 ) {
			NSRange r2 = [text rangeOfString:@"\">"];
			if ( r2.length > 0 ) {
				text = [text stringByReplacingCharactersInRange:NSMakeRange(r1.location,r2.location+r2.length-r1.location) withString:@""];
				text = [text stringByReplacingOccurrencesOfString:@"</a>" withString:@""];
			}
		}
		text = [text stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];

		UIAlertController * alertKeepRight = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
		[alertKeepRight addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil)	  style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
		[alertKeepRight addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			// they want to hide this button from now on
			[_notesDatabase ignoreNote:note];
			[self refreshNoteButtonsFromDatabase];
			_editorLayer.selectedNode = nil;
			_editorLayer.selectedWay = nil;
			_editorLayer.selectedRelation = nil;
			[self removePin];
 		}]];
		[self.mainViewController presentViewController:alertKeepRight animated:YES completion:nil];

	} else if ( note.isFixme ) {
		OsmBaseObject * object = [_editorLayer.mapData objectWithExtendedIdentifier:note.noteId];
		_editorLayer.selectedNode		= object.isNode;
		_editorLayer.selectedWay		= object.isWay;
		_editorLayer.selectedRelation	= object.isRelation;
		[self presentTagEditor:nil];
	} else {
		[self.mainViewController performSegueWithIdentifier:@"NotesSegue" sender:note];
	}
}

#pragma mark Gestures


#if TARGET_OS_IPHONE

static NSString * const DisplayLinkPanning	= @"Panning";

// disable gestures inside toolbar buttons
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
	// http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer
	UIView * view = touch.view;
	while ( view ) {
		if ( [view isKindOfClass:[UIControl class]] || [view isKindOfClass:[UIToolbar class]] )
			break;
		view = view.superview;
	}
	if ( view ) {
		// we touched a button, slider, or other UIControl
		if ( gestureRecognizer == _addNodeButtonLongPressGestureRecognizer ) {
			return YES;
		}
		return NO; // ignore the touch
	}

	return YES; // handle the touch
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
	if ( gestureRecognizer == _addNodeButtonLongPressGestureRecognizer || otherGestureRecognizer == _addNodeButtonLongPressGestureRecognizer )
		return YES;	// if holding down the + button then always allow other gestures to proceeed
	if ( [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]] || [otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]] )
		return NO;	// don't register long-press when other gestures are occuring
	if ( [gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] || [otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]] )
		return NO;	// don't register taps during panning/zooming/rotating
	return YES;	// allow other things so we can pan/zoom/rotate simultaneously
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)pan
{
	self.userOverrodeLocationPosition = YES;

	if ( pan.state == UIGestureRecognizerStateBegan ) {
		// start pan
		DisplayLink * displayLink = [DisplayLink shared];
		[displayLink removeName:DisplayLinkPanning];
	} else if ( pan.state == UIGestureRecognizerStateChanged ) {
		// move pan
#if SHOW_3D
		// multi-finger drag to initiate 3-D view
		if ( self.enableBirdsEye && pan.numberOfTouches == 3 ) {
			CGPoint translation = [pan translationInView:self];
			double delta = -translation.y/40 / 180 * M_PI;
			[self rotateBirdsEyeBy:delta];
			return;
		}
#endif
		CGPoint translation = [pan translationInView:self];
		[self adjustOriginBy:translation];
		[pan setTranslation:CGPointMake(0,0) inView:self];
	} else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled ) {	// cancelled occurs when we throw an error dialog
		double duration = 0.5;

		// finish pan with inertia
		CGPoint initialVelecity = [pan velocityInView:self];
		if ( hypot(initialVelecity.x,initialVelecity.y) < 100.0 ) {
			// don't use inertia for small movements because it interferes with dropping the pin precisely
		} else {
			CFTimeInterval startTime = CACurrentMediaTime();
			__weak MapView * weakSelf = self;
			__weak DisplayLink * displayLink = [DisplayLink shared];
			[displayLink addName:DisplayLinkPanning block:^{
				MapView * myself = weakSelf;
				if ( myself ) {
					double timeOffset = CACurrentMediaTime() - startTime;
					if ( timeOffset >= duration ) {
						[displayLink removeName:DisplayLinkPanning];
					} else {
						CGPoint translation;
						double t = timeOffset / duration;	// time [0..1]
						translation.x = (1-t) * initialVelecity.x * displayLink.duration;
						translation.y = (1-t) * initialVelecity.y * displayLink.duration;
						[myself adjustOriginBy:translation];
					}
				}
			}];
		}
		[self updateNotesFromServerWithDelay:duration];
	} else if ( pan.state == UIGestureRecognizerStateFailed ) {
		DLog( @"pan gesture failed" );
	} else {
		DLog( @"pan gesture %d", (int)pan.state);
	}
}
- (void)handlePinchGesture:(UIPinchGestureRecognizer *)pinch
{
	if ( pinch.state == UIGestureRecognizerStateChanged ) {

		if ( isnan(pinch.scale) )
			return;

		self.userOverrodeLocationZoom = YES;

		DisplayLink * displayLink = [DisplayLink shared];
		[displayLink removeName:DisplayLinkPanning];

		CGPoint zoomCenter = [pinch locationInView:self];
		[self adjustZoomBy:pinch.scale aroundScreenPoint:zoomCenter];

		[pinch setScale:1.0];
	} else if ( pinch.state == UIGestureRecognizerStateEnded ) {
		[self updateNotesFromServerWithDelay:0];
	}
}
- (void)handleTapAndDragGesture:(TapAndDragGesture *)tapAndDrag
{
	// do single-finger zooming
	if ( tapAndDrag.state == UIGestureRecognizerStateChanged ) {
		self.userOverrodeLocationZoom = YES;

		DisplayLink * displayLink = [DisplayLink shared];
		[displayLink removeName:DisplayLinkPanning];

		CGPoint delta = [tapAndDrag translationInView:self];
		double scale = 1 + delta.y * 0.01;
		CGPoint zoomCenter = CGRectCenter( [self bounds] );
		[self adjustZoomBy:scale aroundScreenPoint:zoomCenter];

	} else if ( tapAndDrag.state == UIGestureRecognizerStateEnded ) {
		[self updateNotesFromServerWithDelay:0];
	}
}
- (IBAction)handleTapGesture:(UITapGestureRecognizer *)tap
{
	if ( tap.state == UIGestureRecognizerStateEnded ) {
		CGPoint point = [tap locationInView:self];
		if ( _addNodeButtonTimestamp ) {
			[self dropPinAtPoint:point];
		} else {
			[self singleClick:point];
		}
	}
}

-(void)addNodeButtonLongPressHandler:(UILongPressGestureRecognizer *)recognizer
{
	switch ( recognizer.state ) {
		case UIGestureRecognizerStateBegan:
			_addNodeButtonTimestamp = CACurrentMediaTime();
			break;
		case UIGestureRecognizerStateEnded:
			if ( CACurrentMediaTime() - _addNodeButtonTimestamp < 0.5 ) {
				// treat as tap
				CGPoint point = _crossHairs.position;
				[self dropPinAtPoint:point];
			}
			_addNodeButtonTimestamp = 0.0;
			break;
		case UIGestureRecognizerStateCancelled:
		case UIGestureRecognizerStateFailed:
			_addNodeButtonTimestamp = 0.0;
			break;
		default:
			break;
	}
}

// long press on map allows selection of various objects near the location
- (IBAction)handleLongPressGesture:(UILongPressGestureRecognizer *)longPress
{
	if ( longPress.state == UIGestureRecognizerStateBegan && !_editorLayer.hidden ) {
		CGPoint point = [longPress locationInView:self];

		NSArray<OsmBaseObject *> * objects = [self.editorLayer osmHitTestMultiple:point radius:DefaultHitTestRadius];
		if ( objects.count == 0 )
			return;

		// special case for adding members to relations:
		if ( _editorLayer.selectedPrimary.isRelation.isMultipolygon ) {
			NSArray<OsmBaseObject *> * ways = [objects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OsmBaseObject * obj, id bindings) {
				return obj.isWay != nil;
			}]];
			if ( ways.count == 1 ) {
				UIAlertController * confirm = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Add way to multipolygon?",nil) message:nil preferredStyle:UIAlertControllerStyleAlert];
				void (^addMmember)(NSString *) = ^(NSString * role) {
					NSString * error = nil;
					EditAction add = [_editorLayer.mapData canAddObject:ways.lastObject toRelation:_editorLayer.selectedRelation withRole:role error:&error];
					if ( add ) {
						add();
						[self flashMessage:NSLocalizedString(@"added to multipolygon relation",nil)];
						[_editorLayer setNeedsLayout];
					} else {
						[self showAlert:NSLocalizedString(@"Error",nil) message:error];
					}
				};
				[confirm addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Add outer member",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
					addMmember(@"outer");
				}]];
				[confirm addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Add inner member",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
					addMmember(@"inner");
				}]];
				[confirm addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
				[self.mainViewController presentViewController:confirm animated:YES completion:nil];
			}
			return;
		}

		UIAlertController * multiSelectSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Object",nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		for ( OsmBaseObject * object in objects ) {
			NSString * title = object.friendlyDescription;
			if ( ![title hasPrefix:@"("] ) {
				// indicate what type of object it is
				if ( object.isNode )
					title = [title stringByAppendingString:NSLocalizedString(@" (node)",@"")];
				else if ( object.isWay )
					title = [title stringByAppendingString:NSLocalizedString(@" (way)",nil)];
				else if ( object.isRelation ) {
					NSString * type = object.tags[@"type"] ?: NSLocalizedString(@"relation",nil);
					title = [title stringByAppendingFormat:@" (%@)",type];
				}
			}
			[multiSelectSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
				// processing for selecting one of multipe objects
				[_editorLayer setSelectedNode:nil];
				[_editorLayer setSelectedWay:nil];
				[_editorLayer setSelectedRelation:nil];
				if ( object.isNode ) {
					for ( OsmBaseObject * obj in objects ) {
						if ( obj.isWay && [obj.isWay.nodes containsObject:(id)object] ) {
							// select the way containing the node, then select the node in the way
							[_editorLayer setSelectedWay:obj.isWay];
							break;
						}
					}
					[_editorLayer setSelectedNode:object.isNode];
				} else if ( object.isWay ) {
					[_editorLayer setSelectedWay:object.isWay];
				} else if ( object.isRelation ) {
					[_editorLayer setSelectedRelation:object.isRelation];
				}
				CGPoint pos = [self pointOnObject:object forPoint:point];
				[self placePushpinAtPoint:pos object:object];
			}]];
		}
		[multiSelectSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
		[self.mainViewController presentViewController:multiSelectSheet animated:YES completion:nil];
		// set position
		CGRect rc = { point.x, point.y, 0, 0 };
		multiSelectSheet.popoverPresentationController.sourceView = self;
		multiSelectSheet.popoverPresentationController.sourceRect = rc;
	}
}

- (IBAction)handleRotationGesture:(UIRotationGestureRecognizer *)rotationGesture
{
	if ( _isRotateObjectMode ) {
		// Rotate object on screen
		if ( rotationGesture.state == UIGestureRecognizerStateBegan ) {
			[_editorLayer.mapData beginUndoGrouping];
			_gestureDidMove = NO;
		} else if ( rotationGesture.state == UIGestureRecognizerStateChanged ) {
			if ( _gestureDidMove ) {
				// don't allows undo list to accumulate
				[_editorLayer.mapData endUndoGrouping];
				self.silentUndo = YES;
				[_editorLayer.mapData undo];
				self.silentUndo = NO;
				[_editorLayer.mapData beginUndoGrouping];
			}
			_gestureDidMove = YES;

			CGFloat delta = rotationGesture.rotation;
			CGPoint	axis = [self screenPointForLatitude:_rotateObjectCenter.y longitude:_rotateObjectCenter.x birdsEye:YES];
			OsmBaseObject * rotatedObject = _editorLayer.selectedRelation ?: _editorLayer.selectedWay;
			for ( OsmNode * node in rotatedObject.nodeSet ) {
				CGPoint pt = [self screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
				OSMPoint diff = { pt.x - axis.x, pt.y - axis.y };
				double radius = hypot( diff.x, diff.y );
				double angle = atan2( diff.y, diff.x );
				angle += delta;
				OSMPoint new = { axis.x + radius * cos(angle), axis.y + radius * sin(angle) };
				CGPoint dist = { new.x - pt.x, -(new.y - pt.y) };
				[_editorLayer adjustNode:node byDistance:dist];
			}
		} else {
			// ended
			[self endObjectRotation];
			[_editorLayer.mapData endUndoGrouping];
		}
		return;
	}

	// Rotate screen
	if ( self.enableRotation ) {
		if ( rotationGesture.state == UIGestureRecognizerStateBegan ) {
			// ignore
		} else if ( rotationGesture.state == UIGestureRecognizerStateChanged ) {
			CGPoint centerPoint = [rotationGesture locationInView:self];
			CGFloat angle = rotationGesture.rotation;
			[self rotateBy:angle aroundScreenPoint:centerPoint];
			rotationGesture.rotation = 0.0;
			
			if ( _gpsState == GPS_STATE_HEADING ) {
				_gpsState = GPS_STATE_LOCATION;
			}
		} else if ( rotationGesture.state == UIGestureRecognizerStateEnded ) {
			[self updateNotesFromServerWithDelay:0];
		}
	}
}


- (void)updateSpeechBalloonPosition
{
}
#endif


#pragma mark Mouse movment

- (void)handleScrollWheelGesture:(UIPanGestureRecognizer *)pan
{
	if ( pan.state == UIGestureRecognizerStateChanged ) {
		CGPoint delta 	= [pan translationInView:self];
		CGPoint center 	= [pan locationInView:self];
		center.y -= delta.y;
		CGFloat zoom = delta.y >= 0 ? (1000 + delta.y) / 1000 : 1000/(1000-delta.y);
		[self adjustZoomBy:zoom aroundScreenPoint:center];
	}
}

- (void)singleClick:(CGPoint)point
{
	OsmBaseObject * hit = nil;

	// disable rotation if in action
	if ( _isRotateObjectMode ) {
		[self endObjectRotation];
	}


	if ( _editorLayer.selectedWay ) {
		// check for selecting node inside way
		hit = [_editorLayer osmHitTestNodeInSelectedWay:point radius:DefaultHitTestRadius];
	}
	if ( hit ) {
		_editorLayer.selectedNode = (id)hit;

	} else {

		// hit test anything
		hit = [_editorLayer osmHitTest:point radius:DefaultHitTestRadius isDragConnect:NO ignoreList:nil segment:NULL];
		if ( hit ) {
			if ( hit.isNode ) {
				_editorLayer.selectedNode = (id)hit;
				_editorLayer.selectedWay = nil;
				_editorLayer.selectedRelation = nil;
			} else if ( hit.isWay ) {
				if ( _editorLayer.selectedRelation && [hit.isWay.parentRelations containsObject:_editorLayer.selectedRelation] ) {
					// selecting way inside previously selected relation
					_editorLayer.selectedNode = nil;
					_editorLayer.selectedWay = (id)hit;
				} else if ( hit.parentRelations.count > 0 ) {
					// select relation the way belongs to
					NSArray * relations = [hit.parentRelations filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(OsmRelation * relation, id bindings) {
						return relation.isMultipolygon || relation.isBoundary || relation.isWaterway;
					}]];
					if ( relations.count == 0 && !hit.hasInterestingTags )
						relations = hit.parentRelations;	// if the way doesn't have tags then always promote to containing relation
					OsmRelation * relation = relations.count > 0 ? relations.firstObject : nil;
					if ( relation ) {
						hit = relation;	// convert hit to relation
						_editorLayer.selectedNode = nil;
						_editorLayer.selectedWay = nil;
						_editorLayer.selectedRelation = (id)hit;
					} else {
						_editorLayer.selectedNode = nil;
						_editorLayer.selectedWay = (id)hit;
						_editorLayer.selectedRelation = nil;
					}
				} else {
					_editorLayer.selectedNode = nil;
					_editorLayer.selectedWay = (id)hit;
					_editorLayer.selectedRelation = nil;
				}
			} else {
				_editorLayer.selectedNode = nil;
				_editorLayer.selectedWay = nil;
				_editorLayer.selectedRelation = (id)hit;
			}
		} else {
			_editorLayer.selectedNode = nil;
			_editorLayer.selectedWay = nil;
			_editorLayer.selectedRelation = nil;
		}
	}

	[self removePin];

	if ( _editorLayer.selectedPrimary ) {
		// adjust tap point to touch object
		CLLocationCoordinate2D latLon = [self longitudeLatitudeForScreenPoint:point birdsEye:YES];
		OSMPoint pt = { latLon.longitude, latLon.latitude };
		pt = [_editorLayer.selectedPrimary pointOnObjectForPoint:pt];
		point = [self screenPointForLatitude:pt.y longitude:pt.x birdsEye:YES];

		[self placePushpinAtPoint:point object:_editorLayer.selectedPrimary];

		if ( _editorLayer.selectedPrimary.isWay || _editorLayer.selectedPrimary.isRelation ) {
			// if they later try to drag this way ask them if they really wanted to
			_confirmDrag = (_editorLayer.selectedPrimary.modifyCount == 0);
		}
	}
}

@end
