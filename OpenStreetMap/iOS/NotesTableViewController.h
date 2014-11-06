//
//  NotesTableViewController.h
//  Go Map!!
//
//  Created by Bryce on 11/4/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class OsmNote;


@interface NotesTableViewController : UIViewController<UITableViewDataSource,UITableViewDelegate,UITextViewDelegate>
{
	NSString	*	_newComment;
}
@property (strong,nonatomic)	OsmNote	* note;
@end
