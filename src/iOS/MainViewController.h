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

typedef enum {
	BUTTON_LAYOUT_ADD_ON_LEFT,
	BUTTON_LAYOUT_ADD_ON_RIGHT,
} BUTTON_LAYOUT;


@class MapView;

@interface MainViewController : UIViewController <UIActionSheetDelegate,UIGestureRecognizerDelegate>
{
	IBOutlet UIButton		*	_uploadButton;
	IBOutlet UIButton		*	_undoButton;
	IBOutlet UIButton		*	_redoButton;
	IBOutlet UIView			*	_undoRedoView;
	IBOutlet UIButton		*	_searchButton;
}

@property (assign,nonatomic) IBOutlet MapView	*	_Nonnull mapView;
@property (assign,nonatomic) IBOutlet UIButton 	* 	_Nonnull locationButton;
@property (assign,nonatomic) BUTTON_LAYOUT	buttonLayout;

-(IBAction)toggleLocation:(_Nullable id)sender;
-(void)setGpsState:(GPS_STATE)state;

- (void)updateUndoRedoButtonState;

@end
