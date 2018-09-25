//
//  FirstViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import "MapView.h"


@class MapView;

@interface MapViewController : UIViewController <UIActionSheetDelegate,UIGestureRecognizerDelegate>
{
	IBOutlet UIToolbar		*	_toolbar;
	IBOutlet UIBarButtonItem *	_uploadButton;
	IBOutlet UIBarButtonItem *	_undoButton;
	IBOutlet UIBarButtonItem *	_redoButton;
}

@property (assign,nonatomic) IBOutlet MapView		*	mapView;
@property (assign,nonatomic) IBOutlet UIBarButtonItem * locationButton;

-(IBAction)toggleLocation:(id)sender;
-(void)setGpsState:(GPS_STATE)state;

- (void)updateUndoRedoButtonState;

@end
