//
//  NewItemController.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <UIKit/UIKit.h>

@class PresetCategory;
@class PresetFeature;
@class POIFeaturePickerViewController;

@protocol POITypeViewControllerDelegate <NSObject>
-(void)typeViewController:(POIFeaturePickerViewController *)typeViewController didChangeFeatureTo:(PresetFeature *)feature;
@end

@interface POIFeaturePickerViewController : UITableViewController <UISearchBarDelegate, UIAlertViewDelegate>
{
	NSArray					*	_featureList;
	NSArray					*	_searchArrayRecent;
	NSArray					*	_searchArrayAll;
	IBOutlet UISearchBar    *	_searchBar;
	BOOL						_isTopLevel;
}
@property (strong,nonatomic) PresetCategory				*	parentCategory;
@property (assign,nonatomic) id<POITypeViewControllerDelegate>		delegate;

-(IBAction)back:(id)sender;
-(IBAction)configure:(id)sender;


+(void)loadMostRecentForGeometry:(NSString *)geometry;
+(void)updateMostRecentArrayWithSelection:(PresetFeature *)feature geometry:(NSString *)geometry;

@end
