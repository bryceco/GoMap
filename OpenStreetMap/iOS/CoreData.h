//
//  CoreData.h
//  Go Map!!
//
//  Created by Bryce on 9/8/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CoreData : NSObject

@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *	persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel		*	managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext		*	managedObjectContext;

@end
