//
//  UndoManager.h
//  Go Map!
//
//  Created by Bryce Cogswell on 8/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"



@interface UndoAction : NSObject <NSCoding>
@property (readonly,nonatomic)	NSString	*	selector;
@property (readonly,nonatomic)	id				target;
@property (readonly,nonatomic)	NSArray		*	objects;
@property (assign)				NSInteger		group;
@end


@protocol UndoManagerDelegate <NSObject>
-(BOOL)undoAction:(UndoAction *)newAction duplicatesPreviousAction:(UndoAction *)prevAction;
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
@property (weak,nonatomic)	id<UndoManagerDelegate> delegate;

@property (readonly) BOOL isUndoing;
@property (readonly) BOOL isRedoing;
@property (readonly) BOOL canUndo;
@property (readonly) BOOL canRedo;
@property (assign) NSInteger runLoopCounter;

-(NSSet *)objectRefs;

-(void)addChangeCallback:(UndoManagerChangeCallback)callback;

- (void)registerUndoComment:(NSString *)comment;
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects;

-(void)registerUndo:(UndoAction *)action;
-(void)undo;
-(void)redo;
-(void)removeAllActions;
-(void)removeMostRecentRedo;

-(void)beginUndoGrouping;
-(void)endUndoGrouping;

@end
