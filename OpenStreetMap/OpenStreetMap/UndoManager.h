//
//  UndoManager.h
//  Go Map!
//
//  Created by Bryce on 8/16/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"



@interface UndoAction : NSObject <NSCoding>
@property (copy,nonatomic)		NSString	*	selector;
@property (strong,nonatomic)	id				target;
@property (strong,nonatomic)	NSArray		*	objects;
@property (assign)				NSInteger		group;
@property (strong,nonatomic)	NSInvocation *	invocation;
@end

typedef void(^UndoManagerChangeCallback)(void);

@interface UndoManager : NSObject <NSCoding>
{
	CFRunLoopObserverRef _runLoopObserver;
	
	NSMutableArray	*	_undoStack;
	NSMutableArray	*	_redoStack;
	
	BOOL				_isUndoing;
	BOOL				_isRedoing;

	NSMutableArray	*	_groupingStack;	// for explicit grouping

	NSMutableArray	*	_observerList;

	NSMutableArray	*	_commentList;
}

@property (strong,nonatomic) void (^commentCallback)(BOOL undo,NSArray * comments);
@property (strong,nonatomic) NSData * (^locationCallback)();

@property (readonly) BOOL isUndoing;
@property (readonly) BOOL isRedoing;
@property (readonly) BOOL canUndo;
@property (readonly) BOOL canRedo;
@property (assign) NSInteger runLoopCounter;

-(NSArray *)objectRefs;

-(void)addChangeCallback:(UndoManagerChangeCallback)callback;

- (void)registerUndoComment:(NSString *)comment;
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects;
- (id)registerUndoWithInvocationTarget:(id)target;

-(void)registerUndo:(UndoAction *)action;
-(void)undo;
-(void)redo;
-(void)removeAllActions;
-(void)removeMostRecentRedo;

-(void)beginUndoGrouping;
-(void)endUndoGrouping;

@end
