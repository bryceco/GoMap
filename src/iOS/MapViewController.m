//
//  FirstViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "DLog.h"
#import "EditorMapLayer.h"
#import "MapViewController.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "PushPinView.h"


@interface MapViewController ()
@end

@implementation MapViewController


- (void)updateDeleteButtonState
{
	_trashcanButton.enabled = self.mapView.editorLayer.selectedPrimary && !self.mapView.editorLayer.hidden;
}

- (void)updateUndoRedoButtonState
{
	_undoButton.enabled = self.mapView.editorLayer.mapData.canUndo && !self.mapView.editorLayer.hidden;
	_redoButton.enabled = self.mapView.editorLayer.mapData.canRedo && !self.mapView.editorLayer.hidden;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.mapView.viewController = self;

	AppDelegate * delegate = [[UIApplication sharedApplication] delegate];
	delegate.mapView = self.mapView;

	[self.mapView.editorLayer setSelectionChangeCallback:^{
		[self updateDeleteButtonState];
	}];

	_statusBarBackground.backgroundColor = NSColor.whiteColor;
	_statusBarBackground.alpha = 0.25;

	// undo/redo buttons
	_undoButton.enabled = self.mapView.editorLayer.mapData.canUndo;
	_redoButton.enabled = self.mapView.editorLayer.mapData.canRedo;
	[self.mapView.editorLayer.mapData addChangeCallback:^{
		[self updateUndoRedoButtonState];
	}];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:NULL];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	self.navigationController.navigationBarHidden = YES;

#if 0 && DEBUG
	{
		static dispatch_source_t timer;
		timer = dispatch_source_create( DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC/2);
		dispatch_source_set_event_handler(timer, ^{
			DLog(@"memory used: %f MB used", MemoryUsedMB() );
		});
		dispatch_resume(timer);
	}
#endif
}


- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if ( buttonIndex == actionSheet.cancelButtonIndex ) {
		return;
	}
	switch ( buttonIndex ) {
		case 0:
			[self performSegueWithIdentifier:@"searchSegue" sender:self];
			break;
		case 1:
			[self performSegueWithIdentifier:@"locationSegue" sender:self];
			break;
	}
}

-(void)search:(UILongPressGestureRecognizer *)recognizer
{
	[self installLongPressGestureRecognizer:NO];	// remove so we don't trigger twice during a long press
#if 0 // enable GPX view
	UIView * view = recognizer.view;
	UIActionSheet * sheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"GPS Action",nil)
														delegate:self
											   cancelButtonTitle:NSLocalizedString(@"Cancel",nil)
										  destructiveButtonTitle:nil
											   otherButtonTitles:NSLocalizedString(@"Search for Location",nil), NSLocalizedString(@"Manage GPX Tracks",nil), nil];
	[sheet showInView:view];
#else
	[self performSegueWithIdentifier:@"searchSegue" sender:recognizer];
#endif
	[self installLongPressGestureRecognizer:YES];
}


- (void)installLongPressGestureRecognizer:(BOOL)install
{
	if ( [self.locationButton respondsToSelector:@selector(view)] ) {
		UIView * view = [(id)self.locationButton view];
		if ( install ) {
			if ( view.gestureRecognizers.count == 0 ) {
				UILongPressGestureRecognizer * gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(search:)];
				[view addGestureRecognizer:gesture];
			}
		} else {
			view.gestureRecognizers = nil;
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

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	self.mapView.frame = self.view.bounds;
	[self installLongPressGestureRecognizer:YES];
}


-(IBAction)toggleLocation:(id)sender
{
	self.mapView.trackingLocation = !self.mapView.trackingLocation;
	
	if ( self.mapView.trackingLocation ) {
		UIColor * tint = [UIColor colorWithRed:0.5 green:0.5 blue:1.0 alpha:1.0];
		self.locationButton.tintColor = tint;
	} else {
		self.locationButton.tintColor = nil;
	}
	
	// changing the button tint changes the view, so we have to install longpress again
	[self installLongPressGestureRecognizer:YES];
}

-(void)applicationWillResignActive:(id)sender
{
	if ( self.mapView.trackingLocation ) {
		[self toggleLocation:nil];
	}
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	// save start location for pushpin
	if ( _mapView.pushpinView ) {
		CGPoint pt = _mapView.pushpinView.arrowPoint;
		_pushPinLocation = [_mapView longitudeLatitudeForViewPoint:pt];
	}
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	CGRect rc = self.view.superview.bounds;
	self.mapView.frame = rc;

	// set new pushpin position
	if ( _mapView.pushpinView ) {
		_mapView.pushpinView.arrowPoint = [_mapView viewPointForLatitude:_pushPinLocation.latitude longitude:_pushPinLocation.longitude];
	}
}


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

@end
