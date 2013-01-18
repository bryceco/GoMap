//
//  OfflineViewController.h
//  OSMiOS
//
//  Created by Bryce on 12/27/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MercatorTileLayer;


@interface OfflineTableViewCell : UITableViewCell
@property (strong,nonatomic)	IBOutlet UILabel					*	detailLabel;
@property (strong,nonatomic)	IBOutlet UIButton					*	button;
@property (strong,nonatomic)	IBOutlet UIActivityIndicatorView	*	activityView;
@property (strong,nonatomic)	NSMutableArray						*	tileList;
@property (assign,nonatomic)	MercatorTileLayer					*	tileLayer;
@end


@interface OfflineViewController : UITableViewController
{
	IBOutlet OfflineTableViewCell	*	_aerialCell;
	IBOutlet OfflineTableViewCell	*	_mapnikCell;
	NSInteger							_activityCount;
}

-(IBAction)toggleDownload:(id)sender;

@end
