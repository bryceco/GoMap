//
//  POITabBarController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 12/14/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "MapView.h"
#import "OsmMapData.h"
#import "OsmObjects.h"
#import "POICommonTagsViewController.h"
#import "POITabBarController.h"
#import "POIAttributesViewController.h"

@implementation POITabBarController


- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	OsmBaseObject * selection = appDelegate.mapView.editorLayer.selectedPrimary;
	self.selection = selection;
	self.keyValueDict = [NSMutableDictionary new];
	self.relationList = [NSMutableArray new];
	if ( selection ) {
		[selection.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * obj, BOOL *stop) {
			[_keyValueDict setObject:obj forKey:key];
		}];

		self.relationList = [selection.parentRelations mutableCopy];
	}

	NSInteger tabIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"POITabIndex"];
	self.selectedIndex = tabIndex;
    
    [self updatePOIAttributesTabBarItemVisibilityWithSelectedObject:selection];
}

/**
 Hides the POI attributes tab bar item when the user is adding a new item, since it doesn't have any attributes yet.

 @param selectedObject The object that the user selected on the map.
 */
- (void)updatePOIAttributesTabBarItemVisibilityWithSelectedObject:(nullable OsmBaseObject *)selectedObject {
    BOOL isAddingNewItem = selectedObject.ident.integerValue <= 0;
    if (isAddingNewItem) {
        // Remove the `POIAttributesViewController`.
        NSMutableArray<UIViewController *> *viewControllersToKeep = [NSMutableArray array];
        [self.viewControllers enumerateObjectsUsingBlock:^(__kindof UIViewController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            if ([obj isKindOfClass:[UINavigationController class]] && [[(UINavigationController *)obj viewControllers].firstObject isKindOfClass:[POIAttributesViewController class]]) {
                // For new objects, the navigation controller that contains the view controller
                // for POI attributes is not needed; ignore it.
                return;
            } else {
                [viewControllersToKeep addObject:obj];
            }
        }];
        
        [self setViewControllers:viewControllersToKeep animated:NO];
    }
}

- (void)setFeatureKey:(NSString *)key value:(NSString *)value
{
	if ( value ) {
		[_keyValueDict setObject:value forKey:key];
	} else {
		[_keyValueDict removeObjectForKey:key];
	}
}

- (void)commitChanges
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];
	[appDelegate.mapView setTagsForCurrentObject:self.keyValueDict];
}

- (BOOL)isTagDictChanged:(NSDictionary *)newDictionary
{
	AppDelegate * appDelegate = [AppDelegate getAppDelegate];

	NSDictionary * tags = appDelegate.mapView.editorLayer.selectedPrimary.tags;
	if ( tags.count == 0 )
		return newDictionary.count != 0;

	return ![newDictionary isEqual:tags];
}

- (BOOL)isTagDictChanged
{
	return [self isTagDictChanged:self.keyValueDict];
}



- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
	NSInteger tabIndex = [tabBar.items indexOfObject:item];
	[[NSUserDefaults standardUserDefaults] setInteger:tabIndex forKey:@"POITabIndex"];
}


@end
