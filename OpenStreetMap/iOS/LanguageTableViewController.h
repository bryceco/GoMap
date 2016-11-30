//
//  LanguageTableViewController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/12/15.
//  Copyright © 2015 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LanguageTableViewController : UITableViewController <UITableViewDataSource,UITableViewDelegate>
{
	NSMutableArray *	_supportedLanguages;
}
@end
