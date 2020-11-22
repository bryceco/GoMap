//
//  FirstViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "AerialList.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "MainViewController.h"
#import "MapView.h"
#import "NotesTableViewController.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "PushPinView.h"
#import "SpeechBalloonView.h"


#define USER_MOVABLE_BUTTONS	0

@interface MainViewController ()
@property (weak, nonatomic) IBOutlet UIButton *settingsButton;
@property (weak, nonatomic) IBOutlet UIButton *displayButton;
@end

@implementation MainViewController
@synthesize buttonLayout = _buttonLayout;

- (void)updateUndoRedoButtonState
{
	_undoButton.enabled = self.mapView.editorLayer.mapData.canUndo && !self.mapView.editorLayer.hidden;
	_redoButton.enabled = self.mapView.editorLayer.mapData.canRedo && !self.mapView.editorLayer.hidden;
	_uploadButton.hidden = !_undoButton.enabled;
	_undoRedoView.hidden = !_undoButton.enabled && !_redoButton.enabled;
}


- (void)updateUploadButtonState
{
	const int yellowCount	= 25;
	const int redCount		= 50;
	NSInteger changeCount = [self.mapView.editorLayer.mapData modificationCount];
	UIColor * color = nil;
	if ( changeCount < yellowCount ) {
		color = nil;														// default color
	} else if ( changeCount < redCount ) {
		color = [UIColor colorWithRed:1.0 green:0.55 blue:0.0 alpha:1.0];	// yellow
	} else {
		color = UIColor.redColor;	// red
	}
	_uploadButton.tintColor = color;
	_uploadButton.enabled = changeCount > 0;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.mapView.mainViewController = self;

	AppDelegate * delegate = AppDelegate.shared;
	delegate.mapView = self.mapView;

	// undo/redo buttons
	[self updateUndoRedoButtonState];
	[self updateUploadButtonState];

	__weak __auto_type weakSelf = self;
	[self.mapView.editorLayer.mapData addChangeCallback:^{
		[weakSelf updateUndoRedoButtonState];
		[weakSelf updateUploadButtonState];
	}];
    
    [self setupAccessibility];

	// long press for quick access to aerial imagery
	UILongPressGestureRecognizer * longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(displayButtonLongPressGesture:)];
	[self.displayButton addGestureRecognizer:longPress];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:NULL];
}

- (void)setupAccessibility
{
    self.locationButton.accessibilityIdentifier = @"location_button";
    
    _undoButton.accessibilityLabel = NSLocalizedString(@"Undo",nil);
    _redoButton.accessibilityLabel = NSLocalizedString(@"Redo",nil);
    _settingsButton.accessibilityLabel = NSLocalizedString(@"Settings",nil);
    _uploadButton.accessibilityLabel = NSLocalizedString(@"Upload your changes",nil);
    _displayButton.accessibilityLabel = NSLocalizedString(@"Display options",nil);
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	self.navigationController.navigationBarHidden = YES;

	// update button layout constraints
	[NSUserDefaults.standardUserDefaults registerDefaults:@{ @"buttonLayout" : @(BUTTON_LAYOUT_ADD_ON_RIGHT) }];
	self.buttonLayout = (BUTTON_LAYOUT) [NSUserDefaults.standardUserDefaults integerForKey:@"buttonLayout"];

	// update button styling
	NSArray * buttons = @[
		_undoRedoView,
		_locationButton,
		_undoButton,
		_redoButton,
		_mapView.addNodeButton,
		_mapView.compassButton,
		_mapView.centerOnGPSButton,
		_settingsButton,
		_uploadButton,
		_displayButton,
		_searchButton
	];
	for ( UIButton * button in buttons ) {

		// corners
		if ( button != _mapView.compassButton ) {
			button.layer.cornerRadius	= button == _mapView.addNodeButton ? 30.0 : 10.0;
		}
		// shadow
		if ( button.superview != _undoRedoView ) {
			button.layer.shadowColor 	= UIColor.blackColor.CGColor;
			button.layer.shadowOffset	= CGSizeMake(0,0);
			button.layer.shadowRadius	= 3;
			button.layer.shadowOpacity	= 0.5;
			button.layer.masksToBounds	= NO;
		}
		// image blue tint
		if ( button != _undoRedoView && button != _mapView.compassButton ) {
			UIImage * image = [button.currentImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
			[button setImage:image forState:UIControlStateNormal];
			if (@available(iOS 13.0, *)) {
				button.tintColor = UIColor.linkColor;
			} else {
				button.tintColor = UIColor.systemBlueColor;
			}
			if ( button == _mapView.addNodeButton )
				button.imageEdgeInsets = UIEdgeInsetsMake(15, 15, 15, 15);	// resize images on button to be smaller
			else
				button.imageEdgeInsets = UIEdgeInsetsMake(9, 9, 9, 9);	// resize images on button to be smaller
		}

		// normal background color
		[self makeButtonNormal:button];

		// background selection color
		if ( button != _undoRedoView ) {
			[button addTarget:self action:@selector(makeButtonHighlight:) forControlEvents:UIControlEventTouchDown];
			[button addTarget:self action:@selector(makeButtonNormal:) forControlEvents:UIControlEventTouchUpInside];
			[button addTarget:self action:@selector(makeButtonNormal:) forControlEvents:UIControlEventTouchUpOutside];
			[button addTarget:self action:@selector(makeButtonNormal:) forControlEvents:UIControlEventTouchCancel];

			button.showsTouchWhenHighlighted = YES;
		}
	}
}
-(void)makeButtonHighlight:(UIButton *)button
{
	if (@available(iOS 13.0, *)) {
		button.backgroundColor = UIColor.secondarySystemBackgroundColor;
	} else {
		button.backgroundColor = UIColor.lightGrayColor;
	}
}
-(void)makeButtonNormal:(UIButton *)button
{
	if (@available(iOS 13.0, *)) {
		button.backgroundColor = UIColor.systemBackgroundColor;
	} else {
		button.backgroundColor = UIColor.whiteColor;
	}
}

#if USER_MOVABLE_BUTTONS
-(void)removeConstrainsOnView:(UIView *)view
{
	UIView * superview = view.superview;
	while ( superview != nil ) {
		for ( NSLayoutConstraint * c in superview.constraints ) {
			if ( c.firstItem == view || c.secondItem == view ) {
				[superview removeConstraint:c];
			}
		}
		superview = superview.superview;
	}
	for ( NSLayoutConstraint * c in [view.constraints copy] ) {
		if ( ((UIView *)c.firstItem).superview == view || ((UIView *)c.secondItem).superview == view ) {
			// skip
		} else {
			[view removeConstraint:c];
		}
	}
}

-(void)makeMovableButtons
{
	NSArray * buttons = @[
//		_mapView.editControl,
		_undoRedoView,
		_locationButton,
		_searchButton,
		_mapView.addNodeButton,
		_settingsButton,
		_uploadButton,
		_displayButton,
		_mapView.compassButton,
		_mapView.helpButton,
		_mapView.centerOnGPSButton,
//		_mapView.rulerView,
	];
	// remove layout constraints
	for ( UIButton * button in buttons ) {
		[self removeConstrainsOnView:button];
		button.translatesAutoresizingMaskIntoConstraints = YES;
	}
	for ( UIButton * button in buttons ) {
		UIPanGestureRecognizer * panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(buttonPan:)];
		// panGesture.delegate = self;
		[button addGestureRecognizer:panGesture];
	}
	NSString * message = @"This build has a temporary feature: Drag the buttons in the UI to new locations that looks and feel best for you.\n\n"
						@"* Submit your preferred layouts either via email or on GitHub.\n\n"
						@"* Positions reset when the app terminates\n\n"
						@"* Orientation changes are not supported\n\n"
						@"* Buttons won't move when they're disabled (undo/redo, upload)";
	UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"Attention Testers!" message:message preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction * ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action){
		[alert dismissViewControllerAnimated:YES completion:nil];
	}];
	[alert addAction:ok];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)buttonPan:(UIPanGestureRecognizer *)pan
{
	if ( pan.state == UIGestureRecognizerStateBegan ) {
	} else if ( pan.state == UIGestureRecognizerStateChanged ) {
		pan.view.center = [pan locationInView:self.view];
	} else {
	}
}
#endif

-(BUTTON_LAYOUT)buttonLayout
{
	return _buttonLayout;
}

-(void)setButtonLayout:(BUTTON_LAYOUT)buttonLayout
{
	_buttonLayout = buttonLayout;

	[NSUserDefaults.standardUserDefaults setInteger:_buttonLayout forKey:@"buttonLayout"];

	BOOL left = buttonLayout == BUTTON_LAYOUT_ADD_ON_LEFT;
	NSLayoutAttribute attribute = left ? NSLayoutAttributeLeading : NSLayoutAttributeTrailing;
	UIButton * addButton = _mapView.addNodeButton;
	UIView * superview = addButton.superview;
	for ( NSLayoutConstraint * c in superview.constraints ) {
		if ( c.firstItem == addButton &&
			[c.secondItem isKindOfClass:[UILayoutGuide class]] &&
			(c.firstAttribute == NSLayoutAttributeLeading || c.firstAttribute == NSLayoutAttributeTrailing) &&
			(c.secondAttribute == NSLayoutAttributeLeading || c.secondAttribute == NSLayoutAttributeTrailing) )
		{
			[superview removeConstraint:c];
			NSLayoutConstraint * c2 = [NSLayoutConstraint constraintWithItem:c.firstItem
																   attribute:attribute
																   relatedBy:NSLayoutRelationEqual
																	  toItem:c.secondItem
																   attribute:attribute
																  multiplier:1.0
																	constant:left ? fabs(c.constant) : -fabs(c.constant)];
			[superview addConstraint:c2];
			return;
		}
	}
	assert(NO);	// didn't find the constraint
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

#if USER_MOVABLE_BUTTONS
	[self makeMovableButtons];
#endif

	// this is necessary because we need the frame to be set on the view before we set the previous lat/lon for the view
	[_mapView viewDidAppear];

#if 0 && DEBUG
	SpeechBalloonView * speech = [[SpeechBalloonView alloc] initWithText:@"Press here to create a new node,\nor to begin a way"];
	[speech setTargetView:_toolbar];
	[self.view addSubview:speech];
#endif
}

-(void)addNodeQuick:(UILongPressGestureRecognizer *)recognizer
{
	if ( recognizer.state == UIGestureRecognizerStateBegan ) {
		NSLog(@"go");
	}
}

- (void)installGestureRecognizer:(UIGestureRecognizer *)gesture onButton:(UIButton *)button
{
	if ( [button respondsToSelector:@selector(view)] ) {
		UIView * view = [(id)button view];
		if ( view.gestureRecognizers.count == 0 ) {
			[view addGestureRecognizer:gesture];
		}
	}
}

-(void)displayButtonLongPressGesture:(UILongPressGestureRecognizer *)recognizer
{
	if ( recognizer.state == UIGestureRecognizerStateBegan ) {
		// show the most recently used aerial imagery
		AerialList * aerialList = self.mapView.customAerials;
		UIAlertController * actionSheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Recent Aerial Imagery", @"Alert title message")
																			  message:nil
																	   preferredStyle:UIAlertControllerStyleActionSheet];
		for ( AerialService * service in aerialList.recentlyUsed ) {
			[actionSheet addAction:[UIAlertAction actionWithTitle:service.name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
				aerialList.currentAerial = service;
				[self.mapView setAerialTileService:service];
			}]];
		}
		[actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:actionSheet animated:YES completion:nil];
	}
}

- (void)didReceiveMemoryWarning
{
	[super didReceiveMemoryWarning];
	
	DLog(@"memory warning: %f MB used", MemoryUsedMB() );

	[self.mapView flashMessage:NSLocalizedString(@"Low memory: clearing cache",nil)];

	[_mapView.editorLayer didReceiveMemoryWarning];
}

-(void)setGpsState:(GPS_STATE)state
{
	if ( self.mapView.gpsState != state ) {
		self.mapView.gpsState = state;

		// update GPS icon
		NSString * imageName = (self.mapView.gpsState == GPS_STATE_NONE) ? @"location2" : @"location.fill";
		UIImage * image = [UIImage imageNamed:imageName];
		image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		[self.locationButton setImage:image forState:UIControlStateNormal];
	}
}

-(IBAction)toggleLocation:(id)sender
{
	switch (self.mapView.gpsState) {
		case GPS_STATE_NONE:
			[self setGpsState:GPS_STATE_LOCATION];
			[self.mapView rotateToNorth];
			break;
		case GPS_STATE_LOCATION:
		case GPS_STATE_HEADING:
			[self setGpsState:GPS_STATE_NONE];
			break;
	}
}

-(void)applicationDidEnterBackground:(id)sender
{
	AppDelegate * appDelegate = AppDelegate.shared;
	if ( appDelegate.mapView.gpsInBackground && appDelegate.mapView.enableGpxLogging ) {
		// allow GPS collection in background
	} else {
		// turn off GPS tracking
		[self setGpsState:GPS_STATE_NONE];
	}
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
		CGRect rc = self.mapView.frame;
		rc.size = size;
		self.mapView.frame = rc;
	} completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
	}];
}

#if 1 // FIXME - not sure if we still need something like this after removing the toolbar
// disable gestures inside toolbar buttons
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
	// http://stackoverflow.com/questions/3344341/uibutton-inside-a-view-that-has-a-uitapgesturerecognizer

	if ( [touch.view isKindOfClass:[UIControl class]] || [touch.view isKindOfClass:[UIToolbar class]] ) {
		// we touched a button, slider, or other UIControl
		return NO; // ignore the touch
	}
    return YES; // handle the touch
}
#endif

-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if ( [sender isKindOfClass:[OsmNote class]] ) {
        NotesTableViewController *con;
        if ([segue.destinationViewController isKindOfClass:[NotesTableViewController class]]) {
            /// The `NotesTableViewController` is presented directly.
            con = segue.destinationViewController;
        } else if ([segue.destinationViewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *navigationController = segue.destinationViewController;
            if ([navigationController.viewControllers.firstObject isKindOfClass:[NotesTableViewController class]]) {
                /// The `NotesTableViewController` is wrapped in an `UINavigationController´.
                con = navigationController.viewControllers.firstObject;
            }
        }
        
		con.note = sender;
        con.mapView = _mapView;
	}
}

@end
