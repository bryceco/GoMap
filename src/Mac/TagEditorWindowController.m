//
//  POIWindowController.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/19/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "OsmMapData.h"
#import "OsmObjects.h"
#import "TagEditorWindowController.h"
#import "TagInfo.h"


@implementation TagEditorWindowController
@synthesize osmObject = _osmObject;

- (id)init
{
	self = [super initWithWindowNibName:@"TagEditorWindowController"];
	if ( self ) {
 	}
	return self;
}

- (void)windowDidLoad
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [super windowDidLoad];
	
	_tagDictionary = @{
		// basic
		@"name"					:	_nameTextField,
		@"alt_name"				:	_altNameTextField,
		@"cuisine"				:	_cuisineComboBox,
		@"wifi"					:	_wifiComboBox,
		@"operator"				:	_operatorTextField,
		@"ref"					:	_refTextField,
		// address
		@"addr:housenumber"		:	_houseNumberTextField,
		@"addr:housename"		:	_buildingTextField,
		@"addr:street"			:	_streetTextField,
		@"addr:city"			:	_cityTextField,
		@"addr:postcode"		:	_postalCodeTextField,
		@"website"				:	_websiteTextField,
		// source
		@"designation"			:	_officialClassificationTextField,
		@"source"				:	_sourceComboBox,
	};

	_cuisineArray = @[
		@"bagel",
		@"barbecue",
		@"bougatsa",
		@"burger",
		@"cake",
		@"chicken",
		@"coffee_shop",
		@"crepe",
		@"couscous",
		@"curry",
		@"doughnut",
		@"fish_and_chips",
		@"fried_food",
		@"friture",
		@"ice_cream",
		@"kebab",
		@"mediterranean",
		@"noodle",
		@"pasta",
		@"pie",
		@"pizza",
		@"regional",
		@"sandwich",
		@"sausage",
		@"savory_pancakes",
		@"seafood",
		@"steak_house",
		@"sushi",
	
		@"african",
		@"american",
		@"arab",
		@"argentinian",
		@"asian",
		@"balkan",
		@"basque",
		@"brazilian",
		@"chinese",
		@"croatian",
		@"czech",
		@"french",
		@"german",
		@"greek",
		@"indian",
		@"iranian",
		@"italian",
		@"japanese",
		@"korean",
		@"latin_american",
		@"lebanese",
		@"mexican",
		@"peruvian",
		@"portuguese",
		@"spanish",
		@"thai",
		@"turkish",
		@"vietnamese"
	];
	[_cuisineComboBox addItemsWithObjectValues:_cuisineArray];

	[_sourceComboBox addItemsWithObjectValues:@[
		@"Bing",
		@"local_knowledge",
		@"survey",
		@"Yahoo"
	]];


	// get list of entries for type field, and set it for the combo box
	_typeKeyNames = @{
		@"amenity" : @"",
		@"building" : @"building",
		@"landuse" : @" landuse",
		@"leisure" : @"leisure area",
		@"office" : @"office",
		@"shop" : @"shop",
	};

	NSArray * typesArray = [[TagInfoDatabase sharedTagInfoDatabase] tagsForNodes];
	NSMutableDictionary * dict = [NSMutableDictionary new];
	for ( KeyValue * kv in typesArray ) {
		if ( [kv.value length] == 0 )
			continue;
		NSString * text = [_typeKeyNames objectForKey:kv.key];
		if ( text == nil )
			continue;
		if ( text.length == 0 )
			text = kv.value;
		else
			text = [NSString stringWithFormat:@"%@ %@", kv.value, text];
		[dict setObject:kv forKey:text];
	}
	[dict setObject:[KeyValue keyValueWithKey:@"building" value:@"yes"] forKey:@"building"];
	_typesDictionary = [NSDictionary dictionaryWithDictionary:dict];
	NSArray * keys = [[_typesDictionary allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
	[_typeComboBox addItemsWithObjectValues:keys];

	_customArray = [NSMutableArray array];

	_tagTypeMenu = [[TagInfoDatabase sharedTagInfoDatabase] tagNodeMenuWithTarget:self action:@selector(pickTypeTag:)];

	// type field needs special handling because the text doesn't equal the key:value pair
	[center addObserverForName:NSControlTextDidEndEditingNotification
						object:_typeComboBox
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification * note) {
						NSString * text = _typeComboBox.stringValue;
						if ( text.length ) {
							KeyValue * kv = [_typesDictionary objectForKey:text];
							if ( kv ) {
								[self.tags setObject:kv.value forKey:kv.key];
								[self makeTypeUnique:kv.key];
							} else {
								NSAlert * alert = [NSAlert alertWithMessageText:@"Invalid type" defaultButton:@"OK" alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
								[alert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:nil contextInfo:NULL];
							}
						}
					}];
	[center addObserverForName:NSComboBoxSelectionDidChangeNotification
						object:_typeComboBox
						 queue:[NSOperationQueue mainQueue]
					usingBlock:^(NSNotification * note) {
						NSString * text = [_typeComboBox objectValueOfSelectedItem];
						KeyValue * kv = [_typesDictionary objectForKey:text];
						assert(kv);
						[self.tags setObject:kv.value forKey:kv.key];
						[self makeTypeUnique:kv.key];
					}];

	[_tagDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * tag, NSControl * field, BOOL *stop) {
		// observe changing selection in NSComboBox
		if ( [field isKindOfClass:[NSComboBox class]] ) {
			[center addObserverForName:NSComboBoxSelectionDidChangeNotification
								object:field
								 queue:[NSOperationQueue mainQueue]
							usingBlock:^(NSNotification * note) {
								NSComboBox * combo = (id)field;
								NSString * text = [combo objectValueOfSelectedItem];
								[self.tags setObject:text forKey:tag];
				}];
		}
	}];

	[self addObserver:self forKeyPath:@"tags.name" options:0 context:NULL];	// for window title
	[self addObserver:self forKeyPath:@"tags.amenity" options:0 context:NULL];	// for restaurant cousine
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( [keyPath isEqualToString:@"tags.name"] ) {
		[self updateWindowTitle];
	} else if ( [keyPath isEqualToString:@"tags.amenity"] ) {
		NSString * value = [self valueForKeyPath:keyPath];
		BOOL isRest = [value isEqualToString:@"restaurant"];
		[_cuisineComboBox setEnabled:isRest];
	}
}

-(void)makeTypeUnique:(NSString *)key
{
	if ( [_typeKeyNames objectForKey:key] ) {
		// changed to a type key, so remove all conflicting tags
		NSMutableSet * set = [NSMutableSet set];
		for ( NSString * tag in _osmObject.tags ) {
			if ( ![tag isEqualToString:key] && [_typeKeyNames objectForKey:tag] ) {
				[set addObject:tag];
			}
		}
		for ( NSString * tag in set ) {
			[self.tags removeObjectForKey:tag];
		}
	}

	TagInfo * tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForObject:_osmObject];
	_iconImageView.image = tagInfo.icon;
}

-(void)updateTypeFromTags
{
	_typeComboBox.stringValue = @"";
	[_typesDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * key, KeyValue * kv, BOOL *stop) {
		if ( [[_osmObject.tags valueForKey:kv.key] isEqualToString:kv.value] ) {
			_typeComboBox.stringValue = key;
			[_typeComboBox selectItemWithObjectValue:key];
			*stop = YES;
		}
	}];
}


-(void)updateWindowTitle
{
	NSString * value = [_osmObject.tags valueForKey:@"name"];
	if ( value == nil ) {
		if ( [_osmObject isKindOfClass:[OsmNode class]] ) {
			value = @"Node Properties";
		} else if ( [_osmObject isKindOfClass:[OsmWay class]] ) {
			value = @"Way Properties";
		} else {
			value = @"Properties";
		}
	}
	self.window.title = value;
}


-(IBAction)showTagMenu:(id)sender
{
	NSEvent * event = [NSApp currentEvent];
    [NSMenu popUpContextMenu:_tagTypeMenu withEvent:event forView:nil];
}

-(void)pickTypeTag:(id)sender
{
	NSMenuItem * item = sender;
	KeyValue * kv = item.representedObject;
	[self.tags setObject:kv.value forKey:kv.key];
	[self updateTypeFromTags];
}


-(OsmBaseObject *)osmObject
{
	return _osmObject;
}

-(void)setObject:(OsmBaseObject	*)osmObject mapData:(OsmMapData *)mapData;
{
	if ( _osmObject != osmObject ) {
		_osmObject = osmObject;
		self.tags = [_osmObject.tags mutableCopy];
		
		[self updateTypeFromTags];
		[self refreshCustomArray];
		[self refreshAttributesArray:_osmObject];

#if 0
		_relations = osmObject.relations;
		[_relationsTableView reloadData];
#endif

		TagInfo * tagInfo = [[TagInfoDatabase sharedTagInfoDatabase] tagInfoForObject:_osmObject];
		_iconImageView.image = tagInfo.icon;
	}
}


#pragma mark Custom fields

-(void)refreshCustomArray
{
	[_customArray removeAllObjects];
	[_osmObject.tags enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL *stop) {
		KeyValue * kv = [KeyValue keyValueWithKey:key value:value];
		[_customArray addObject:kv];
	}];
	[_customArray sortUsingComparator:^NSComparisonResult(KeyValue * obj1, KeyValue * obj2) {
		return [obj1.key caseInsensitiveCompare:obj2.key];
	}];
	[_tagsTableView reloadData];
}


-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if ( tableView == _tagsTableView )
		return _customArray.count;
	if ( tableView == _attributesTableView )
		return _attributes.count;
	if ( tableView == _relationsTableView )
		return _relations.count;
	return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	if ( tableView == _tagsTableView ) {
		if ( rowIndex >= _customArray.count )
			return nil;
		KeyValue * kv = _customArray[ rowIndex ];
		if ( [tableColumn.identifier isEqualToString:@"key"] ) {
			return kv.key;
		} else {
			return kv.value;
		}
	}
	if ( tableView == _attributesTableView ) {
		if ( rowIndex >= _attributes.count )
			return nil;
		int column = [tableColumn.identifier isEqualToString:@"key"] ? 0 : 1;
		NSArray * row = _attributes[ rowIndex ];
		return row[ column ];
	}
	if ( tableView == _relationsTableView ) {
		if ( rowIndex >= _relations.count )
			return nil;
		OsmRelation * relation = _relations[ rowIndex ];
		if ( [tableColumn.identifier isEqualToString:@"identifier"] ) {
			return relation.ident;
		}
	}
	return nil;
}
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ( tableView == _tagsTableView ) {
		assert( rowIndex < _customArray.count );
		KeyValue * kv = _customArray[ rowIndex ];
		if ( [aTableColumn.identifier isEqualToString:@"key"] ) {
			kv.key = anObject;
		} else {
			kv.value = anObject;
		}
		[self.tags setObject:kv.value forKey:kv.key];
	}
}
-(void)addRow:(id)sender
{
	KeyValue * kv = [KeyValue keyValueWithKey:@"(new tag)" value:@"(new value)"];
	[_customArray addObject:kv];
	[_tagsTableView reloadData];
	NSInteger row = _customArray.count - 1;
	[_tagsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[_tagsTableView editColumn:0 row:row withEvent:nil select:YES];
}
-(void)removeRow:(id)sender
{
	NSInteger row = [_tagsTableView selectedRow];
	if ( row >= 0 && row < _customArray.count ) {
		KeyValue * kv = _customArray[ row ];
		[self.tags setObject:nil forKey:kv.key];
		[_customArray removeObjectAtIndex:row];
		[_tagsTableView reloadData];
		if ( row < _customArray.count ) {
			[_tagsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		}
	}
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	NSInteger newTab = [tabViewItem.identifier integerValue];
	if ( newTab == 1 ) {
		[self updateTypeFromTags];
	} else if ( newTab == 4 ) {
		[self refreshCustomArray];
	} else if ( newTab == 5 ) {
		[self refreshAttributesArray:_osmObject];
	}
}


#pragma mark attributes

-(void)refreshAttributesArray:(OsmBaseObject *)base
{
	if ( base ) {
		_attributes = @[
			@[ @"id",			base.ident ],
			@[ @"visible",		OsmValueForBoolean(base.visible)],
			@[ @"timestamp",	[_dateFormatter stringFromDate:[base dateForTimestamp] ]],
			@[ @"version",		@(base.version) ],
			@[ @"changeset",	@(base.changeset) ],
			@[ @"user",			base.user ],
			@[ @"uid",			@(base.uid) ]
		];
		if ( [base isKindOfClass:[OsmNode class]] ) {
			OsmNode * node = (id)base;
			_attributes = [_attributes arrayByAddingObjectsFromArray:@[
						   @[ @"latitude",  @(node.lat) ],
						   @[ @"longitude", @(node.lon) ],
						   ]];
		}
	} else {
		_attributes = nil;
	}
	[_attributesTableView reloadData];
}

#pragma mark Relations



@end
