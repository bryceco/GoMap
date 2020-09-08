//
//  FirstViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "MainViewController.h"
#import "MapView.h"
#import "NotesTableViewController.h"
#import "OsmNotesDatabase.h"
#import "OsmMapData.h"
#import "PushPinView.h"
#import "SpeechBalloonView.h"

@interface MainViewController ()
@property (weak, nonatomic) IBOutlet UIButton *settingsButton;
@property (weak, nonatomic) IBOutlet UIButton *displayButton;
@end

@implementation MainViewController


- (void)updateUndoRedoButtonState
{
	_undoButton.enabled = self.mapView.editorLayer.mapData.canUndo && !self.mapView.editorLayer.hidden;
	_redoButton.enabled = self.mapView.editorLayer.mapData.canRedo && !self.mapView.editorLayer.hidden;
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

	NSArray * buttons = @[
		_undoRedoView,
		_locationButton,
		_undoButton,
		_redoButton,
		_mapView.addNodeButton,
		_mapView.compassButton,
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
			button.tintColor = UIColor.systemBlueColor;
			if ( button == _mapView.addNodeButton )
				button.imageEdgeInsets = UIEdgeInsetsMake(15, 15, 15, 15);	// resize images on button to be smaller
			else
				button.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);	// resize images on button to be smaller
		}
		// background selection color
		if ( button != _undoRedoView ) {
			[button addTarget:self action:@selector(buttonHighlight:) forControlEvents:UIControlEventTouchDown];
			[button addTarget:self action:@selector(buttonNormal:) forControlEvents:UIControlEventTouchUpInside];
			[button addTarget:self action:@selector(buttonNormal:) forControlEvents:UIControlEventTouchUpOutside];
			[button addTarget:self action:@selector(buttonNormal:) forControlEvents:UIControlEventTouchCancel];
		}
	}
}
-(void)buttonHighlight:(UIButton *)button
{
	button.backgroundColor = UIColor.lightGrayColor;
}
-(void)buttonNormal:(UIButton *)button
{
	button.backgroundColor = UIColor.whiteColor;
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
		UIView * superview = button.superview;
		while ( superview != nil ) {
			for ( NSLayoutConstraint * c in superview.constraints ) {
				if ( c.firstItem == button || c.secondItem == button ) {
					[superview removeConstraint:c];
				}
			}
			superview = superview.superview;
		}
		for ( NSLayoutConstraint * c in [button.constraints copy] ) {
			if ( ((UIView *)c.firstItem).superview == button || ((UIView *)c.secondItem).superview == button ) {
				// skip
			} else {
				[button removeConstraint:c];
			}
		}
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

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

#if 1 // FIXME
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

-(void)search:(UILongPressGestureRecognizer *)recognizer
{
	if ( recognizer.state == UIGestureRecognizerStateBegan ) {
		[self performSegueWithIdentifier:@"searchSegue" sender:recognizer];
	}
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
