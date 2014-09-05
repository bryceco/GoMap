//
//  CousineViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface POIPresetViewController : UITableViewController
{
	NSMutableArray	*	_sectionNames;
	NSMutableArray	*	_sectionValues;
}

@property NSString	*	tag;
@property NSArray	*	valueDefinitions;

@end
