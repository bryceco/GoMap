//
//  CustomPresetListViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/20/14.
//  Copyright (c) 2014 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class PresetKeyUserDefinedList;

@interface CustomPresetListViewController : UITableViewController <UITableViewDelegate,UITableViewDataSource>
{
	PresetKeyUserDefinedList * _customPresets;
}

@end
