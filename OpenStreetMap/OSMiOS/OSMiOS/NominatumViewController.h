//
//  NominatumViewController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 1/3/13.
//  Copyright (c) 2013 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface NominatumViewController : UIViewController <UISearchBarDelegate>
{
	IBOutlet UISearchBar				*	_searchBar;
	NSMutableArray						*	_resultsArray;
	IBOutlet UIActivityIndicatorView	*	_activityIndicator;
	IBOutlet UITableView				*	_tableView;
	NSArray								*	_historyArray;
}

-(IBAction)cancel:(id)sender;

@end
