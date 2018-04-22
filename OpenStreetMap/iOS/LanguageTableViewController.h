//
//  LanguageTableViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/12/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CommonTagList.h"

@interface LanguageTableViewController : UITableViewController <UITableViewDataSource,UITableViewDelegate>
{
	PresetLanguages * _languages;
}
@end
