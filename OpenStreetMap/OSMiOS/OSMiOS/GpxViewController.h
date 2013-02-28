//
//  GpxViewController.h
//  Go Map!!
//
//  Created by Bryce on 2/26/13.
//  Copyright (c) 2013 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface GpxViewController : UITableViewController
@property (strong,nonatomic)	NSArray * gpxTracks;

-(IBAction)cancel:(id)sender;

@end
