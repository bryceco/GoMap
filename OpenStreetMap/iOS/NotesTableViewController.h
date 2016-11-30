//
//  NotesTableViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/4/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmNote;
@class MapView;

@interface NotesTableViewController : UIViewController<UITableViewDataSource,UITableViewDelegate,UITextViewDelegate>
{
	NSString		*	_newComment;
	UIAlertView		*	_alert;
}
@property (assign,nonatomic)	IBOutlet UITableView	*	tableView;
@property (strong,nonatomic)	OsmNote	* note;
@property (strong,nonatomic)	MapView	* mapView;
@end
