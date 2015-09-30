//
//  GpxViewController.h
//  Go Map!!
//
//  Created by Bryce on 2/26/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface GpxViewController : UITableViewController <UITableViewDelegate,UITableViewDataSource>
{
	NSTimer						*	_timer;
	IBOutlet UINavigationBar	*	_navigationBar;
}

-(IBAction)cancel:(id)sender;
-(void)shareTrack:(GpxTrack *)track;

@end
