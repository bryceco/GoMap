//
//  UsersWindowController.h
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface UsersWindowController : NSWindowController
{
	IBOutlet NSTableView		*	_tableView;
	IBOutlet NSArrayController	*	_arrayController;
}
@property (strong,nonatomic)	NSArray	*	users;


+(id)usersWindowController;

@end
