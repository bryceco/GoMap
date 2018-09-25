//
//  MainWindowController.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MapView.h"

@class ChangesWindowController;
@class TagEditorWindowController;
@class TagInfoEditorWindowController;
@class TextInputWindowController;
@class UsersWindowController;


@interface MainWindowController : NSWindowController
{
	TagEditorWindowController		*	_tagEditorWindowController;
	UsersWindowController			*	_usersWindowController;
	ChangesWindowController			*	_changesWindowController;
	TagInfoEditorWindowController	*	_tagTypesEditorWindowController;
	TextInputWindowController		*	_goToLocationWindow;
}

@property (assign,nonatomic) IBOutlet MapView	*	mapView;


-(IBAction)showUsers:(id)sender;
-(IBAction)showInGoogleMaps:(id)sender;
-(IBAction)showInPotlatch2:(id)sender;
-(IBAction)editTags:(id)sender;
-(IBAction)removeObject:(id)sender;
-(IBAction)purgeOsmCachedData:(id)sender;
-(IBAction)purgeMapnikTileCache:(id)sender;
-(IBAction)purgeBingTileCache:(id)sender;
-(IBAction)goToLocation:(id)sender;

-(IBAction)commitChangeset:(id)sender;

-(IBAction)editTagInfo:(id)sender;

@end
