//
//  ClearCacheViewController.h
//  OSMiOS
//
//  Created by Bryce on 12/15/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ClearCacheViewController : UITableViewController <UIAlertViewDelegate>
{
	IBOutlet UILabel *	_osmDetail;
	IBOutlet UILabel *	_aerialDetail;
	IBOutlet UILabel *	_mapnikDetail;
}
@end
