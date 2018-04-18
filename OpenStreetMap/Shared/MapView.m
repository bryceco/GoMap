//
//  MapView.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 9/25/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>

#import "iosapi.h"

#import "AerialList.h"
#import "BingMapsGeometry.h"
#import "DisplayLink.h"
#import "DLog.h"
#import "DownloadThreadPool.h"
#import "EditorMapLayer.h"
#import "FpsLabel.h"
#import "GpxLayer.h"
#import "HtmlAlertViewController.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "OsmMapData+Orthogonalize.h"
#import "OsmMapData+Straighten.h"
#import "OsmObjects.h"
#import "RulerLayer.h"
#import "SpeechBalloonView.h"
#import "TapAndDragGesture.h"
#import "TurnRestrictController.h"
#import "VoiceAnnouncement.h"

#if TARGET_OS_IPHONE
#import "DDXML.h"
#import "LocationBallLayer.h"
#import "MapViewController.h"
#import "PushPinView.h"
#import "WebPageViewController.h"
#else
#import "HtmlErrorWindow.h"
#endif


#define FRAMERATE_TEST	0


static const CGFloat Z_AERIAL			= -100;
static const CGFloat Z_MAPNIK			= -99;
static const CGFloat Z_LOCATOR			= -50;
static const CGFloat Z_GPSTRACE			= -40;
static const CGFloat Z_ROTATEGRAPHIC	= -35;
static const CGFloat Z_EDITOR			= -20;
static const CGFloat Z_GPX				= -15;
//static const CGFloat Z_BUILDINGS		= -18;
static const CGFloat Z_RULER			= -5;	// ruler is below buttons
//static const CGFloat Z_BING_LOGO		= 2;
static const CGFloat Z_BLINK			= 4;
static const CGFloat Z_BALL				= 5;
static const CGFloat Z_FLASH			= 6;
static const CGFloat Z_TOOLBAR			= 9000;
static const CGFloat Z_PUSHPIN			= 9001;
static const CGFloat Z_CROSSHAIRS		= 10000;




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


@interface MapView ()
@property (strong,nonatomic) IBOutlet UIView	*	statusBarBackground;
@end

@implementation MapView

@synthesize aerialLayer			= _aerialLayer;
@synthesize mapnikLayer			= _mapnikLayer;
@synthesize editorLayer			= _editorLayer;
@synthesize gpsState			= _gpsState;
@synthesize pushpinView			= _pushpinView;
@synthesize viewState			= _viewState;
@synthesize screenFromMapTransform	= _screenFromMapTransform;


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
		self.backgroundColor = UIColor.whiteColor;

		_screenFromMapTransform = OSMTransformIdentity();
		_birdsEyeDistance = 1000.0;

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
		_aerialLayer.backgroundColor = [UIColor lightGrayColor].CGColor;	// this color is displayed while waiting for tiles to download
		[bg addObject:_aerialLayer];

		_mapnikLayer = [[MercatorTileLayer alloc] initWithMapView:self];
		_mapnikLayer.aerialService = [AerialService mapnik];
		_mapnikLayer.zPosition = Z_MAPNIK;
		_mapnikLayer.hidden = YES;
		_mapnikLayer.backgroundColor = [UIColor lightGrayColor].CGColor;	// this color is displayed while waiting for tiles to download
		[bg addObject:_mapnikLayer];

		_editorLayer = [[EditorMapLayer alloc] initWithMapView:self];
		_editorLayer.zPosition = Z_EDITOR;
		[bg addObject:_editorLayer];

		_gpxLayer = [[GpxLayer alloc] initWithMapView:self];
		_gpxLayer.zPosition = Z_GPX;
		_gpxLayer.hidden = YES;
		[bg addObject:_gpxLayer];

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


		if ( YES ) {
			// implement crosshairs
			_crossHairs = [CAShapeLayer new];
			UIBezierPath * path = [UIBezierPath bezierPath];
			CGFloat radius = 10;
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

#if !TARGET_OS_IPHONE
		[self setFrame:frame];
#endif

#if TARGET_OS_IPHONE
		_editorLayer.mapData.undoCommentCallback = ^(BOOL undo,NSArray * comments) {
			if ( self.silentUndo )
				return;
			NSString * title = undo ? NSLocalizedString(@"Undo",nil) : NSLocalizedString(@"Redo",nil);
			NSArray * comment = comments.count == 0 ? nil : undo ? comments.lastObject : comments[0];
			NSString * action = comment[0];
			NSData * location = comment[1];
			if ( location.length == sizeof(OSMTransform) ) {
				OSMTransform transform = *(OSMTransform *)[location bytes];
				self.screenFromMapTransform = transform;
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
	[super awakeFromNib];

#if TARGET_OS_IPHONE
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:UIApplicationWillResignActiveNotification object:NULL];
#else
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:[NSApplication sharedApplication]];
#endif

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarChange:) name:UIApplicationWillChangeStatusBarFrameNotification object:[UIApplication sharedApplication]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusBarChange:) name:UIApplicationDidChangeStatusBarFrameNotification object:[UIApplication sharedApplication]];

	_userInstructionLabel.layer.cornerRadius	= 5;
	_userInstructionLabel.layer.masksToBounds	= YES;
	_userInstructionLabel.backgroundColor		= [UIColor colorWithWhite:0.0 alpha:0.3];
	_userInstructionLabel.textColor				= [UIColor whiteColor];
	_userInstructionLabel.hidden = YES;

#if TARGET_OS_IPHONE
	_progressIndicator.color = NSColor.greenColor;
#endif

	if ( [CLLocationManager locationServicesEnabled] ) {
		_locationManager = [[CLLocationManager alloc] init];
		_locationManager.delegate = self;
#if TARGET_OS_IPHONE
		_locationManager.pausesLocationUpdatesAutomatically = NO;
		_locationManager.allowsBackgroundLocationUpdates = self.gpsInBackground && self.enableBreadCrumb;
		if (@available(iOS 11.0, *)) {
			_locationManager.showsBackgroundLocationIndicator = YES;
		}
		_locationManager.activityType = CLActivityTypeOther;
#endif
	}

	// white background for status bar
	_statusBarBackground.backgroundColor = NSColor.whiteColor;
	_statusBarBackground.alpha = 0.25;

	// set up action button
	_editControl.hidden = YES;
	_editControl.selected = NO;
	_editControl.selectedSegmentIndex = UISegmentedControlNoSegment;
	[_editControl setTitleTextAttributes:@{ NSFontAttributeName : [UIFont boldSystemFontOfSize:17.0f] }
									   forState:UIControlStateNormal];
	_editControl.layer.zPosition = Z_TOOLBAR;

#if SHOW_3D
	UIPanGestureRecognizer * panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerPanGesture:)];
	panGestureRecognizer.minimumNumberOfTouches = 2;
	panGestureRecognizer.maximumNumberOfTouches = 2;
	[self addGestureRecognizer:panGestureRecognizer];
#endif

	UILongPressGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
	longPress.delegate = self;
	[self addGestureRecognizer:longPress];

	UIRotationGestureRecognizer * rotationGesture = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotationGesture:)];
	rotationGesture.delegate = self;
	[self addGestureRecognizer:rotationGesture];

	_addNodeButtonLongPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(addNodeButtonLongPressHandler:)];
	_addNodeButtonLongPressGestureRecognizer.minimumPressDuration = 0.001;
	_addNodeButtonLongPressGestureRecognizer.delegate = self;
	[self.addNodeButton addGestureRecognizer:_addNodeButtonLongPressGestureRecognizer];

	_notesDatabase			= [OsmNotesDatabase new];
	_notesDatabase.mapData	= _editorLayer.mapData;
	_notesViewDict			= [NSMutableDictionary new];

	// make help button have rounded corners
	_helpButton.layer.cornerRadius = 10.0;

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
	_centerOnGPSButton.layer.borderColor = [UIColor blueColor].CGColor;
	_centerOnGPSButton.hidden = YES;

	// compass button
	//self.compassButton.hidden = YES;
	self.compassButton.clipsToBounds = NO;
	self.compassButton.contentMode = UIViewContentModeCenter;

#if 0
	// Support zoom via tap and drag
	_tapAndDragGesture = [[TapAndDragGesture alloc] initWithTarget:self action:@selector(handleTapAndDragGesture:)];
	_tapAndDragGesture.delegate = self;
	[self addGestureRecognizer:_tapAndDragGesture];
#endif

#if 0
	// check for mail periodically and update application badge
	_mailTimer = dispatch_source_create( DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue() );
	if ( _mailTimer ) {
		dispatch_source_set_event_handler(_mailTimer, ^{

			NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/user/details"];
			[_editorLayer.mapData putRequest:url method:@"GET" xml:nil completion:^(NSData *postData,NSString * postErrorMessage) {
				if ( postData && postErrorMessage == nil ) {
					NSString * xmlText = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
					NSError * error = nil;
					NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
					for ( NSXMLElement * element in [xmlDoc.rootElement nodesForXPath:@"./user/messages/received" error:nil] ) {
						NSString * unread = [element attributeForName:@"unread"].stringValue;
						[UIApplication sharedApplication].applicationIconBadgeNumber = unread.integerValue +1;
						NSLog(@"update badge");
					}
				}
			}];
		} );
		dispatch_source_set_timer( _mailTimer, DISPATCH_TIME_NOW, 120*NSEC_PER_SEC, 10*NSEC_PER_SEC );
		dispatch_resume( _mailTimer );
	}
#endif
}


-(void)viewDidAppear
{
	static BOOL first = YES;
	if ( !first )
		return;
	first = NO;

	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
															  @"view.scale"				: @(nan("")),
															  @"view.latitude"			: @(nan("")),
															  @"view.longitude"			: @(nan("")),
															  @"mapViewState"			: @(MAPVIEW_EDITORAERIAL),
															  @"mapViewEnableBirdsEye"	: @(NO),
															  @"mapViewEnableRotation"	: @(YES),
															  }];

	self.viewState		 = (MapViewState)	 [[NSUserDefaults standardUserDefaults] integerForKey:@"mapViewState"];
	self.viewOverlayMask = (ViewOverlayMask) [[NSUserDefaults standardUserDefaults] integerForKey:@"mapViewOverlays"];

	self.enableRotation			= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableRotation"];
	self.enableBirdsEye			= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableBirdsEye"];
	self.enableUnnamedRoadHalo	= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableUnnamedRoadHalo"];
	self.enableBreadCrumb		= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableBreadCrumb"];
	self.enableTurnRestriction	= [[NSUserDefaults standardUserDefaults] boolForKey:@"mapViewEnableTurnRestriction"];

	// get current location
	double scale		= [[NSUserDefaults standardUserDefaults] doubleForKey:@"view.scale"];
	double latitude		= [[NSUserDefaults standardUserDefaults] doubleForKey:@"view.latitude"];
	double longitude	= [[NSUserDefaults standardUserDefaults] doubleForKey:@"view.longitude"];
#if 1
	if ( !isnan(latitude) && !isnan(longitude) && !isnan(scale) ) {
		[self setTransformForLatitude:latitude longitude:longitude scale:scale];
	} else {
		OSMRect rc = OSMRectFromCGRect( self.layer.frame );
		self.screenFromMapTransform = OSMTransformMakeTranslation( rc.origin.x+rc.size.width/2 - 128, rc.origin.y+rc.size.height/2 - 128);
		// turn on GPS which will move us to current location
		self.gpsState = GPS_STATE_LOCATION;
	}
#endif

	// get notes
	[self updateNotesWithDelay:0];

	[self updateAerialAttributionButton];

#if FRAMERATE_TEST
	// automaatically scroll view for frame rate testing
	OSMTransform t = { 161658.59853698246, 0, 0, 161658.59853698246, -6643669.8581485003, -14441173.300930388 };
	self.screenFromMapTransform = t;
	__block int side = 0, distance = 0;
	__weak MapView * weakSelf = self;
	DisplayLink * displayLink = [DisplayLink shared];
	[displayLink addName:@"autoScroll" block:^{
		int dx = 0, dy = 0;
		switch ( side ) {
			case 0:
				dx = 1;
				break;
			case 1:
				dy = 1;
				break;
			case 2:
				dx = -1;
				break;
			case 3:
				dy = -1;
				break;
		}
		if ( ++distance > 30 ) {
			side = (side+1) % 4;
			distance = 0;
		}
		[weakSelf adjustOriginBy:CGPointMake(dx,dy)];
	}];
#endif
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
	CGRect rc = self.layer.bounds;
	OSMPoint center = { rc.origin.x + rc.size.width/2, rc.origin.y + rc.size.height/2 };
	center = [self mapPointFromScreenPoint:center birdsEye:NO];
	center = LongitudeLatitudeFromMapPoint( center );
	double scale = OSMTransformScaleX(self.screenFromMapTransform);
	[[NSUserDefaults standardUserDefaults] setDouble:scale					forKey:@"view.scale"];
	[[NSUserDefaults standardUserDefaults] setDouble:center.y				forKey:@"view.latitude"];
	[[NSUserDefaults standardUserDefaults] setDouble:center.x				forKey:@"view.longitude"];

	[[NSUserDefaults standardUserDefaults] setInteger:self.viewState		forKey:@"mapViewState"];
	[[NSUserDefaults standardUserDefaults] setInteger:self.viewOverlayMask	forKey:@"mapViewOverlays"];

	[[NSUserDefaults standardUserDefaults] setBool:self.enableRotation			forKey:@"mapViewEnableRotation"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableBirdsEye			forKey:@"mapViewEnableBirdsEye"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableUnnamedRoadHalo	forKey:@"mapViewEnableUnnamedRoadHalo"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableBreadCrumb		forKey:@"mapViewEnableBreadCrumb"];
	[[NSUserDefaults standardUserDefaults] setBool:self.enableTurnRestriction	forKey:@"mapViewEnableTurnRestriction"];

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

-(void)setFrame:(CGRect)rect
{
	[super setFrame:rect];

	[CATransaction begin];
	[CATransaction setAnimationDuration:0.0];
#if TARGET_OS_IPHONE
	CGRect rc = CGRectMake(10, rect.size.height - 80, 150, 30);
	if (@available(iOS 11.0, *)) {
		rc.origin.y -= self.safeAreaInsets.bottom;
	}
	_rulerLayer.frame = rc;
#else
	_rulerLayer.frame = CGRectMake(10, rect.size.height - 40, 150, 30);
#endif

//	_buildingsLayer.frame = rect;

	CGSize oldSize = _editorLayer.bounds.size;
	if ( oldSize.width ) {
		CGSize newSize = rect.size;
		CGPoint delta = { (newSize.width - oldSize.width)/2, (newSize.height - oldSize.height)/2 };
		[self adjustOriginBy:delta];
	}

	for ( CALayer * layer in _backgroundLayers ) {
		if ( [layer isKindOfClass:[MercatorTileLayer class]] ) {
			layer.anchorPoint = CGPointMake(0.5,0.5);
			layer.frame = self.layer.bounds;
		} else {
			layer.position = self.layer.position;
			layer.bounds = self.layer.bounds;
		}
	}
	_crossHairs.position = CGRectCenter( rect );

	_statusBarBackground.hidden = [UIApplication sharedApplication].statusBarHidden;

	[CATransaction commit];
}

-(void)statusBarChange:(NSNotification *)notification
{
	NSDictionary * userInfo = notification.userInfo;
	NSValue * value = userInfo[ UIApplicationStatusBarFrameUserInfoKey ];
	if ( value ) {
		CGRect rc = [value CGRectValue];
		NSLog(@"bar = %@",NSStringFromCGRect(rc));
	}
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
		[service scaleAttributionIconToHeight:_aerialServiceLogo.frame.size.height];
		[_aerialServiceLogo setImage:service.attributionIcon forState:UIControlStateNormal];
		[_aerialServiceLogo setTitle:service.attributionString forState:UIControlStateNormal];
	}
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
			UIAlertController * alertError = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
			[alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
			[alertError addAction:[UIAlertAction actionWithTitle:ignoreButton style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
				// ignore network errors for a while
				_ignoreNetworkErrorsUntilDate = [[NSDate date] dateByAddingTimeInterval:5*60.0];
			}]];
			[self.viewController presentViewController:alertError animated:YES completion:nil];
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
		NSString * title = [NSString stringWithFormat:@"You've uploaded %ld changesets with this version of Go Map!!\n\nRate this app?", (long)uploadCount];
        UIAlertController * alertViewRateApp = [UIAlertController alertControllerWithTitle:title message:@"Rating this app makes it easier for other mappers to discover it and increases the visibility of OpenStreetMap." preferredStyle:UIAlertControllerStyleAlert];
        [alertViewRateApp addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Maybe later...",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
        [alertViewRateApp addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"I'll do it!",nil)    style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			[self showInAppStore];
        }]];
        [self.viewController presentViewController:alertViewRateApp animated:YES completion:nil];

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
		[self.viewController performSegueWithIdentifier:@"BingMetadataSegue" sender:self];
	} else if ( aerial.attributionUrl.length > 0 ) {
		// open the attribution url
		WebPageViewController * webController = [[WebPageViewController alloc] initWithNibName:@"WebPageView" bundle:nil];
		webController.url = aerial.attributionUrl;
		webController.title = NSLocalizedString(@"Imagery Attribution",nil);
		[self.viewController presentViewController:webController animated:YES completion:nil];
	}
}

#pragma mark Rotate object

-(void)startObjectRotation
{
	_isRotateObjectMode				= YES;
	_rotateObjectCenter				= _editorLayer.selectedNode ? _editorLayer.selectedNode.location : [_editorLayer.selectedWay centerPoint];
	[self removePin];
	_rotateObjectOverlay = [[CAShapeLayer alloc] init];
	CGFloat radiusInner = 70;
	CGFloat radiusOuter = 90;
	CGFloat arrowWidth = 60;
	CGPoint center = [self screenPointForLatitude:_rotateObjectCenter.y longitude:_rotateObjectCenter.x birdsEye:YES]; // CGRectCenter(self.bounds);
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

	[CATransaction begin];
	[CATransaction setAnimationDuration:0.5];

	_locatorLayer.hidden  = (newOverlays & VIEW_OVERLAY_LOCATOR) == 0;
	_gpsTraceLayer.hidden = (newOverlays & VIEW_OVERLAY_GPSTRACE) == 0;

	switch (newState) {
		case MAPVIEW_EDITOR:
			_editorLayer.whiteText = NO;
			_editorLayer.hidden = NO;
			_aerialLayer.hidden = YES;
			_mapnikLayer.hidden = YES;
			_userInstructionLabel.hidden = YES;
			break;
		case MAPVIEW_EDITORAERIAL:
			_editorLayer.whiteText = YES;
			_aerialLayer.aerialService = _customAerials.currentAerial;
			_editorLayer.hidden = NO;
			_aerialLayer.hidden = NO;
			_mapnikLayer.hidden = YES;
			_userInstructionLabel.hidden = YES;
			_aerialLayer.opacity = 0.75;
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
				_userInstructionLabel.text = @"Zoom to Edit";
			break;
		case MAPVIEW_NONE:
			// shouldn't occur
			_editorLayer.hidden = YES;
			_aerialLayer.hidden = YES;
			_mapnikLayer.hidden = YES;
			break;
	}
	[self updateNotesWithDelay:0];

	[CATransaction commit];

	// enable/disable editing buttons based on visibility
	[_viewController updateDeleteButtonState];
	[_viewController updateUndoRedoButtonState];
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
		[_editorLayer setNeedsDisplay];
		[_editorLayer setNeedsLayout];
	}
}
-(void)setEnableBreadCrumb:(BOOL)enableBreadCrumb
{
	if ( _enableBreadCrumb != enableBreadCrumb ) {
		_enableBreadCrumb = enableBreadCrumb;

		_gpxLayer.hidden = !self.enableBreadCrumb;

		_locationManager.allowsBackgroundLocationUpdates = self.gpsInBackground && self.enableBreadCrumb;
	}
}

-(void)setEnableTurnRestriction:(BOOL)enableTurnRestriction
{
	if ( _enableTurnRestriction != enableTurnRestriction ) {
		_enableTurnRestriction = enableTurnRestriction;
		[_editorLayer.mapData clearCachedProperties];    // reset layers associated with objects
		[_editorLayer setNeedsDisplay];
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
	CGPoint center = CGRectCenter(self.bounds);
	CLLocationCoordinate2D latLon = [self longitudeLatitudeForScreenPoint:center birdsEye:YES];
	double area = MetersPerDegree( latLon.latitude );
	OSMRect rcMap = [self boundingMapRectForScreen];
	area = area*area * rcMap.size.width * rcMap.size.height;
	self.viewStateOverride = area > 2.0*1000*1000;

	[_rulerLayer updateDisplay];
	[self updateMouseCoordinates];
	[self updateUserLocationIndicator:nil];

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
		if ( pt.x > rc.origin.x+rc.size.width ) {
			pt.x -= mapSize*unitX.x;
			pt.y -= mapSize*unitX.y;
		} else if ( pt.x < rc.origin.x ) {
			pt.x += mapSize*unitX.x;
			pt.y += mapSize*unitX.y;
		}
		if ( pt.y > rc.origin.y+rc.size.height ) {
			pt.x -= mapSize*unitY.x;
			pt.y -= mapSize*unitY.y;
		} else if ( pt.y < 0 ) {
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
	return rc;
}

-(CGPoint)screenPointForLatitude:(double)latitude longitude:(double)longitude birdsEye:(BOOL)birdsEye
{
	OSMPoint pt = MapPointForLatitudeLongitude( latitude, longitude );
	pt = [self screenPointFromMapPoint:pt birdsEye:birdsEye];
	return CGPointFromOSMPoint(pt);
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude scale:(double)scale
{
#if 1
	OSMPoint center = MapPointForLatitudeLongitude( latitude, longitude );
	[self setMapCenter:center scale:scale];
#else
	CGPoint point = [self screenPointForLatitude:latitude longitude:longitude];
	CGPoint center = CGRectCenter( self.layer.bounds );

	CGPoint delta = { center.x - point.x, center.y - point.y };
	double ratio = scale / OSMTransformScaleX(_screenFromMapTransform);

	[self adjustOriginBy:delta];
	[self adjustZoomBy:ratio aroundScreenPoint:center];
#endif
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude
{
	CGPoint point = [self screenPointForLatitude:latitude longitude:longitude birdsEye:NO];
	CGPoint center = CGRectCenter( self.layer.bounds );
	CGPoint delta = { center.x - point.x, center.y - point.y };
	[self adjustOriginBy:delta];
}

-(void)setTransformForLatitude:(double)latitude longitude:(double)longitude width:(double)widthDegrees
{
	double scale = 360/(widthDegrees / 2);
	[self setTransformForLatitude:latitude longitude:longitude scale:scale];
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

		if ( _gpsState == GPS_STATE_HEADING ) {
			// orient toward north
			CGPoint center = CGRectCenter(self.bounds);
			double rotation = OSMTransformRotation( _screenFromMapTransform );
			[self animateRotationBy:-rotation aroundPoint:center];
		}

		if ( gpsState == GPS_STATE_NONE ) {
			_centerOnGPSButton.hidden = YES;
			_voiceAnnouncement.enabled = NO;
		} else {
			_voiceAnnouncement.enabled = YES;
		}

		_gpsState = gpsState;
		if ( _gpsState != GPS_STATE_NONE ) {
			[self locateMe:nil];
		} else {
			// turn off updates
			[_locationManager stopUpdatingLocation];
#if TARGET_OS_IPHONE
			[_locationManager stopUpdatingHeading];
#endif
			[_locationBallLayer removeFromSuperlayer];
			_locationBallLayer = nil;
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

	_locationManager.allowsBackgroundLocationUpdates = gpsInBackground && self.enableBreadCrumb;

	if ( gpsInBackground ) {
		// ios 8 and later:
		if ( [_locationManager respondsToSelector:@selector(requestAlwaysAuthorization)] ) {
			[_locationManager  requestAlwaysAuthorization];
		}
	}
}

-(IBAction)locateMe:(id)sender
{
	CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
	if ( status == kCLAuthorizationStatusRestricted || status == kCLAuthorizationStatusDenied ) {
		NSString * appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
		NSString * title = [NSString stringWithFormat:NSLocalizedString(@"Turn On Location Services to Allow %@ to Determine Your Location",nil),appName];
        UIAlertController * alertGps = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alertGps addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
        [self.viewController presentViewController:alertGps animated:YES completion:nil];

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
#else
	[self performSelector:@selector(locationUpdateFailed:) withObject:nil afterDelay:5.0];
#endif
}

-(IBAction)centerOnGPS:(id)sender
{
	if ( _gpsState == GPS_STATE_NONE )
		return;

	self.userOverrodeLocationPosition = NO;
	CLLocation * location = _locationManager.location;
	[self setTransformForLatitude:location.coordinate.latitude longitude:location.coordinate.longitude];
}

-(IBAction)rotateToNorth:(id)sender
{
	switch ( self.gpsState ) {
		case GPS_STATE_HEADING:
			self.gpsState = GPS_STATE_LOCATION;
			break;
		case GPS_STATE_LOCATION:
			self.gpsState = GPS_STATE_HEADING;
		case GPS_STATE_NONE:
			// nothing
			break;
	}
}

-(void)locationUpdateFailed:(NSError *)error
{
	MapViewController * controller = self.viewController;
	[controller setGpsState:GPS_STATE_NONE];

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(locationUpdateFailed:) object:nil];

	if ( ![self isLocationSpecified] ) {
		// go home
#if 1
		[self setTransformForLatitude:47.6858 longitude:-122.1917 width:0.01];
#else
		OSMTransform transform = { 0 };
		transform.a = transform.d = 106344;
		transform.tx = 9241972;
		transform.ty = 4112460;
		self.screenFromMapTransform = transform;
#endif
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

#if 0
- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager
{
	return YES;
}
#endif

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
			double (^easeInOutQuad)( double t, double b, double c, double d ) = ^( double t, double b, double c, double d ) {
				t /= d/2;
				if (t < 1) return c/2*t*t + b;
				t--;
				return -c/2 * (t*(t-2) - 1) + b;
			};
			double miniHeading = easeInOutQuad( elapsedTime, 0, deltaHeading, duration);
			[myself rotateBy:miniHeading-prevHeading aroundScreenPoint:center];
			myself->_locationBallLayer.heading	= M_PI*3/2;
			prevHeading = miniHeading;
			if ( elapsedTime >= duration ) {
				[displayLink removeName:DisplayLinkHeading];
			}
		}
	}];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
	if ( _locationBallLayer ) {

		double screenAngle = OSMTransformRotation( _screenFromMapTransform );
		_locationBallLayer.headingAccuracy	= newHeading.headingAccuracy * M_PI / 180;
		_locationBallLayer.showHeading		= YES;
		double heading = newHeading.trueHeading * M_PI / 180;
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
		if ( _gpsState == GPS_STATE_LOCATION ) {
			_locationBallLayer.heading	= heading + screenAngle - M_PI/2;
		}
		if ( _gpsState == GPS_STATE_HEADING ) {
			// rotate to new heading
			CGPoint	center;
			if ( CGRectContainsPoint( self.bounds, _locationBallLayer.position ) ) {
				center = _locationBallLayer.position;
			} else {
				center = CGRectCenter( self.bounds );
			}

			double delta = -(heading + screenAngle);
			[self animateRotationBy:delta aroundPoint:center];
		}
	}
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
	double delta = hypot( newLocation.coordinate.latitude - _currentLocation.coordinate.latitude, newLocation.coordinate.longitude - _currentLocation.coordinate.longitude);
	delta *= MetersPerDegree( newLocation.coordinate.latitude );
	if ( _locationBallLayer && delta < 0.1 && fabs(newLocation.horizontalAccuracy - _currentLocation.horizontalAccuracy) < 1.0 )
		return;
	_currentLocation = [newLocation copy];

	if ( _voiceAnnouncement && !_editorLayer.hidden ) {
		[_voiceAnnouncement announceForLocation:newLocation.coordinate];
	}

	if ( _gpxLayer.activeTrack ) {
		[_gpxLayer addPoint:newLocation];
		// DLog( @"gps point %d", (int)_gpxLayer.activeTrack.points.count );
	}

	if ( self.gpsState == GPS_STATE_NONE ) {
		[_locationManager stopUpdatingLocation];
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(locationUpdateFailed:) object:nil];

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
		_locationBallLayer = [LocationBallLayer new];
		_locationBallLayer.zPosition = Z_BALL;
		_locationBallLayer.heading = 0.0;
		_locationBallLayer.showHeading = YES;
		[self.layer addSublayer:_locationBallLayer];
	}
	[self updateUserLocationIndicator:newLocation];
}

// delegate for iIOS 6 and later
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
	[self locationUpdateFailed:error];
}


#pragma mark Undo/Redo

-(void)placePushpinForSelection
{
#if TARGET_OS_IPHONE
	if ( _editorLayer.selectedNode ) {
		CGPoint point = [self screenPointForLatitude:_editorLayer.selectedNode.lat longitude:_editorLayer.selectedNode.lon birdsEye:YES];
		[self placePushpinAtPoint:point object:_editorLayer.selectedNode];
	} else if ( _editorLayer.selectedWay ) {
		OSMPoint pt = [_editorLayer.selectedWay centerPoint];
		pt = [_editorLayer.selectedWay pointOnWayForPoint:pt];
		CGPoint point = [self screenPointForLatitude:pt.y longitude:pt.x birdsEye:YES];
		[self placePushpinAtPoint:point object:_editorLayer.selectedPrimary];
	} else if (_editorLayer.selectedRelation ) {
		OSMPoint pt = [_editorLayer.selectedRelation centerPoint];
		CGPoint point = [self screenPointForLatitude:pt.y longitude:pt.x birdsEye:YES];
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
	[_editorLayer setNeedsLayout];

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
	[_editorLayer setNeedsLayout];

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
	return !OSMTransformEqual( _screenFromMapTransform, OSMTransformIdentity() );
}


-(void)updateMouseCoordinates
{
}

-(void)setMapCenter:(OSMPoint)mapCenter scale:(double)newScale
{
	// translate
	OSMPoint point = [self screenPointFromMapPoint:mapCenter birdsEye:NO];
	CGPoint center = CGRectCenter( self.layer.bounds );

	CGPoint delta = { center.x - point.x, center.y - point.y };
	[self adjustOriginBy:delta];

	double ratio = newScale / OSMTransformScaleX(_screenFromMapTransform);
	[self adjustZoomBy:ratio aroundScreenPoint:center];
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

	if ( _locationBallLayer ) {
		_locationBallLayer.heading = _locationBallLayer.heading + angle;
	}
	if ( !_compassButton.hidden ) {
		double screenAngle = OSMTransformRotation( _screenFromMapTransform );
//		_compassButton.imageView.layer.transform = CATransform3DMakeAffineTransform( CGAffineTransformMakeRotation(screenAngle) );
		_compassButton.transform = CGAffineTransformMakeRotation(screenAngle);
	}
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

-(IBAction)delete:(id)sender
{
#if TARGET_OS_IPHONE
	UIAlertController *	alertDelete = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Delete",nil) message:NSLocalizedString(@"Delete selection?",nil) preferredStyle:UIAlertControllerStyleAlert];
	[alertDelete addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
	[alertDelete addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
		[_editorLayer deleteSelectedObject];
		[self removePin];
	}]];
	[self.viewController presentViewController:alertDelete animated:YES completion:nil];
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


#pragma mark Edit Actions

typedef enum {
	// used for extended edit actions:
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
	// used by edit control:
	ACTION_EDITTAGS,
	ACTION_ADDNOTE,
	ACTION_DELETE,
	ACTION_MORE,
	ACTION_HEIGHT,
	ACTION_RESTRICT,
} EDIT_ACTION;
NSString * ActionTitle( NSInteger action )
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
		case ACTION_HEIGHT:			return NSLocalizedString(@"Measure Height", nil);
		case ACTION_RESTRICT:		return NSLocalizedString(@"Restrict", nil);
	};
	return nil;
}

- (void)presentEditActionSheet:(id)sender
{
	NSArray * actionList = nil;
	if ( _editorLayer.selectedRelation ) {
		// relation
		actionList = @[ @(ACTION_COPYTAGS), @(ACTION_PASTETAGS) ];
	} else if ( _editorLayer.selectedWay ) {
		if ( _editorLayer.selectedNode ) {
			// node in way
			NSArray * parentWays = [_editorLayer.mapData waysContainingNode:_editorLayer.selectedNode];
			BOOL disconnect = parentWays.count > 1 || _editorLayer.selectedNode.hasInterestingTags;
			BOOL split = _editorLayer.selectedWay.isClosed || (_editorLayer.selectedNode != _editorLayer.selectedWay.nodes[0] && _editorLayer.selectedNode != _editorLayer.selectedWay.nodes.lastObject);
			BOOL join = parentWays.count > 1;
			NSMutableArray * a = [NSMutableArray arrayWithObjects:@(ACTION_COPYTAGS), @(ACTION_HEIGHT), nil];
			if ( disconnect )
				[a addObject:@(ACTION_DISCONNECT)];
			if ( split )
				[a addObject:@(ACTION_SPLIT)];
			if ( join )
				[a addObject:@(ACTION_JOIN)];
			[a addObject:@(ACTION_ROTATE)];
			actionList = [NSArray arrayWithArray:a];
		} else {
			if ( _editorLayer.selectedWay.isClosed ) {
				// polygon
				actionList = @[ @(ACTION_COPYTAGS), @(ACTION_HEIGHT), @(ACTION_ROTATE), @(ACTION_DUPLICATE), @(ACTION_CIRCULARIZE), @(ACTION_RECTANGULARIZE) ];
			} else {
				// line
				actionList = @[ @(ACTION_COPYTAGS), @(ACTION_HEIGHT), @(ACTION_DUPLICATE), @(ACTION_STRAIGHTEN), @(ACTION_REVERSE) ];
			}
		}
	} else if ( _editorLayer.selectedNode ) {
		// node
		actionList = @[ @(ACTION_COPYTAGS), @(ACTION_HEIGHT), @(ACTION_DUPLICATE) ];
	} else {
		// nothing selected
		return;
	}
	UIAlertController * actionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Perform Action",nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	for ( NSNumber * value in actionList ) {
		NSString * title = ActionTitle( value.integerValue );
		[actionSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
			[self performEditAction:value.integerValue];
		}]];
	}
	[actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {}]];
	[self.viewController presentViewController:actionSheet animated:YES completion:nil];
	// compute location for action sheet to originate
	CGRect button = self.editControl.bounds;
	CGFloat segmentWidth = button.size.width / self.editControl.numberOfSegments;	// hack because we can't get the frame for an individual segment
	button.origin.x += button.size.width - segmentWidth;
	button.size.width = segmentWidth;
	actionSheet.popoverPresentationController.sourceView = self.editControl;
	actionSheet.popoverPresentationController.sourceRect = button;

}

-(void)performEditAction:(NSInteger)action
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
			if ( ! [_editorLayer pasteTags:_editorLayer.selectedPrimary] )
				error = NSLocalizedString(@"No tags to paste",nil);
			break;
		case ACTION_DUPLICATE:
			{
				OsmBaseObject * newObject = [_editorLayer duplicateObject:_editorLayer.selectedPrimary];
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
			if ( _editorLayer.selectedWay == nil || _editorLayer.selectedRelation ) {
				error = NSLocalizedString(@"Only ways can be rotated", nil);
			} else {
				[self startObjectRotation];
			}
			break;
		case ACTION_RECTANGULARIZE:
			if ( _editorLayer.selectedWay.ident.longLongValue >= 0  &&  !OSMRectContainsRect( self.screenLongitudeLatitude, _editorLayer.selectedWay.boundingBox ) )
				error = NSLocalizedString(@"The selected way must be completely visible", nil);	// avoid bugs where nodes are deleted from other objects
			else if ( ! [_editorLayer.mapData orthogonalizeWay:_editorLayer.selectedWay] )
				error = NSLocalizedString(@"The way is not sufficiently rectangular",nil);
			break;
		case ACTION_REVERSE:
			if ( ![_editorLayer.mapData reverseWay:_editorLayer.selectedWay] )
				error = NSLocalizedString(@"Cannot reverse way",nil);
			break;
		case ACTION_JOIN:
			if ( ![_editorLayer.mapData joinWay:_editorLayer.selectedWay atNode:_editorLayer.selectedNode] )
				error = NSLocalizedString(@"Cannot join selection",nil);
			break;
		case ACTION_DISCONNECT:
			if ( ! [_editorLayer.mapData disconnectWay:_editorLayer.selectedWay atNode:_editorLayer.selectedNode] )
				error = NSLocalizedString(@"Cannot disconnect way",nil);
			break;
		case ACTION_SPLIT:
			if ( ! [_editorLayer.mapData splitWay:_editorLayer.selectedWay atNode:_editorLayer.selectedNode] )
				error = NSLocalizedString(@"Cannot split way",nil);
			break;
		case ACTION_STRAIGHTEN:
			if ( _editorLayer.selectedWay.ident.longLongValue >= 0  &&  !OSMRectContainsRect( self.screenLongitudeLatitude, _editorLayer.selectedWay.boundingBox ) )
				error = NSLocalizedString(@"The selected way must be completely visible", nil);	// avoid bugs where nodes are deleted from other objects
			else if ( ! [_editorLayer.mapData straightenWay:_editorLayer.selectedWay] )
				error = NSLocalizedString(@"The way is not sufficiently straight",nil);
			break;
		case ACTION_CIRCULARIZE:
			if ( ! [_editorLayer.mapData circularizeWay:_editorLayer.selectedWay] )
				error = NSLocalizedString(@"The way cannot be made circular",nil);
			break;
		case ACTION_HEIGHT:
			if ( self.gpsState != GPS_STATE_NONE ) {
				[self.viewController performSegueWithIdentifier:@"CalculateHeightSegue" sender:nil];
			} else {
				error = NSLocalizedString(@"This action requires GPS to be turned on",nil);
			}
			break;
		case ACTION_EDITTAGS:
			[self presentTagEditor:nil];
			break;
		case ACTION_ADDNOTE: {
				CLLocationCoordinate2D pos = [self longitudeLatitudeForScreenPoint:_pushpinView.arrowPoint birdsEye:YES];
				OsmNote * note = [[OsmNote alloc] initWithLat:pos.latitude lon:pos.longitude];
				[self.viewController performSegueWithIdentifier:@"NotesSegue" sender:note];
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
		default:
			error = NSLocalizedString(@"Not implemented",nil);
			break;
	}
	if ( error ) {
		UIAlertController * alertError = [UIAlertController alertControllerWithTitle:error message:nil preferredStyle:UIAlertControllerStyleAlert];
		[alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
		[self.viewController presentViewController:alertError animated:YES completion:nil];
	}

	[self.editorLayer setNeedsDisplay];
	[self.editorLayer setNeedsLayout];
	[self refreshPushpinText];
}

-(IBAction)presentTagEditor:(id)sender
{
	[self.viewController performSegueWithIdentifier:@"poiSegue" sender:nil];
}

-(IBAction)editControlAction:(id)sender
{
	// get the selected button: has to be done before modifying the node/way selection
	UISegmentedControl * segmentedControl = (UISegmentedControl *) sender;
	NSInteger segment = segmentedControl.selectedSegmentIndex;

	if ( segment < _editControlActions.count ) {
		NSNumber * actionNum = _editControlActions[ segment ];
		NSInteger action = actionNum.integerValue;

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
		}

		[self performEditAction:action];
	}
	segmentedControl.selectedSegmentIndex = UISegmentedControlNoSegment;
}

- (void)updateEditControl
{
	BOOL show = _pushpinView || _editorLayer.selectedWay || _editorLayer.selectedNode || _editorLayer.selectedRelation;
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
				self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS) ];
			else if ( _enableTurnRestriction && _editorLayer.selectedPrimary.isNode && [_editorLayer.mapData waysContainingNode:_editorLayer.selectedNode].count > 1 )
				self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS), @(ACTION_DELETE), @(ACTION_RESTRICT), @(ACTION_MORE) ];
			else
				self.editControlActions = @[ @(ACTION_EDITTAGS), @(ACTION_PASTETAGS), @(ACTION_DELETE), @(ACTION_MORE) ];
		}
		[_editControl removeAllSegments];
		for ( NSNumber * action in _editControlActions ) {
			NSString * title = ActionTitle( action.integerValue );
			[_editControl insertSegmentWithTitle:title atIndex:_editControl.numberOfSegments animated:NO];
		}
	}
}


// MARK: Open Restrict popup window
-(void)restrictOptionSelected
{
#if 0
	rotationGesture.rotation = 0.00001;
	CGPoint centerPoint = [rotationGesture locationInView:self];
	CGFloat angle = rotationGesture.rotation;
	[self rotateBy:angle aroundScreenPoint:centerPoint];
	rotationGesture.rotation = 0.0;
#endif

	//    rotationGesture.rotation = -0.00001;
	//    CGPoint centerPoint2 = [rotationGesture locationInView:self];
	//    CGFloat angle2 = rotationGesture.rotation;
	//    [self rotateBy:angle2 aroundScreenPoint:centerPoint2];
	//    rotationGesture.rotation = 0.0;



	[self updateNotesWithDelay:0];

	//    [self startObjectRotation];
	//    rotationGesture.state = UIGestureRecognizerStateBegan;
	//    [self handleRotationGesture:rotationGesture];
	//
	//    rotationGesture.state = UIGestureRecognizerStateChanged;
	//    [self handleRotationGesture:rotationGesture];
	//
	//    rotationGesture.state = UIGestureRecognizerStateEnded;
	//    [self handleRotationGesture:rotationGesture];
	//    [self endObjectRotation];

	NSMutableArray *parents = [[_editorLayer.mapData waysContainingNode:_editorLayer.selectedNode] mutableCopy];
	for ( OsmWay * way in [parents copy] ) {
		if ( [way.tags objectForKey:@"highway"] == nil )
			[parents removeObject:way];
	}
	NSArray *parentWays = parents;
	OsmNode *seletedNode = self.editorLayer.selectedNode;

	TurnRestrictController *myVc = [_viewController.storyboard instantiateViewControllerWithIdentifier:@"MapCropController"];
	myVc.parentWays   = [NSMutableArray arrayWithArray:parentWays];
	myVc.selectedNode = seletedNode;

	CGPoint center = CGRectCenter(self.layer.bounds);

	myVc.mapCenter = center;
	myVc.birdsEyeRotation = _birdsEyeRotation;
	myVc.birdsEyeDistance = _birdsEyeDistance;
	myVc.screenFromMapTransform = _screenFromMapTransform;

	myVc.modalPresentationStyle = UIModalPresentationOverCurrentContext;
	[_viewController presentViewController:myVc animated:true completion:nil];
}
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
#pragma mark PushPin


#if TARGET_OS_IPHONE
-(OsmBaseObject *)dragConnectionForNode:(OsmNode *)node segment:(NSInteger *)segment
{
	assert( node.isNode );
	assert( _editorLayer.selectedWay );

	OsmWay * way = _editorLayer.selectedWay;

#if 0
	// only do this checks if we want to be extra cautious
	if ( node != way.nodes[0] && node != way.nodes.lastObject )
		return nil;
	if ( node.wayCount > 1 )
		return nil;
#endif

	NSArray * ignoreList = nil;
	NSInteger index = [way.nodes indexOfObject:node];
	NSArray * parentWays = node.wayCount == 1 ? @[ way ] : [_editorLayer.mapData waysContainingNode:node];
	if ( way.nodes.count < 3 ) {
		ignoreList = [parentWays arrayByAddingObjectsFromArray:way.nodes];
	} else if ( index == 0 ) {
		// if end-node then okay to connect to self-nodes except for adjacent
		ignoreList = [parentWays arrayByAddingObjectsFromArray:@[ way.nodes[0], way.nodes[1], way.nodes[2] ]];
	} else if ( index == way.nodes.count-1 ) {
		// if end-node then okay to connect to self-nodes except for adjacent
		ignoreList = [parentWays arrayByAddingObjectsFromArray:@[ way.nodes[index], way.nodes[index-1], way.nodes[index-2] ]];
	} else {
		// if middle node then never connect to self
		ignoreList = [way.nodes arrayByAddingObjectsFromArray:parentWays];
	}
	OsmBaseObject * hit = [EditorMapLayer osmHitTest:_pushpinView.arrowPoint
											  radius:DragConnectHitTestRadius
											 mapView:self
											 objects:_editorLayer.shownObjects
										   testNodes:YES
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

	_pushpinView = [PushPinView new];
	_pushpinView.text = object ? object.friendlyDescription : NSLocalizedString(@"(new object)",nil);
	_pushpinView.layer.zPosition = Z_PUSHPIN;

	_pushpinView.arrowPoint = point;

	__weak MapView * weakSelf = self;
	if ( object ) {
		_pushpinView.dragCallback = ^(UIGestureRecognizerState state, CGFloat dx, CGFloat dy, UIGestureRecognizer * gesture ) {
			switch ( state ) {
				case UIGestureRecognizerStateBegan:
					[weakSelf.editorLayer.mapData beginUndoGrouping];
					_pushpinDragTotalMove.x = _pushpinDragTotalMove.y = 0.0;
					_gestureDidMove		= NO;
					break;

				case UIGestureRecognizerStateCancelled:
				case UIGestureRecognizerStateFailed:
					DLog(@"Gesture ended with cancel/fail\n");
					// fall through so we properly terminate gesture
				case UIGestureRecognizerStateEnded:
					{
						MapView * strongSelf = weakSelf;

						[strongSelf.editorLayer.mapData endUndoGrouping];
						[[DisplayLink shared] removeName:@"dragScroll"];

						BOOL isRotate = strongSelf->_isRotateObjectMode;
						if ( isRotate ) {
							[strongSelf endObjectRotation];
						}

						[strongSelf unblinkObject];
						if ( strongSelf.editorLayer.selectedWay && object.isNode ) {
							// dragging a node that is part of a way
							OsmNode * dragNode = object.isNode;
							OsmWay  * dragWay = strongSelf.editorLayer.selectedWay;
							NSInteger segment;
							OsmBaseObject * hit = [strongSelf dragConnectionForNode:dragNode segment:&segment];
							if ( hit.isNode ) {
								// replace dragged node with hit node
								NSDictionary * mergedTags = MergeTags(hit.tags,dragNode.tags);
								NSInteger index = [dragWay.nodes indexOfObject:dragNode];
								[strongSelf.editorLayer deleteNode:dragNode fromWay:dragWay allowDegenerate:YES];
								[strongSelf.editorLayer addNode:hit.isNode toWay:dragWay atIndex:index];
								[strongSelf.editorLayer.mapData setTags:mergedTags forObject:hit];
								if ( dragWay.isArea ) {
									strongSelf.editorLayer.selectedNode = nil;
									[strongSelf placePushpinForSelection];
								} else {
									strongSelf.editorLayer.selectedNode = hit.isNode;
									[strongSelf placePushpinForSelection];
								}
							}
							if ( hit.isWay ) {
								// add new node to hit way
								OSMPoint pt = [hit.isWay pointOnWayForPoint:dragNode.location];
								[strongSelf.editorLayer.mapData setLongitude:pt.x latitude:pt.y forNode:dragNode inWay:weakSelf.editorLayer.selectedWay];
								[strongSelf.editorLayer addNode:dragNode toWay:hit.isWay atIndex:segment+1];
							}
							return;
						}
						if ( isRotate )
							break;
						if ( strongSelf.editorLayer.selectedWay && strongSelf.editorLayer.selectedWay.tags.count == 0 && strongSelf.editorLayer.selectedWay.relations.count == 0 )
							break;
						if ( strongSelf.editorLayer.selectedWay && strongSelf.editorLayer.selectedNode )
							break;
						if ( strongSelf->_confirmDrag ) {
							strongSelf->_confirmDrag = NO;

							UIAlertController *	alertMove = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Confirm move",nil) message:NSLocalizedString(@"Move selected object?",nil) preferredStyle:UIAlertControllerStyleAlert];
							[alertMove addAction:[UIAlertAction actionWithTitle:@"Undo" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
								// cancel move
								[strongSelf->_editorLayer.mapData undo];
								[strongSelf->_editorLayer.mapData removeMostRecentRedo];
								strongSelf->_editorLayer.selectedNode = nil;
								strongSelf->_editorLayer.selectedWay = nil;
								strongSelf->_editorLayer.selectedRelation = nil;
								[strongSelf removePin];
								[strongSelf->_editorLayer setNeedsDisplay];
								[strongSelf->_editorLayer setNeedsLayout];
							}]];
							[alertMove addAction:[UIAlertAction actionWithTitle:@"Move" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
								// okay
							}]];
							[strongSelf.viewController presentViewController:alertMove animated:YES completion:nil];
						}
					}
					break;
					
				case UIGestureRecognizerStateChanged:
					{
						// define the drag function
						void (^dragObject)(CGFloat dragx, CGFloat dragy) = ^(CGFloat dragx, CGFloat dragy) {
							// don't accumulate undo moves
							MapView * strongSelf = weakSelf;
							strongSelf->_pushpinDragTotalMove.x += dragx;
							strongSelf->_pushpinDragTotalMove.y += dragy;
							if ( strongSelf->_gestureDidMove ) {
								[strongSelf.editorLayer.mapData endUndoGrouping];
								strongSelf.silentUndo = YES;
								[strongSelf.editorLayer.mapData undo];
								strongSelf.silentUndo = NO;
								[strongSelf.editorLayer.mapData beginUndoGrouping];
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
							if ( weakSelf.editorLayer.selectedWay && object.isNode ) {
								NSInteger segment;
								OsmBaseObject * hit = [strongSelf dragConnectionForNode:(id)object segment:&segment];
								if ( hit ) {
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
						CGPoint arrow = weakSelf.pushpinView.arrowPoint;
						CGRect screen = weakSelf.bounds;
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
							// scroll the screen to keep pushpin centered
							DisplayLink * displayLink = [DisplayLink shared];
							__block NSTimeInterval prevTime = CACurrentMediaTime();
							[displayLink addName:@"dragScroll" block:^{
								MapView * strongSelf = weakSelf;
								NSTimeInterval now = CACurrentMediaTime();
								NSTimeInterval duration = now - prevTime;
								prevTime = now;
								CGFloat sx = scrollx * duration * 60.0;	// scale to 60 FPS assumption, need to move farther if framerate is slow
								CGFloat sy = scrolly * duration * 60.0;
								[weakSelf adjustOriginBy:CGPointMake(-sx,-sy)];
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
	NSString * text = _editorLayer.selectedPrimary.friendlyDescription;
	text = text ?: @"(new object)";
	_pushpinView.text = text;
}

-(void)interactiveExtendSelectedWayToPoint:(CGPoint)newPoint userSpecified:(BOOL)userSpecified
{
	if ( !_pushpinView )
		return;
	OsmWay * way = _editorLayer.selectedWay;
	OsmNode * node = _editorLayer.selectedNode;
	CGPoint prevPoint = _pushpinView.arrowPoint;

	if ( way && !node ) {
		// add new node at point
		NSInteger segment;
		OsmBaseObject * object = [_editorLayer osmHitTestSelection:prevPoint radius:DefaultHitTestRadius segment:&segment];
		if ( object == nil ) {
			UIAlertController * alertError = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select location",nil)
																				 message:NSLocalizedString(@"Select the location in the way in which to create the new node",nil)
																		  preferredStyle:UIAlertControllerStyleAlert];
			[alertError addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleCancel handler:nil]];
			[self.viewController presentViewController:alertError animated:YES completion:nil];
			return;
		}
		OsmNode * newNode = [_editorLayer createNodeAtPoint:prevPoint];
		[_editorLayer.mapData addNode:newNode toWay:way atIndex:segment+1];
		_editorLayer.selectedNode = newNode;
		[self placePushpinForSelection];

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
		OSMPoint centerPoint = OSMPointFromCGPoint( self.center );
		OsmNode * prevPrevNode = way.nodes.count >= 2 ? way.nodes[way.nodes.count-2] : nil;
		CGPoint prevPrevPoint = prevPrevNode ? [self screenPointForLatitude:prevPrevNode.lat longitude:prevPrevNode.lon birdsEye:YES] : CGPointMake(0,0);

		if ( userSpecified ) {
			// just use the supplied point
		} else if ( hypot( prevPoint.x-centerPoint.x, prevPoint.y-centerPoint.y) > 10.0 &&
			(prevPrevNode==nil || hypot( prevPrevPoint.x-centerPoint.x, prevPrevPoint.y-centerPoint.y) > 10.0 ) )
		{
			// it's far enough from previous point to use
		} else {

			// compute a good place for next point
			if ( way.nodes.count < 2 ) {
				// create 2nd point in the direction of the center of the screen
				BOOL vert = fabs(prevPoint.x - centerPoint.x) < fabs(prevPoint.y - centerPoint.y);
				if ( vert ) {
					newPoint.x = prevPoint.x;
					newPoint.y = fabs(centerPoint.y-prevPoint.y) < 30 ? prevPoint.y + 60 : 2*centerPoint.y - prevPoint.y;
				} else {
					newPoint.x = fabs(centerPoint.x-prevPoint.x) < 30 ? prevPoint.x + 60 : 2*centerPoint.x - prevPoint.x;
					newPoint.y = prevPoint.y;
				}
			} else if ( way.nodes.count == 2 ) {
				// create 3rd point 90 degrees from first 2
				OsmNode * n1 = way.nodes[1-prevIndex];
				CGPoint p1 = [self screenPointForLatitude:n1.lat longitude:n1.lon birdsEye:YES];
				CGPoint delta = { p1.x - prevPoint.x, p1.y - prevPoint.y };
				double len = hypot( delta.x, delta.y );
				if ( len > 100 ) {
					delta.x *= 100/len;
					delta.y *= 100/len;
				}
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
				CGPoint p1 = [self screenPointForLatitude:n1.lat longitude:n1.lon birdsEye:YES];
				CGPoint p2 = [self screenPointForLatitude:n2.lat longitude:n2.lon birdsEye:YES];
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
				[_editorLayer addNode:start toWay:way atIndex:nextIndex];
				_editorLayer.selectedWay = way;
				_editorLayer.selectedNode = nil;
				[self placePushpinAtPoint:s object:way];
				return;
			}
		}
		OsmNode * node2 = [_editorLayer createNodeAtPoint:newPoint];
		[_editorLayer addNode:node2 toWay:way atIndex:nextIndex];
		_editorLayer.selectedWay = way;
		_editorLayer.selectedNode = node2;
		[self placePushpinForSelection];
	}
}
#endif

-(void)dropPinAtPoint:(CGPoint)dropPoint userSpecified:(BOOL)userSpecified
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
			[self interactiveExtendSelectedWayToPoint:dropPoint userSpecified:userSpecified ];
		} else if ( _editorLayer.selectedPrimary == nil && _pushpinView ) {
			// just dropped a pin, so convert it into a way
			[self interactiveExtendSelectedWayToPoint:dropPoint userSpecified:userSpecified];
		} else if ( _editorLayer.selectedWay && _editorLayer.selectedNode == nil ) {
			// add a new node to a way
			[self interactiveExtendSelectedWayToPoint:dropPoint userSpecified:userSpecified];
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

		[self placePushpinAtPoint:dropPoint object:nil];
	}
#endif
}
-(IBAction)dropPin:(id)sender
{
	CGPoint point = CGRectCenter( self.bounds );
	[self dropPinAtPoint:point userSpecified:NO];
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
		[self placePushpinForSelection];
	} else {
		// update current object
		OsmBaseObject * object = _editorLayer.selectedPrimary;
		[_editorLayer.mapData setTags:tags forObject:object];
		[self refreshPushpinText];
		[self refreshNoteButtonsFromDatabase];
	}
	[_editorLayer setNeedsDisplay];
	[_editorLayer setNeedsLayout];
	_confirmDrag = NO;
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
	dashAnimation.repeatCount = 100000;
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
		OsmNode * origNode = _editorLayer.selectedPrimary.isNode;
		CGPoint pt = [self screenPointForLatitude:origNode.lat longitude:origNode.lon birdsEye:YES];
		pt.x += 20;
		pt.y += 20;
		OsmNode * newNode = [_editorLayer createNodeAtPoint:pt];
		[_editorLayer.mapData setTags:origNode.tags forObject:newNode];
		_editorLayer.selectedNode = newNode;
		return;
	}
	if ( _editorLayer.selectedPrimary.isWay ) {
		OsmWay * origWay = _editorLayer.selectedPrimary.isWay;
		OsmWay * newWay = nil;
		NSInteger last = origWay.nodes.lastObject == origWay.nodes[0] ? origWay.nodes.count : -1;
		for ( OsmNode * origNode in origWay.nodes ) {
			if ( --last == 0 ) {
				[_editorLayer.mapData addNode:newWay.nodes[0] toWay:newWay atIndex:newWay.nodes.count];
				break;
			}
			CGPoint pt = [self screenPointForLatitude:origNode.lat longitude:origNode.lon birdsEye:YES];
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
		return hit.isWay != NULL;
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


#pragma mark Notes

-(void)updateNotesWithDelay:(CGFloat)delay
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
			[_notesDatabase.dict enumerateKeysAndObjectsUsingBlock:^(id key, OsmNote * note, BOOL *stop) {
				UIButton * button = _notesViewDict[ note.uid ];
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
						button.titleLabel.font			= [UIFont boldSystemFontOfSize:17];
						button.titleLabel.textColor		= UIColor.whiteColor;
						button.titleLabel.textAlignment	= NSTextAlignmentCenter;
						NSString * title = note.isFixme ? @"F" : note.isWaypoint ? @"W" : note.isKeepRight ? @"R" : @"N";
						[button setTitle:title forState:UIControlStateNormal];
						button.tag = note.uid.integerValue;
						[self addSubview:button];
						[_notesViewDict setObject:button forKey:note.uid];
					}

					if ( [note.status isEqualToString:@"closed"] ) {
						[button removeFromSuperview];
					} else if ( note.isFixme && [self.editorLayer.mapData objectWithExtendedIdentifier:note.noteId].tags[@"fixme"] == nil ) {
						[button removeFromSuperview];
					} else {
						double offsetX = note.isKeepRight ? 0.00001 : 0.0;
						CGPoint pos = [self screenPointForLatitude:note.lat longitude:note.lon+offsetX birdsEye:YES];
						if ( isinf(pos.x) || isinf(pos.y) )
							return;

						CGRect rc = button.bounds;
						rc = CGRectOffset( rc, pos.x-rc.size.width/2, pos.y-rc.size.height/2 );
						button.frame = rc;
					}
				} else {
					[button removeFromSuperview];
					[_notesViewDict removeObjectForKey:note.uid];
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
	OsmNote * note = _notesDatabase.dict[ @(button.tag) ];
	if ( note == nil )
		return;

	if ( note.isWaypoint || note.isKeepRight ) {
		if ( !_editorLayer.hidden ) {
			OsmBaseObject * object = [_editorLayer.mapData objectWithExtendedIdentifier:note.noteId];
			if ( object ) {
				_editorLayer.selectedNode		= object.isNode;
				_editorLayer.selectedWay		= object.isWay;
				_editorLayer.selectedRelation	= object.isRelation;

				if ( object.isWay ) {
					OSMPoint pt = { note.lon, note.lat };
					pt = [object.isWay pointOnWayForPoint:pt];
					CGPoint point = [self screenPointForLatitude:pt.y longitude:pt.x birdsEye:YES];
					[self placePushpinAtPoint:point object:object];
				} else {
					[self placePushpinForSelection];
				}
			}
		}
		OsmNoteComment * comment = note.comments.lastObject;
		NSString * title = note.isWaypoint ? @"Waypoint" : @"Keep Right";

#if 0
		// use our custom alertview
		HtmlAlertViewController * alert = [self.viewController.storyboard instantiateViewControllerWithIdentifier:@"HtmlAlert"];
		[self.window addSubview:alert.view];
		alert.heading.text			= title;
		alert.htmlText				= comment.text;
		_alertKeepRight = (id)alert;	// so we don't get deallocated
		__weak HtmlAlertViewController * weakAlert = alert;
		[alert addButton:@"OK" callback:^{
			[weakAlert.view removeFromSuperview];
			_alertKeepRight = nil;
		}];
		[alert addButton:@"Ignore" callback:^{
			// they want to hide this button from now on
			[_notesDatabase ignoreNote:_currentNote];
			[self refreshNoteButtonsFromDatabase];
			_editorLayer.selectedNode = nil;
			_editorLayer.selectedWay = nil;
			_editorLayer.selectedRelation = nil;
			[self removePin];
			[weakAlert.view removeFromSuperview];
			_alertKeepRight = nil;
		}];
#else
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
		[self.viewController presentViewController:alertKeepRight animated:YES completion:nil];
#endif
	} else if ( note.isFixme ) {
		OsmBaseObject * object = [_editorLayer.mapData objectWithExtendedIdentifier:note.noteId];
		_editorLayer.selectedNode		= object.isNode;
		_editorLayer.selectedWay		= object.isWay;
		_editorLayer.selectedRelation	= object.isRelation;
		[self presentTagEditor:nil];
	} else {
		[self.viewController performSegueWithIdentifier:@"NotesSegue" sender:note];
	}
}

#pragma mark Gestures


#if TARGET_OS_IPHONE

static NSString * const DisplayLinkPanning	= @"Panning";

// disable gestures inside toolbar buttons
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
	// http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer
	if ( [touch.view isKindOfClass:[UIControl class]] || [touch.view isKindOfClass:[UIToolbar class]] ) {
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
	if ( [gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && otherGestureRecognizer != _addNodeButtonLongPressGestureRecognizer )
		return NO;
	if ( [otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && gestureRecognizer != _addNodeButtonLongPressGestureRecognizer )
		return NO;
	return YES;
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
		CGPoint translation = [pan translationInView:self];
		[self adjustOriginBy:translation];
		[pan setTranslation:CGPointMake(0,0) inView:self];
	} else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled ) {	// cancelled occurs when we throw an error dialog
		// finish pan with inertia
		CGPoint initialVelecity = [pan velocityInView:self];
		CFTimeInterval startTime = CACurrentMediaTime();
		double duration = 0.5;
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
		[self updateNotesWithDelay:duration];
	} else if ( pan.state == UIGestureRecognizerStateFailed ) {
		DLog( @"pan gesture failed" );
	} else {
		DLog( @"pan gesture %d", (int)pan.state);
	}
}
- (void)handlePinchGesture:(UIPinchGestureRecognizer *)pinch
{
	if ( pinch.state == UIGestureRecognizerStateChanged ) {
		self.userOverrodeLocationZoom = YES;

		DisplayLink * displayLink = [DisplayLink shared];
		[displayLink removeName:DisplayLinkPanning];

		CGPoint zoomCenter = [pinch locationInView:self];
		[self adjustZoomBy:pinch.scale aroundScreenPoint:zoomCenter];

		[pinch setScale:1.0];
	} else if ( pinch.state == UIGestureRecognizerStateEnded ) {
		[self updateNotesWithDelay:0];
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
		[self updateNotesWithDelay:0];
	}
}
- (IBAction)handleTapGesture:(UITapGestureRecognizer *)tap
{
	if ( tap.state == UIGestureRecognizerStateEnded ) {
		CGPoint point = [tap locationInView:self];
		BOOL extendedCommand = NO;
		if ( tap.numberOfTapsRequired == 1 ) {

			if ( _addNodeButtonPressed ) {
				if ( _addNodeButtonPressed )
					_addNodeButtonPressed -= 1.0;	// ensure tap event doesn't trigger
				[self dropPinAtPoint:point userSpecified:YES];
			} else {
				[self singleClick:point extendedCommand:extendedCommand];
			}
		}
	}
}

-(void)addNodeButtonLongPressHandler:(UILongPressGestureRecognizer *)recognizer
{
	switch ( recognizer.state ) {
		case UIGestureRecognizerStateBegan:
			_addNodeButtonPressed = CACurrentMediaTime();
			break;
		case UIGestureRecognizerStateEnded:
			if ( CACurrentMediaTime() - _addNodeButtonPressed < 0.5 ) {
				// treat as tap
				[self dropPin:self];
			}
			_addNodeButtonPressed = 0.0;
			break;
		case UIGestureRecognizerStateCancelled:
		case UIGestureRecognizerStateFailed:
			_addNodeButtonPressed = 0.0;
			break;
		default:
			break;
	}
}

- (IBAction)handleLongPressGesture:(UILongPressGestureRecognizer *)longPress
{
	if ( longPress.state == UIGestureRecognizerStateBegan && !_editorLayer.hidden ) {
		CGPoint point = [longPress locationInView:self];

		NSArray * objects = [self.editorLayer osmHitTestMultiple:point radius:DefaultHitTestRadius];
		if ( objects.count == 0 )
			return;
		UIAlertController * multiSelectSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Select Object",nil) message:nil preferredStyle:UIAlertControllerStyleActionSheet];
		for ( OsmBaseObject * object in objects ) {
			NSString * title = object.friendlyDescription;
			[multiSelectSheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
				// processing for selecting one of multipe objects
				if ( object.isNode ) {
					for ( OsmBaseObject * obj in objects ) {
						if ( obj.isWay && [obj.isWay.nodes containsObject:object] ) {
							// select the way containing the node, then select the node in the way
							[_editorLayer setSelectedWay:obj.isWay];
							break;
						}
					}
					[_editorLayer setSelectedNode:object.isNode];
					[self placePushpinForSelection];
				} else if ( object.isWay ) {
					[_editorLayer setSelectedWay:object.isWay];
					CLLocationCoordinate2D latLon = [self longitudeLatitudeForScreenPoint:point birdsEye:YES];
					OSMPoint latLon2 = [object.isWay pointOnWayForPoint:OSMPointMake(latLon.longitude,latLon.latitude)];
					CGPoint pos = [self screenPointForLatitude:latLon2.y longitude:latLon2.x birdsEye:YES];
					[self placePushpinAtPoint:pos object:object];
				}
			}]];
		}
		[multiSelectSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
		[self.viewController presentViewController:multiSelectSheet animated:YES completion:nil];
		// set position
		CGRect rc = { point.x, point.y, 0, 0 };
		multiSelectSheet.popoverPresentationController.sourceView = self;
		multiSelectSheet.popoverPresentationController.sourceRect = rc;
	}
}

- (IBAction)handleRotationGesture:(UIRotationGestureRecognizer *)rotationGesture
{
	// Rotate object on screen
	if ( _isRotateObjectMode ) {
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
			for ( OsmNode * node in _editorLayer.selectedWay.nodeSet ) {
				CGPoint pt = [self screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
				OSMPoint diff = { pt.x - axis.x, pt.y - axis.y };
				double radius = hypot( diff.x, diff.y );
				double angle = atan2( diff.y, diff.x );
				angle += delta;
				OSMPoint new = { axis.x + radius * cos(angle), axis.y + radius * sin(angle) };
				CGPoint dist = { new.x - pt.x, -(new.y - pt.y) };
				[_editorLayer adjustNode:node byDistance:dist];
			}
//			rotationGesture.rotation = 0.0;
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
#if FRAMERATE_TEST
			DisplayLink * displayLink = [DisplayLink shared];
			[displayLink removeName:@"autoScroll"];
#endif
		} else if ( rotationGesture.state == UIGestureRecognizerStateChanged ) {
			CGPoint centerPoint = [rotationGesture locationInView:self];
			CGFloat angle = rotationGesture.rotation;
			[self rotateBy:angle aroundScreenPoint:centerPoint];
			rotationGesture.rotation = 0.0;
		} else if ( rotationGesture.state == UIGestureRecognizerStateEnded ) {
			[self updateNotesWithDelay:0];
		}
	}
}


- (IBAction)handleTwoFingerPanGesture:(UIPanGestureRecognizer *)pan
{
	if ( !self.enableBirdsEye )
		return;

	CGPoint translation = [pan translationInView:self];
	double delta = -translation.y/40 / 180 * M_PI;

	[self rotateBirdsEyeBy:delta];
}

- (void)updateSpeechBalloonPosition
{
}
#endif


#pragma mark Mouse movment

- (void)singleClick:(CGPoint)point extendedCommand:(BOOL)extendedCommand
{
	OsmBaseObject * hit = nil;
	_grabbedObject = nil;

	// disable rotation if in action
	if ( _isRotateObjectMode ) {
		[self endObjectRotation];
	}

	if ( _editorLayer.addNodeInProgress || _editorLayer.addWayInProgress ) {

		// create node/way
		if ( _editorLayer.addNodeInProgress ) {

			// check if connecting to existing way
			NSInteger segment;
			hit = [_editorLayer osmHitTest:point radius:DefaultHitTestRadius segment:&segment ignoreList:nil];

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
			hit = [_editorLayer osmHitTest:point radius:DefaultHitTestRadius segment:&segment ignoreList:nil];
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
			hit = [_editorLayer osmHitTestNodeInSelection:point radius:DefaultHitTestRadius];
		}
		if ( hit ) {
			_editorLayer.selectedNode = (id)hit;
			[_delegate mapviewSelectionChanged:hit];
			_grabbedObject = (id)hit;

		} else {

			// hit test anything
			hit = [_editorLayer osmHitTest:point radius:DefaultHitTestRadius];

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
				point = [self screenPointForLatitude:node.lat longitude:node.lon birdsEye:YES];
			} else if ( _editorLayer.selectedPrimary.isWay ) {
				// when tapping a way select the point on the way closest to the tap
				CLLocationCoordinate2D latLon = [self longitudeLatitudeForScreenPoint:point birdsEye:YES];
				OSMPoint pt = { latLon.longitude, latLon.latitude };
				pt = [_editorLayer.selectedWay pointOnWayForPoint:pt];
				point = [self screenPointForLatitude:pt.y longitude:pt.x birdsEye:YES];
				_confirmDrag = (_editorLayer.selectedPrimary.modifyCount == 0);	// if they later try to drag this way ask them if they really wanted to
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

#if !TARGET_OS_IPHONE

- (void)doubleClick:(CGPoint)point
{
	OsmBaseObject * selection = [_editorLayer osmHitTestSelection:point];
	if ( selection ) {

		// open tag editor window
		[[NSCursor arrowCursor] set];
		[_delegate doubleClickSelection:selection];

	} else {

		// zoom in on point
		CGPoint center = CGRectCenter( self.bounds );
		point.x = center.x - point.x;
		point.y = center.y - point.y;
		[self adjustOriginBy:point];
		[self adjustZoomBy:2.0];
	}
}

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
			CGPoint center = CGRectCenter( self.bounds );
			CGPoint delta = { center.x - point.x, center.y - point.y };
			delta.x *= ratio - 1;
			delta.y *= ratio - 1;
			[self adjustOriginBy:delta];
		}
		[self adjustZoomBy:ratio];
	} else {
		// scroll
		CGPoint delta = CGPointMake( event.scrollingDeltaX, event.scrollingDeltaY );
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
#endif	// desktop

@end
