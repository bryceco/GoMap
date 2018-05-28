//
//  UndoManager.h
//  Go Map!
//
//  Created by Bryce Cogswell on 8/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"


static NSString * UndoManagerDidChangeNotification = @"UndoManagerDidChangeNotification";



typedef void(^UndoManagerChangeCallback)(void);

@interface UndoManager : NSObject <NSCoding>
{
	CFRunLoopObserverRef _runLoopObserver;
	
	NSMutableArray	*	_undoStack;
	NSMutableArray	*	_redoStack;
	
	BOOL				_isUndoing;
	BOOL				_isRedoing;

	NSMutableArray	*	_groupingStack;	// for explicit grouping

	NSMutableArray	*	_commentList;
}

@property (readonly,nonatomic) BOOL			isUndoing;
@property (readonly,nonatomic) BOOL			isRedoing;
@property (readonly,nonatomic) BOOL			canUndo;
@property (readonly,nonatomic) BOOL			canRedo;
@property (readonly,nonatomic) NSInteger	count;
@property (assign) NSInteger				runLoopCounter;

-(NSSet *)objectRefs;

- (void)registerUndoComment:(NSDictionary *)comment;
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects;

-(NSDictionary *)undo;	// returns the oldest comment registered within the undo group
-(NSDictionary *)redo;
-(void)removeAllActions;
-(void)removeMostRecentRedo;

-(void)beginUndoGrouping;
-(void)endUndoGrouping;

@end
