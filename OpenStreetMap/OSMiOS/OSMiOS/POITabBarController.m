//
//  POITabBarController.m
//  OSMiOS
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


@implementation POITabBarController


- (void)viewDidLoad
{
    [super viewDidLoad];

	if ( _typeList == nil ) {
		_typeList = @[	@"amenity", @"leisure", @"aeroway", @"building", @"craft",
						@"emergency", @"landmark", @"man_made", @"military", @"natural",
						@"office", @"power", @"railway", @"shop", @"sport", @"tourism" ];
	}
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	OsmBaseObject * selection = appDelegate.mapView.editorLayer.selectedPrimary;
	self.selection = selection;
	self.keyValueDict = [NSMutableDictionary new];
	self.relationList = [NSMutableArray new];
	if ( selection ) {
		[selection.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * obj, BOOL *stop) {
			[_keyValueDict setObject:obj forKey:key];
		}];

		self.relationList = [[appDelegate.mapView.editorLayer.mapData relationsForObject:selection] mutableCopy];
	}

	NSInteger tabIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"POITabIndex"];
	self.selectedIndex = tabIndex;
}


- (void)setType:(NSString *)tag value:(NSString *)value byUser:(BOOL)byUser
{
	if ( byUser ) {
		// remove conflicting tags
		for ( NSString * tag in _typeList ) {
			[_keyValueDict removeObjectForKey:tag];
		}
	}

	_typeTag = tag;
	_typeValue = value;

	[_keyValueDict setObject:_typeValue forKey:_typeTag];
}

- (void)commitChanges
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];
	[appDelegate.mapView setTagsForCurrentObject:self.keyValueDict];
}

- (BOOL)isTagDictChanged
{
	AppDelegate * appDelegate = [[UIApplication sharedApplication] delegate];

	NSDictionary * tags = appDelegate.mapView.editorLayer.selectedPrimary.tags;
	if ( tags.count == 0 )
		return self.keyValueDict.count != 0;

	return ![self.keyValueDict isEqual:tags];
}



- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
	NSInteger tabIndex = [tabBar.items indexOfObject:item];
	[[NSUserDefaults standardUserDefaults] setInteger:tabIndex forKey:@"POITabIndex"];
}


@end
