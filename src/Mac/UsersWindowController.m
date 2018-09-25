//
//  UsersWindowController.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "UsersWindowController.h"


@implementation UsersWindowController

@synthesize users = _users;


+(id)usersWindowController
{
	UsersWindowController * wc = [[UsersWindowController alloc] initWithWindowNibName:@"UsersWindowController"];
	return wc;
}

-(void)windowDidLoad
{
	NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"user" ascending:YES selector:@selector(caseInsensitiveCompare:)];
	[_arrayController setSortDescriptors:@[sorter]];
}

-(void)setUsers:(NSArray *)users
{
	_users = users;
	[_tableView reloadData];
}

-(NSArray *)users
{
	return _users;
}

@end
