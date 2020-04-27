//
//  NewItemController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CommonPresetCategory;
@class CommonPresetFeature;
@class POITypeViewController;

@protocol POITypeViewControllerDelegate <NSObject>
-(void)typeViewController:(POITypeViewController *)typeViewController didChangeFeatureTo:(CommonPresetFeature *)feature;
@end

@interface POITypeViewController : UITableViewController <UISearchBarDelegate, UIAlertViewDelegate>
{
	NSArray					*	_typeArray;
	NSArray					*	_searchArrayRecent;
	NSArray					*	_searchArrayAll;
	IBOutlet UISearchBar    *	_searchBar;
	BOOL						_isTopLevel;
}
@property (strong,nonatomic) CommonPresetCategory					*	parentCategory;
@property (assign,nonatomic) id<POITypeViewControllerDelegate>		delegate;

-(IBAction)back:(id)sender;
-(IBAction)configure:(id)sender;


+(void)loadMostRecentForGeometry:(NSString *)geometry;
+(void)updateMostRecentArrayWithSelection:(CommonPresetFeature *)feature geometry:(NSString *)geometry;

@end
