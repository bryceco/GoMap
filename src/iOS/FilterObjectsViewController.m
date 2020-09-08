//
//  FilterObjectsViewController.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/20/18.
//  Copyright © 2018 Bryce. All rights reserved.
//

#import "AppDelegate.h"
#import "EditorMapLayer.h"
#import "FilterObjectsViewController.h"
#import "MapView.h"

@interface FilterObjectsViewController ()
@end

@implementation FilterObjectsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	EditorMapLayer * editor = AppDelegate.shared.mapView.editorLayer;
	
	self.levelsText.text		= editor.showLevelRange;
	self.switchLevel.on			= editor.showLevel;
	self.switchPoints.on		= editor.showPoints;
	self.switchTrafficRoads.on	= editor.showTrafficRoads;
	self.switchServiceRoads.on	= editor.showServiceRoads;
	self.switchPaths.on			= editor.showPaths;
	self.switchBuildings.on		= editor.showBuildings;
	self.switchLanduse.on		= editor.showLanduse;
	self.switchBoundaries.on	= editor.showBoundaries;
	self.switchWater.on			= editor.showWater;
	self.switchRail.on			= editor.showRail;
	self.switchPower.on			= editor.showPower;
	self.switchPastFuture.on	= editor.showPastFuture;
	self.switchOthers.on		= editor.showOthers;
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];

	EditorMapLayer * editor = AppDelegate.shared.mapView.editorLayer;
	
	editor.showLevelRange		= self.levelsText.text;
	editor.showLevel			= self.switchLevel.on;
	editor.showPoints			= self.switchPoints.on;
	editor.showTrafficRoads		= self.switchTrafficRoads.on;
	editor.showServiceRoads		= self.switchServiceRoads.on;
	editor.showPaths			= self.switchPaths.on;
	editor.showBuildings		= self.switchBuildings.on;
	editor.showLanduse			= self.switchLanduse.on;
	editor.showBoundaries		= self.switchBoundaries.on;
	editor.showWater			= self.switchWater.on;
	editor.showRail				= self.switchRail.on;
	editor.showPower			= self.switchPower.on;
	editor.showPastFuture		= self.switchPastFuture.on;
	editor.showOthers			= self.switchOthers.on;
}

// return a list of arrays, each array containing either a single integer or a first-last pair of integers
+(NSArray *)levelsForString:(NSString *)text
{
	NSMutableArray * list = [NSMutableArray new];
	NSScanner * scanner = [NSScanner scannerWithString:text];
	scanner.charactersToBeSkipped = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	
	if ( [scanner isAtEnd] )
		return list;	// empty list
	for (;;) {
		NSInteger first, last;
		if ( ![scanner scanInteger:&first] )
			return nil;
		if ( [scanner scanString:@".." intoString:nil] ) {
			if ( ![scanner scanInteger:&last] )
				return nil;
			[list addObject:@[ @(first), @(last) ]];
		} else {
			[list addObject:@[ @(first) ]];
		}
		if ( [scanner isAtEnd] )
			return list;
		if ( ![scanner scanString:@"," intoString:nil] )
			return nil;
	}
}

- (void)setColorForText:(NSString *)text
{
	NSArray * a = [FilterObjectsViewController levelsForString:text];
	if ( a == nil ) {
		self.levelsText.textColor = UIColor.redColor;
	} else {
		self.levelsText.textColor = UIColor.blackColor;
	}
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	NSString * newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
	[self setColorForText:newString];
	return YES;
}

-(void)textFieldDidEndEditing:(UITextField *)textField
{
	[self setColorForText:textField.text];
}

@end
