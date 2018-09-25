//
//  OSMWindowController.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "BingMapsGeometry.h"
#import "ChangesWindowController.h"
#import "EditorMapLayer.h"
#import "MainWindowController.h"
#import "MapView.h"
#import "MercatorTileLayer.h"
#import "OsmMapData.h"
#import "TagEditorWindowController.h"
#import "TagInfoEditorWindowController.h"
#import "TextInputWindowController.h"
#import "UsersWindowController.h"


@implementation MainWindowController

@synthesize mapView = _mapView;


- (id)init
{
    self = [super initWithWindowNibName:@"MainWindow"];
    if ( self ) {
    }
    return self;
}

-(void)windowDidLoad
{
}

-(IBAction)editTags:(id)sender
{
	if ( _tagEditorWindowController == nil ) {
		_tagEditorWindowController = [TagEditorWindowController new];
	}
	[_tagEditorWindowController showWindow:nil];
	OsmBaseObject * object = _mapView.editorLayer.selectedNode ? (id)_mapView.editorLayer.selectedNode : (id)_mapView.editorLayer.selectedWay;
	[_tagEditorWindowController setObject:object mapData:_mapView.editorLayer.mapData];
}

-(IBAction)removeObject:(id)sender
{
	NSString * error = nil;
	EditAction delete = [_mapView.editorLayer canDeleteSelectedObject:&error];
	if ( delete )
		delete();
}

-(IBAction)cancelOperation:(id)sender
{
#if 0
	[_mapView.editorLayer cancelOperation];
#endif
}

-(IBAction)showUsers:(id)sender
{
	if ( _usersWindowController == nil ) {
		_usersWindowController = [UsersWindowController usersWindowController];
	}
	[_usersWindowController.window orderFront:self];
	OSMRect rect = [_mapView screenLongitudeLatitude];
	_usersWindowController.users = [_mapView.editorLayer.mapData userStatisticsForRegion:rect];
}


-(IBAction)showInPotlatch2:(id)sender
{
	OSMRect rect = [_mapView screenLongitudeLatitude];
	OSMPoint center = { rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height/2 };

	double z = OSMTransformScaleX( _mapView.screenFromMapTransform );
	NSInteger zoom = lround( log2( z ) );
	NSString * text = [NSString stringWithFormat:
					   @"http://www.openstreetmap.org/edit?lat=%.9f&lon=%.9f&zoom=%ld",
					   center.y, center.x, zoom];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:text]];
}
-(IBAction)showInGoogleMaps:(id)sender
{
	OSMRect rect = [_mapView screenLongitudeLatitude];
	OSMPoint center = { rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height/2 };
	NSString * text = [NSString stringWithFormat:
					   @"http://maps.google.com/maps?ll=%f,%f&spn=%f,%f",
					   center.y, center.x,
					   rect.size.height, rect.size.width];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:text]];
}

-(IBAction)purgeOsmCachedData:(id)sender
{
	[_mapView.editorLayer.mapData purgeSoft];
}
-(IBAction)purgeMapnikTileCache:(id)sender
{
	[_mapView.mapnikLayer purgeTileCache];
}
-(IBAction)purgeBingTileCache:(id)sender
{
	[_mapView.aerialLayer purgeTileCache];
}

- (IBAction)commitChangeset:(id)sender
{
	if ( _changesWindowController == nil ) {
		_changesWindowController = [[ChangesWindowController alloc] init];
		[_changesWindowController window];
	}
	if ( [_changesWindowController setMapdata:_mapView.editorLayer.mapData] ) {
		[NSApp runModalForWindow:_changesWindowController.window];
	}
}

-(IBAction)editTagInfo:(id)sender
{
	if ( _tagTypesEditorWindowController == nil ) {
		_tagTypesEditorWindowController = [TagInfoEditorWindowController new];
	}
	[_tagTypesEditorWindowController showWindow:self];
}

-(IBAction)goToLocation:(id)sender
{
	TextInputWindowController * inputWindow = [TextInputWindowController new];
	inputWindow.title  = @"New Location";
	inputWindow.prompt = @"Go to location:";
	[inputWindow beginSheetModalForWindow:self.window completionHandler:^(BOOL accepted) {
		if ( accepted ) {
			// http://www.openstreetmap.org/edit?editor=potlatch2&bbox=-75.1199358701706,39.708362827838855,-75.1122111082077,39.711354751437526
			NSCharacterSet * splitter = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.-"];
			splitter = [splitter invertedSet];
			NSString * text = inputWindow.text;
			NSMutableArray * a = [[text componentsSeparatedByCharactersInSet:splitter] mutableCopy];
			[a filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString * s, NSDictionary *bindings) {
				return s.length > 0;
			}]];
			if ( a.count < 2 ) {
				// error
			} else if ( a.count < 4 ) {
				// take last 2
				double lon = [a[a.count-2] doubleValue];
				double lat = [a[a.count-1] doubleValue];
				double widthDegrees = 60 / EarthRadius * 360;
				[_mapView setTransformForLatitude:lat longitude:lon width:widthDegrees];

			} else {
				// take last 4
				double lon1 = [a[a.count-4] doubleValue];
				double lat1 = [a[a.count-3] doubleValue];
				double lon2 = [a[a.count-2] doubleValue];
				double lat2 = [a[a.count-1] doubleValue];
				double widthDegrees = fabs( lon1 - lon2 );
				lon1 = (lon1+lon2)/2;
				lat1 = (lat1+lat2)/2;
				[_mapView setTransformForLatitude:lat1 longitude:lon1 width:widthDegrees];
			}
		}
	}];
}


-(void)mapviewSelectionChanged:(id)selection
{
	if ( _tagEditorWindowController ) {
		[_tagEditorWindowController setObject:selection mapData:_mapView.editorLayer.mapData];
	}
}

-(void)mapviewViewportChanged
{
}

-(void)doubleClickSelection:(id)selection
{
	[self editTags:nil];
}


@end
