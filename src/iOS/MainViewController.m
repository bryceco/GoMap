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

	[self setButtonAppearances];

#if TARGET_OS_MACCATALYST
	// mouseover support for Mac Catalyst:
	UIHoverGestureRecognizer * hover = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(hover:)];
	[_mapView addGestureRecognizer:hover];

	// right-click support for Mac Catalyst:
	UIContextMenuInteraction * rightClick = [[UIContextMenuInteraction alloc] initWithDelegate:self];
	[_mapView addInteraction:rightClick];
#endif
}

-(void)hover:(UIGestureRecognizer *)recognizer
{
	CGPoint loc = [recognizer locationInView:_mapView];
	NSInteger segment = 0;
	OsmBaseObject * hit = nil;
	if ( recognizer.state == UIGestureRecognizerStateChanged ) {
		if ( _mapView.editorLayer.selectedWay ) {
			hit = [_mapView.editorLayer osmHitTestNodeInSelectedWay:loc radius:DefaultHitTestRadius];
		}
		if ( hit == nil ) {
			hit = [_mapView.editorLayer osmHitTest:loc radius:DefaultHitTestRadius isDragConnect:NO ignoreList:nil segment:&segment];
		}
		if ( hit == _mapView.editorLayer.selectedNode || hit == _mapView.editorLayer.selectedWay || hit.isRelation )
			hit = nil;
	}
	[_mapView blinkObject:hit segment:segment];
}

-(UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location
{
	[_mapView rightClickAtLocation:location];
	return nil;
}

#if TARGET_OS_MACCATALYST
-(void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
	if (@available(macCatalyst 13.4, *)) {
		for ( UIPress * press in presses ) {
			UIKey * key = [press key];
			const CGFloat ARROW_KEY_DELTA = 256;;
			switch ( key.keyCode ) {
				case UIKeyboardHIDUsageKeyboardRightArrow:
					[_mapView adjustOriginBy:CGPointMake(-ARROW_KEY_DELTA, 0)];
					break;
				case UIKeyboardHIDUsageKeyboardLeftArrow:
					[_mapView adjustOriginBy:CGPointMake(ARROW_KEY_DELTA, 0)];
					break;
				case UIKeyboardHIDUsageKeyboardDownArrow:
					[_mapView adjustOriginBy:CGPointMake(0, -ARROW_KEY_DELTA)];
					break;
				case UIKeyboardHIDUsageKeyboardUpArrow:
					[_mapView adjustOriginBy:CGPointMake(0, ARROW_KEY_DELTA)];
					break;
				default:
					break;
			}
		}
	}
}
#endif

-(void)setButtonAppearances
{
	// update button styling
	NSArray * buttons = @[
		// these aren't actually buttons, but they get similar tinting and shadows
		_mapView.editControl,
		_undoRedoView,
		// these are buttons
		_locationButton,
		_undoButton,
		_redoButton,
		_mapView.addNodeButton,
		_mapView.compassButton,
		_mapView.centerOnGPSButton,
		_mapView.helpButton,
		_settingsButton,
		_uploadButton,
		_displayButton,
		_searchButton
	];
	for ( UIView * view in buttons ) {

		// corners
		if ( view == _mapView.compassButton ||
			 view == _mapView.editControl )
		{
			// these buttons take care of themselves
		} else if ( view == _mapView.helpButton ||
					view == _mapView.addNodeButton )
		{
			// The button is a circle.
			view.layer.cornerRadius = view.bounds.size.width / 2;
		} else {
			// rounded corners
			view.layer.cornerRadius	= 10.0;
		}
		// shadow
		if ( view.superview != _undoRedoView ) {
			view.layer.shadowColor 	= UIColor.blackColor.CGColor;
			view.layer.shadowOffset	= CGSizeMake(0,0);
			view.layer.shadowRadius	= 3;
			view.layer.shadowOpacity	= 0.5;
			view.layer.masksToBounds	= NO;
		}
		// image blue tint
		if ( [view isKindOfClass:[UIButton class]] ) {
			UIButton * button = (UIButton *)view;
			if ( button != _mapView.compassButton && button != _mapView.helpButton ) {
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
		}

		// normal background color
		[self makeButtonNormal:view];

		// background selection color
		if ( [view isKindOfClass:[UIButton class]] ) {
			UIButton * button = (UIButton *)view;
			[button addTarget:self action:@selector(makeButtonHighlight:) forControlEvents:UIControlEventTouchDown];
			[button addTarget:self action:@selector(makeButtonNormal:) forControlEvents:UIControlEventTouchUpInside];
			[button addTarget:self action:@selector(makeButtonNormal:) forControlEvents:UIControlEventTouchUpOutside];
			[button addTarget:self action:@selector(makeButtonNormal:) forControlEvents:UIControlEventTouchCancel];

			button.showsTouchWhenHighlighted = YES;
		}
	}
}

-(void)makeButtonHighlight:(UIView *)button
{
	if (@available(iOS 13.0, *)) {
		button.backgroundColor = UIColor.secondarySystemBackgroundColor;
	} else {
		button.backgroundColor = UIColor.lightGrayColor;
	}
}
-(void)makeButtonNormal:(UIView *)button
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
		if ( c.firstItem != addButton )
			continue;
		if ( !([c.secondItem isKindOfClass:[UILayoutGuide class]] || [c.secondItem isKindOfClass:[UIView class]]) )
			continue;;
		if ( (c.firstAttribute == NSLayoutAttributeLeading || c.firstAttribute == NSLayoutAttributeTrailing) &&
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


#pragma mark Keyboard shortcuts

-(BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
	if ( action == @selector(undo:) )
		return self.mapView.editorLayer.mapData.canUndo;
	if ( action == @selector(redo:) )
		return self.mapView.editorLayer.mapData.canRedo;
	if ( action == @selector(copy:) )
		return self.mapView.editorLayer.selectedPrimary != nil;
	if ( action == @selector(paste:) )
		return self.mapView.editorLayer.selectedPrimary != nil && self.mapView.editorLayer.canPasteTags;
	if ( action == @selector(delete:) )
		return self.mapView.editorLayer.selectedPrimary && !self.mapView.editorLayer.selectedRelation;
	if ( action == @selector(showHelp:) )
		return YES;
	return NO;
}

-(void)undo:(id)sender
{
	[self.mapView undo:sender];
}
-(void)redo:(id)sender
{
	[self.mapView redo:sender];
}
-(void)copy:(id)sender
{
	[self.mapView performEditAction:ACTION_COPYTAGS];
}
-(void)paste:(id)sender
{
	[self.mapView performEditAction:ACTION_PASTETAGS];
}
-(void)delete:(id)sender
{
	[self.mapView performEditAction:ACTION_DELETE];
}
-(void)showHelp:(id)sender
{
	[self openHelp];
}

#pragma mark Gesture recognizers

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
				if ( _mapView.viewState == MAPVIEW_EDITOR )
					_mapView.viewState = MAPVIEW_EDITORAERIAL;
				else if ( _mapView.viewState == MAPVIEW_MAPNIK )
					_mapView.viewState = MAPVIEW_EDITORAERIAL;
			}]];
		}

		// add options for changing display
		NSString * prefix = @"🌐 ";
		UIAlertAction * editorOnly = [UIAlertAction actionWithTitle:[prefix stringByAppendingString:NSLocalizedString(@"Editor only",nil)]
															  style:UIAlertActionStyleDefault
															handler:^(UIAlertAction * _Nonnull action) {
			_mapView.viewState = MAPVIEW_EDITOR;
		}];
		UIAlertAction * aerialOnly = [UIAlertAction actionWithTitle:[prefix stringByAppendingString:NSLocalizedString(@"Aerial only",nil)]
															  style:UIAlertActionStyleDefault
															handler:^(UIAlertAction * _Nonnull action) {
			_mapView.viewState = MAPVIEW_AERIAL;
		}];
		UIAlertAction * editorAerial = [UIAlertAction actionWithTitle:[prefix stringByAppendingString:NSLocalizedString(@"Editor with Aerial",nil)]
																style:UIAlertActionStyleDefault
															  handler:^(UIAlertAction * _Nonnull action) {
			_mapView.viewState = MAPVIEW_EDITORAERIAL;
		}];

		switch ( _mapView.viewState ) {
			case MAPVIEW_EDITOR:
				[actionSheet addAction:editorAerial];
				[actionSheet addAction:aerialOnly];
				break;
			case MAPVIEW_EDITORAERIAL:
				[actionSheet addAction:editorOnly];
				[actionSheet addAction:aerialOnly];
				break;
			case MAPVIEW_AERIAL:
				[actionSheet addAction:editorAerial];
				[actionSheet addAction:editorOnly];
				break;
			default:
				[actionSheet addAction:editorAerial];
				[actionSheet addAction:editorOnly];
				[actionSheet addAction:aerialOnly];
				break;
		}

		[actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
		[self presentViewController:actionSheet animated:YES completion:nil];
		// set location of popup
		actionSheet.popoverPresentationController.sourceView = self.displayButton;
		actionSheet.popoverPresentationController.sourceRect = self.displayButton.bounds;
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
