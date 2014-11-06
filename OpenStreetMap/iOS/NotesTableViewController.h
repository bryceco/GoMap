//
//  NotesTableViewController.h
//  Go Map!!
//
//  Created by Bryce on 11/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmNote;
@class MapView;

@interface NotesTableViewController : UIViewController<UITableViewDataSource,UITableViewDelegate,UITextViewDelegate>
{
	NSString		*	_newComment;
	UIAlertView		*	_alert;
}
@property (strong,nonatomic)	OsmNote	* note;
@property (strong,nonatomic)	MapView	* mapView;
@end
