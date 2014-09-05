//
//  CousineViewController.m
//  OSMiOS
//
//  Created by Bryce Cogswell on 12/10/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "iosapi.h"
#import "POIPresetViewController.h"
#import "POITabBarController.h"
#import "TagInfo.h"


@implementation POIPresetViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	_sectionValues	= [NSMutableArray new];
	_sectionNames	= [NSMutableArray new];

	for ( NSInteger i = 0; i+1 < self.valueDefinitions.count; i += 2 ) {
		NSString * sectionHeader	= _valueDefinitions[i];
		NSArray * valueList			= _valueDefinitions[i+1];
		if ( [valueList isKindOfClass:[NSString class]] ) {
			// expand using taginfo
			SEL selector = NSSelectorFromString((id)valueList);
			TagInfoDatabase * database = [TagInfoDatabase sharedTagInfoDatabase];
			if ( selector && [database respondsToSelector:selector]	) {
				IMP imp = [database methodForSelector:selector];
				NSArray * (*func)(id, SEL) = (void *)imp;
				valueList = func(database, selector);
			} else {
				valueList = @[];
			}
		} else {
			// should already be an array
			assert( [valueList isKindOfClass:[NSArray class]] );
		}
		[_sectionValues addObject:valueList];
		[_sectionNames addObject:sectionHeader];
	}
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return _sectionValues.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	NSArray * values = _sectionValues[ section ];
	return values.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return _sectionNames[ section ];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
	NSArray * a = _sectionValues[ indexPath.section ];
	NSString * rawtext = a[ indexPath.row ];
	NSString * text = [rawtext stringByReplacingOccurrencesOfString:@"_" withString:@" "];
	text = [text capitalizedString];
	cell.textLabel.text = text;

	POITabBarController * tabController = (id)self.tabBarController;
	BOOL selected = [[tabController.keyValueDict valueForKey:@"cuisine"] isEqualToString:rawtext];
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSArray * a = _sectionValues[ indexPath.section ];
	NSString * value = a[ indexPath.row ];
	assert(value);
	POITabBarController * tab = (id)self.tabBarController;
	[tab.keyValueDict setObject:value forKey:self.tag];

	[self.navigationController popViewControllerAnimated:YES];
}

@end
