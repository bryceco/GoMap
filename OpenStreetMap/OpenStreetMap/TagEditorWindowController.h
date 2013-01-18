//
//  POIWindowController.h
//  OpenStreetMap
//
//  Created by Bryce on 10/19/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class OsmBaseObject;
@class TagInfo;
@class OsmMapData;


@interface TagEditorWindowController : NSWindowController <NSTabViewDelegate,NSTableViewDataSource,NSTableViewDelegate>
{
	IBOutlet NSTabView			*	_tabView;

	// basic
	IBOutlet NSImageView		*	_iconImageView;
	IBOutlet NSComboBox			*	_typeComboBox;
	IBOutlet NSTextField		*	_nameTextField;
	IBOutlet NSTextField		*	_altNameTextField;
	IBOutlet NSComboBox			*	_cuisineComboBox;
	IBOutlet NSComboBox			*	_wifiComboBox;
	IBOutlet NSTextField		*	_operatorTextField;
	IBOutlet NSTextField		*	_refTextField;
	// address
	IBOutlet NSTextField		*	_buildingTextField;
	IBOutlet NSTextField		*	_houseNumberTextField;
	IBOutlet NSTextField		*	_streetTextField;
	IBOutlet NSTextField		*	_cityTextField;
	IBOutlet NSTextField		*	_postalCodeTextField;
	IBOutlet NSTextField		*	_websiteTextField;
	// source
	IBOutlet NSTextField		*	_officialClassificationTextField;
	IBOutlet NSComboBox			*	_sourceComboBox;
	// custom
	IBOutlet NSTableView		*	_tagsTableView;
	// attributes
	IBOutlet NSTableView		*	_attributesTableView;
	// relations
	IBOutlet NSTableView		*	_relationsTableView;
	

	NSDictionary				*	_tagDictionary;			// map tag names to NSTextFields

	NSArray						*	_cuisineArray;			// for restaurants
	NSDictionary				*	_typeKeyNames;
	NSDictionary				*	_typesDictionary;

	NSMenu						*	_tagTypeMenu;

	NSMutableArray				*	_customArray;

	NSArray						*	_attributes;
	NSArray						*	_relations;
	IBOutlet NSDateFormatter	*	_dateFormatter;
}

@property (strong,nonatomic)	NSMutableDictionary		*	tags;

@property (readonly,nonatomic) OsmBaseObject * osmObject;
-(void)setObject:(OsmBaseObject	*)osmObject mapData:(OsmMapData *)mapData;

-(IBAction)addRow:(id)sender;
-(IBAction)removeRow:(id)sender;

@end
