//
//  TagInfoEditorWindowController.m
//  OpenStreetMap
//
//  Created by Bryce on 11/3/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#include <sqlite3.h>

#import "TagInfo.h"
#import "TagInfoEditorWindowController.h"


@interface MyArrayController : NSArrayController
@end
@implementation MyArrayController
- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
	if ( operation != NSTableViewDropOn )
		return NSDragOperationNone;

	NSPasteboard * pb = [info draggingPasteboard];
#if 0
	for ( id item in pb.pasteboardItems ) {
		DLog(@"item = %@",item);
		for ( id type in [item types] ) {
			DLog(@"  type = %@",type);
		}
	}
#endif
	NSString * text = [pb stringForType:@"public.utf8-plain-text"];
	if ( text == nil )
		text = [pb stringForType:@"public.file-url"];
	if ( text )
		return  NSDragOperationEvery;

	return NSDragOperationNone;
}
- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	NSPasteboard * pb = [info draggingPasteboard];
	NSString * text = [pb stringForType:@"public.utf8-plain-text"];
	if ( text == nil )
		text = [pb stringForType:@"public.file-url"];
	if ( text == nil )
		return NO;

	text = [text lastPathComponent];
	NSInteger index = [text rangeOfString:@"."].location;
	if ( index != NSNotFound ) {
		text = [text substringToIndex:index];
	}

	TagInfo * tag = [[self arrangedObjects] objectAtIndex:row];
	[tag setValue:text forKey:@"iconName"];
	return YES;
}
@end



@implementation TagInfoEditorWindowController
@synthesize searchText = _searchText;

- (id)init
{
	self = [super initWithWindowNibName:@"TagInfoEditorWindowController"];
	if (self) {
#if 1
		// our own database
		_tagArray = [TagInfoDatabase readXml];
#else
		// potlatch2 XML files augmented by JOSM data
		[self readPotlatch2];
		[self readJosmDatabase];
#endif
#if 0
		[self readMapIcons];
#endif
#if 1
		[self readDescriptions];
#endif
	}
	return self;
}

-(void)readCVS
{
	NSError * error = nil;
	NSString * text = [NSString stringWithContentsOfFile:@"/Users/bryce/Library/Containers/com.Bryceco.OpenStreetMap/Data/Library/Application Support/TagInfo.csv" encoding:NSUTF8StringEncoding error:&error];
	NSArray * a = [text componentsSeparatedByString:@"\n"];
	for ( NSString * t in a ) {
		NSArray * f = [t componentsSeparatedByString:@","];
		TagInfo * tag = [TagInfo new];
		tag.key = f[0];
		tag.value = f[1];
		tag.friendlyName = f[2];
		tag.belongsTo = f[3];
		tag.iconName = f[4];

		tag.key = [tag.key stringByReplacingOccurrencesOfString:@" " withString:@"_"];
		tag.friendlyName = [tag.friendlyName capitalizedString];

		assert( [tag.key rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0 );
		assert( [tag.value rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0 );

		[_tagArray addObject:tag];
	}
}

-(IBAction)saveXml:(id)sender
{
	NSXMLElement * root = (NSXMLElement *)[NSXMLNode elementWithName:@"tags"];
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithRootElement:root];
	[doc setCharacterEncoding:@"UTF-8"];

	for ( TagInfo * tag in _tagArray ) {
		NSXMLElement * element = [NSXMLNode elementWithName:@"tag"];
		[element addAttribute:[NSXMLNode attributeWithName:@"key"			stringValue:tag.key]];
		[element addAttribute:[NSXMLNode attributeWithName:@"value"			stringValue:tag.value]];
		if ( tag.friendlyName.length )
			[element addAttribute:[NSXMLNode attributeWithName:@"name"			stringValue:tag.friendlyName]];
		if ( tag.belongsTo.length )
			[element addAttribute:[NSXMLNode attributeWithName:@"belongsTo"		stringValue:tag.belongsTo]];
		if ( tag.description.length )
			[element addAttribute:[NSXMLNode attributeWithName:@"description"	stringValue:tag.description]];
		if ( tag.iconName.length )
			[element addAttribute:[NSXMLNode attributeWithName:@"iconName"		stringValue:tag.iconName]];
		if ( tag.wikiPage.length )
			[element addAttribute:[NSXMLNode attributeWithName:@"wikiPage"		stringValue:tag.wikiPage]];
		if ( tag.lineColor )
			[element addAttribute:[NSXMLNode attributeWithName:@"lineColor" stringValue:[TagInfo stringForColor:tag.lineColor]]];
		if ( tag.areaColor )
			[element addAttribute:[NSXMLNode attributeWithName:@"areaColor" stringValue:[TagInfo stringForColor:tag.areaColor]]];
		if ( tag.lineWidth )
			[element addAttribute:[NSXMLNode attributeWithName:@"lineWidth" stringValue:[NSString stringWithFormat:@"%f",tag.lineWidth]]];

		[root addChild:element];
	}
	[root addAttribute:[NSXMLNode attributeWithName:@"version" stringValue:@"1"]];

	NSError * error = nil;
	[[doc XMLStringWithOptions:NSXMLNodePrettyPrint] writeToFile:@"TagInfo.xml" atomically:YES encoding:NSUTF8StringEncoding error:&error];
	if ( error ) {
		NSAlert * alert = [NSAlert alertWithError:error];
		[alert beginSheetModalForWindow:self.window modalDelegate:self didEndSelector:nil contextInfo:NULL];
	}
}

-(TagInfo *)lookupTagForKey:(NSString *)key value:(NSString *)value
{
	NSArray * matches = [_tagArray filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TagInfo * object, NSDictionary *bindings) {
		return [object.key isEqualToString:key] && [object.value isEqualToString:value];
	}]];
	return matches.count ? matches.lastObject : nil;
}

-(void)readPotlatch2
{
	NSArray * files = @[
		@"amenities.xml",	@"buildings.xml",	@"man_made.xml",	@"places.xml",
		@"roads.xml",		@"tourism.xml",		@"water.xml",		@"barriers.xml",
		@"landuse.xml",		@"paths.xml",		@"power.xml",		@"shopping.xml",	@"transport.xml"
	];
	for ( NSString * file in files ) {
		NSError * error = nil;
		NSString * text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:&error];
		NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
		NSXMLElement * root = [doc rootElement];
		for ( NSXMLElement * feature in root.children ) {

			if ( ![feature.name isEqualToString:@"feature"] ) {
				DLog(@"skipping %@",feature);
				continue;
			}

			TagInfo * tagType = nil;

			// key/value
			NSArray * tags = [feature elementsForName:@"tag"];
			if ( tags.count ) {
				NSXMLElement * tagNode = tags.lastObject;
				NSString * key = [tagNode attributeForName:@"k"].stringValue;
				NSString * value = [tagNode attributeForName:@"v"].stringValue;

				tagType = [self lookupTagForKey:key value:value];
				if ( tagType == nil ) {
					DLog(@"missing tag %@=%@",key,value);
					continue;
				}
			}

			// wiki
			if ( tagType.wikiPage.length < 2 ) {
				NSArray * wikis = [feature elementsForName:@"help"];
				if ( wikis.count ) {
					NSXMLElement * wikiElement = wikis.lastObject;
					NSString * url = wikiElement.stringValue;
					url = [url stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if ( url.length > 0 )
						tagType.wikiPage = url;
				}
			}
			
			// icon
			if ( tagType.iconName.length < 2 ) {
				NSArray * icons = [feature elementsForName:@"icon"];
				if ( icons.count ) {
					NSXMLElement * iconNode = icons.lastObject;
					NSString * path = [iconNode attributeForName:@"image"].stringValue;
					path = [path lastPathComponent];
					path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					NSInteger index = [path rangeOfString:@"."].location;
					if ( index != NSNotFound ) {
						path = [path substringToIndex:index];
					}
					if ( path.length > 0 )
						tagType.iconName = path;
				}
			}
		}
	}
}

// http://svn.openstreetmap.org/applications/share/map-icons
// (cd /tmp/icons/map-icons/square.big/ && find . -name '*.png') | awk '{s = $1;gsub("\/",".",s);s=substr(s,3);print "cp -pr", $1, "/tmp/icon-list/"s;}' | sh
-(void)readMapIcons
{
	NSError * error = nil;
	NSString * file = [[NSBundle mainBundle] pathForResource:@"icons" ofType:@"xml"];
	NSString * text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:&error];
	if ( text.length == 0 )
		return;
	NSXMLDocument * doc = [[NSXMLDocument alloc] initWithXMLString:text options:0 error:&error];
	NSXMLElement * root = [doc rootElement];
	for ( NSXMLElement * rule in [root elementsForName:@"rule"] ) {
		if ( ![[rule attributeForName:@"k"].stringValue isEqualToString:@"poi"]  ) {
			continue;
		}
		NSString * path = [rule attributeForName:@"v"].stringValue;
		assert( path.length );
		path = [path stringByAppendingPathExtension:@"png"];

		NSArray * conditionList = [rule elementsForName:@"condition"];
		if ( conditionList.count > 1 )
			continue;
		if ( conditionList.count == 0 )
			continue;
		if ( [rule elementsForName:@"condition_2nd"] )
			continue;
		NSXMLElement * condition = conditionList.lastObject;

		NSString * key		= [condition attributeForName:@"k"].stringValue;
		NSString * value	= [condition attributeForName:@"v"].stringValue;
		NSString * b		= [condition attributeForName:@"b"].stringValue;

		if ( value == nil ) {
			if ( b ) {
				if ( [b isEqualToString:@"yes"] ) {
					value = @"yes";
				} else if ( [b isEqualToString:@"no"] ) {
					value = @"no";
				} else {
					assert(NO);
				}
			}
		}
		if ( value.length == 0 ) {
			value = @"*";
		}

		TagInfo * tagType	= [self lookupTagForKey:key value:value];
		if ( tagType == nil ) {
			DLog(@"missing tag: '%@'='%@'",key,value);
			continue;
		}

		DLog(@"%@=%@: %@",key,value,path);
		tagType.iconName = path;
	}
}


-(void)readDescriptions
{
	// select key,value,description from wikipages where lang='en';
	NSString * all = [NSString stringWithContentsOfFile:@"o.txt" encoding:NSUTF8StringEncoding error:NULL];
	NSArray * lines = [all componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	for ( NSString * line in lines ) {
		NSArray * parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"|"]];
		if ( parts.count != 3 ) {
			DLog(@"bad line: %@",line);
			continue;
		}
		NSString * key = parts[0];
		NSString * value = parts[1];
		NSString * desc = parts[2];

		TagInfo * tagType	= [self lookupTagForKey:key value:value];
		if ( tagType == nil ) {
			DLog(@"missing tag: '%@'='%@'",key,value);
			continue;
		}
		if ( value.length == 0 )
			continue;
		tagType.description = desc;
	}
}

static NSColor * ColorFromString( const char * text )
{
	if ( text == NULL )
		return nil;
	const char * p = strrchr( text, '#' );
	if ( p )
		++p;
	else
		p = text;
	int r,g,b;
	sscanf( p, "%2x%2x%2x", &r, &g, &b);
	return [NSColor colorWithCalibratedRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

-(void)readJosmDatabase
{
	NSString * path = [[NSBundle mainBundle] pathForResource:@"taginfo-josm" ofType:@"db"];

	sqlite3 * db = NULL;
	int rc = sqlite3_open(path.UTF8String, &db);
	if ( rc ) {
		return;
	}

    sqlite3_stmt *statement;
	rc = sqlite3_prepare_v2( db, "SELECT k,v,line_color,line_width,area_color FROM josm_style_rules", -1, &statement, nil );
    assert(rc == SQLITE_OK);
	while ( sqlite3_step(statement) == SQLITE_ROW )  {
		const char * szKey			= (char *)sqlite3_column_text(statement, 0);
		const char * szValue		= (char *)sqlite3_column_text(statement, 1);
		const char * szLineColor	= (char *)sqlite3_column_text(statement, 2);
		const char * szLineWidth	= (char *)sqlite3_column_text(statement, 3);
		const char * szAreaColor	= (char *)sqlite3_column_text(statement, 4);

		if ( szKey == NULL || szValue == NULL )
			continue;
		if ( szLineColor == NULL && szLineWidth == NULL && szAreaColor == NULL )
			continue;
		NSString * key			= [[NSString alloc] initWithUTF8String:szKey];
		NSString * value		= [[NSString alloc] initWithUTF8String:szValue];

		TagInfo	* tagType = [self lookupTagForKey:key value:value];
		if ( tagType == nil ) {
			DLog(@"missing %@=%@",key,value);
			continue;
		}

		tagType.lineColor	= ColorFromString( szLineColor );
		tagType.areaColor	= ColorFromString( szAreaColor );
		tagType.lineWidth	= szLineWidth ? atof( szLineWidth ) : 0;
	}
	sqlite3_finalize(statement);
	sqlite3_close(db);
}



-(NSString *)searchText
{
	return _searchText;
}
-(void)setSearchText:(NSString *)searchText
{
	_searchText = searchText;
	if ( _searchText.length ) {
		self.arrayController.filterPredicate = [NSPredicate predicateWithBlock:^BOOL(TagInfo * evaluatedObject, NSDictionary *bindings) {
			if ( [evaluatedObject.key rangeOfString:searchText].length )
				return YES;
			if ( [evaluatedObject.value rangeOfString:searchText].length )
				return YES;
			return NO;
		}];
	} else {
		self.arrayController.filterPredicate = nil;
	}
}

-(void)windowDidLoad
{
	[_tableView registerForDraggedTypes:@[
		NSPasteboardTypeString,
		NSFilenamesPboardType,
		NSPasteboardTypePNG]
	 ];
}

#if 0
 - (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id )info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
	// Add code here to validate the drop
	//DLog(@"validate Drop");
	return NSDragOperationEvery;
}

- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	NSPasteboard* pboard = [info draggingPasteboard];
	NSData* rowData = [pboard dataForType:MyPrivateTableViewDataType];
	NSIndexSet* rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
	NSInteger dragRow = [rowIndexes firstIndex];
	// Move the specified row to its new location...
	// if we remove a row then everything moves down by one
	// so do an insert prior to the delete
	// --- depends which way we're moving the data!!!
	if (dragRow < row) {
		[self.nsMutaryOfMyData insertObject: [self.nsMutaryOfMyData objectAtIndex:dragRow] atIndex:row];
		[self.nsMutaryOfMyData removeObjectAtIndex:dragRow];
		[self.nsTableViewObj noteNumberOfRowsChanged];
		[self.nsTableViewObj reloadData];
		return YES;
	}
	// end
	if MyData * zData = [self.nsMutaryOfMyData objectAtIndex:dragRow];
	[self.nsMutaryOfMyData removeObjectAtIndex:dragRow];
	[self.nsMutaryOfMyData insertObject:zData atIndex:row];
	[self.nsTableViewObj noteNumberOfRowsChanged];
	[self.nsTableViewObj reloadData];
	return YES;
}
#endif

@end
