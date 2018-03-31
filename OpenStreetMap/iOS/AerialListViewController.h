//
//  CustomBackgroundViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/20/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AerialList;
@class DisplayViewController;

@interface AerialListViewController : UITableViewController <UITableViewDelegate,UITableViewDataSource>
{
	AerialList 	*	 _aerials;
	NSArray 	*	_imageryForRegion;
}

@property (weak) DisplayViewController * displayViewController;

@end
