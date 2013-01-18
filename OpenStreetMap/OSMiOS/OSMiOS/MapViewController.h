//
//  FirstViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/6/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>


@class MapView;

@interface MapViewController : UIViewController
{
	IBOutlet UIToolbar		*	_toolbar;
	IBOutlet UIBarButtonItem *	_trashcanButton;
	IBOutlet UIBarButtonItem *	_uploadButton;
	IBOutlet UIBarButtonItem *	_undoButton;
	IBOutlet UIBarButtonItem *	_redoButton;

	CLLocationCoordinate2D		_pushPinLocation;
}

@property (assign,nonatomic) IBOutlet MapView		*	mapView;
@property (assign,nonatomic) IBOutlet UIBarButtonItem * locationButton;

-(IBAction)toggleLocation:(id)sender;
@end
