//
//  NewItemController.h
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CommonTagCategory;
@class CommonTagFeature;
@class POITypeViewController;

@protocol POITypeViewControllerDelegate <NSObject>
-(void)typeViewController:(POITypeViewController *)typeViewController didChangeFeatureTo:(CommonTagFeature *)feature;
@end

@interface POITypeViewController : UITableViewController <UISearchBarDelegate, UIAlertViewDelegate>
{
	NSArray					*	_typeArray;
	NSArray					*	_searchArrayRecent;
	NSArray					*	_searchArrayAll;
	IBOutlet UISearchBar    *	_searchBar;
	BOOL						_isTopLevel;
}
@property (strong,nonatomic) CommonTagCategory					*	parentCategory;
@property (assign,nonatomic) id<POITypeViewControllerDelegate>		delegate;

-(IBAction)back:(id)sender;
-(IBAction)configure:(id)sender;


+(void)loadMostRecentForGeometry:(NSString *)geometry;
+(void)updateMostRecentArrayWithSelection:(CommonTagFeature *)feature geometry:(NSString *)geometry;

@end
