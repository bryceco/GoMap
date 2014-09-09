//
//  CoreData.m
//  Go Map!!
//
//  Created by Bryce on 9/8/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <CoreData/CoreData.h>

#import "CoreData.h"

@implementation CoreData

@synthesize persistentStoreCoordinator	= _persistentStoreCoordinator;
@synthesize managedObjectModel			= _managedObjectModel;
@synthesize managedObjectContext		= _managedObjectContext;


- (NSURL *)applicationFilesDirectory
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
	return [appSupportURL URLByAppendingPathComponent:@"com.Bryceco.GoMap"];
}

- (NSManagedObjectModel *)managedObjectModel
{
	if ( _managedObjectModel == nil ) {
		NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"OsmChangesetDatabase" withExtension:@"momd"];
		_managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
	}
	return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
	if ( _persistentStoreCoordinator == nil ) {
		NSManagedObjectModel *mom = [self managedObjectModel];
		if (!mom) {
			NSLog(@"%@:%@ No model to generate a store from", [self class], NSStringFromSelector(_cmd));
			return nil;
		}

		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSURL *applicationFilesDirectory = [self applicationFilesDirectory];
		[fileManager createDirectoryAtPath:[applicationFilesDirectory path] withIntermediateDirectories:YES attributes:nil error:NULL];

		NSURL *url = [applicationFilesDirectory URLByAppendingPathComponent:@"OsmChangesetDatabase.storedata"];
		NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:mom];
		if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url options:nil error:NULL]) {
			return nil;
		}
		_persistentStoreCoordinator = coordinator;
	}
	return _persistentStoreCoordinator;
}

- (NSManagedObjectContext *)managedObjectContext
{
	if (_managedObjectContext == nil) {
		if ( self.persistentStoreCoordinator == nil )
			return nil;
		_managedObjectContext = [NSManagedObjectContext new];
		[_managedObjectContext setPersistentStoreCoordinator:self.persistentStoreCoordinator];
	}
	return _managedObjectContext;
}

- (BOOL)save
{
	if ( self.managedObjectContext.hasChanges ) {
		NSError *error = nil;
		BOOL ok = [self.managedObjectContext save:&error];
		NSLog( @"Save status = %@", ok ? @"OK" : error);
		return ok;
	}
	return YES;
}

- (void)applicationWillTerminate
{
	if ( !self.managedObjectContext.hasChanges ) {
		return;
	}

	[self save];
}

@end
