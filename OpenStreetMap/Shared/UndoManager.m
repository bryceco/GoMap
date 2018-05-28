//
//  UndoManager.m
//  Spider
//
//  Created by Bryce Cogswell on 8/16/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "DLog.h"
#import "UndoManager.h"

@class OsmBaseObject;

static void RunLoopObserverCallBack(CFRunLoopObserverRef observer,CFRunLoopActivity activity,void *info)
{
	if ( activity & kCFRunLoopAfterWaiting ) {
		UndoManager * undoManager = (__bridge id)info;
		++undoManager.runLoopCounter;
	}
}


#pragma mark UndoAction

@interface UndoAction : NSObject <NSCoding>
@property (readonly,nonatomic)	NSString	*	selector;
@property (readonly,nonatomic)	id				target;
@property (readonly,nonatomic)	NSArray		*	objects;
@property (assign,nonatomic)	NSInteger		group;
@end


@implementation UndoAction

-(instancetype)initWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects
{
	DbgAssert( target && selector );
	self = [super init];
	if ( self ) {
		_target = target;
		_selector = NSStringFromSelector(selector);
		_objects = objects;
	}
	return self;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
	DbgAssert(_target);
	[coder encodeObject:_target		forKey:@"target"];
	[coder encodeObject:_selector	forKey:@"selector"];
	[coder encodeObject:_objects	forKey:@"objects"];
	[coder encodeInteger:_group		forKey:@"group"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	_target		= [coder decodeObjectForKey:@"target"];
	_selector	= [coder decodeObjectForKey:@"selector"];
	_objects	= [coder decodeObjectForKey:@"objects"];
	_group		= [coder decodeIntegerForKey:@"group"];
	DbgAssert(_target);
    return self;
}

-(NSString *)description
{
	return [NSString stringWithFormat:@"%@ %@ %@ (%@) %ld", [super description], _target, _selector, _objects, (long)_group];
}

-(void)performAction
{
	if ( _selector ) {
		// method call
		SEL selector = NSSelectorFromString(_selector);
		assert(_target);
		assert(_objects);
		NSMethodSignature * sig = [_target methodSignatureForSelector:selector];
		assert( sig );
		assert( _objects.count+2 == [sig numberOfArguments] );
		NSInvocation * invocation = [NSInvocation invocationWithMethodSignature:sig];
		invocation.selector = selector;
		invocation.target = _target;
		for ( NSInteger index = 0; index < _objects.count; ++index ) {
			id obj = _objects[index];

			const char * type = [sig getArgumentTypeAtIndex:2+index];
			switch ( *type ) {
				case 'c':
					{
						char c = [obj charValue];
						[invocation setArgument:(void *)&c atIndex:2+index];
					}
					break;
				case 'd':
					{
						double d = [obj doubleValue];
						[invocation setArgument:(void *)&d atIndex:2+index];
					}
					break;
				case 'i':
					{
						int i = (int)[obj integerValue];
						[invocation setArgument:(void *)&i atIndex:2+index];
					}
					break;
				case 'q':
					{
						long long l = [obj longLongValue];
						[invocation setArgument:(void *)&l atIndex:2+index];
					}
					break;
				case 'B':
					{
						BOOL b = [obj boolValue];
						[invocation setArgument:(void *)&b atIndex:2+index];
					}
					break;
				case '@':
					if ( obj == [NSNull null] )
						obj = nil;
					[invocation setArgument:(void *)&obj atIndex:2+index];
					break;
				default:
					assert(NO);
			}
		}
		[invocation invoke];
		return;
	}
	
	// unknown action type
	assert(NO);
}

@end


#pragma mark UndoManager

@implementation UndoManager

@synthesize isUndoing = _isUndoing;
@synthesize isRedoing = _isRedoing;

-(id)init
{
	self = [super init];
	if ( self ) {
		_undoStack = [NSMutableArray array];
		_redoStack = [NSMutableArray array];

		_groupingStack = [NSMutableArray new];
		
		CFRunLoopObserverContext context = { 0 };
		context.info = (__bridge void *)self;
		_runLoopObserver = CFRunLoopObserverCreate( kCFAllocatorDefault, kCFRunLoopAfterWaiting,
																YES, 0, RunLoopObserverCallBack, &context );
		CFRunLoopAddObserver(CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes);
//		DLog(@"add observer %@",_runLoopObserver);
	}
	return self;
}

-(void)dealloc
{
	if ( _runLoopObserver ) {
		CFRunLoopRemoveObserver( CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes );
//		DLog(@"remove observer %@",_runLoopObserver);
	}
}

-(NSString *)description
{
	NSMutableString * text = [NSMutableString new];
	[text appendFormat:@"undo stack:\n"];
	[text appendFormat:@"   run loop = %ld\n", (long)_runLoopCounter];
	[text appendFormat:@"   group = %@\n", _groupingStack.count ? _groupingStack.lastObject : @"none"];
	for ( UndoAction * action in _undoStack ) {
		[text appendFormat:@"   %ld: %@\n", (long)action.group, action.selector];
	}
	return text;
}

-(BOOL) canUndo
{
	return _undoStack.count > 0;
}
-(BOOL) canRedo
{
	return _redoStack.count > 0;
}

-(NSInteger)count
{
	return _undoStack.count + _redoStack.count;
}

-(void)postChangeNotification
{
	NSNotification * notification = [NSNotification notificationWithName:UndoManagerDidChangeNotification object:self];
	[[NSNotificationQueue defaultQueue] enqueueNotification:notification postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnName|NSNotificationCoalescingOnSender forModes:nil];
}

-(void)removeMostRecentRedo
{
	assert( _redoStack.count );

	NSInteger group = ((UndoAction *)_redoStack.lastObject).group;
	while ( _redoStack.count && ((UndoAction *)_redoStack.lastObject).group == group ) {
		[_redoStack removeLastObject];
	}

	[self postChangeNotification];
}

- (void) removeAllActions
{
	[self willChangeValueForKey:@"canUndo"];
	[self willChangeValueForKey:@"canRedo"];

	assert(!_isUndoing && !_isRedoing);
	[_undoStack removeAllObjects];
	[_redoStack removeAllObjects];

	[self didChangeValueForKey:@"canUndo"];
	[self didChangeValueForKey:@"canRedo"];

	[self postChangeNotification];
}

-(void)registerUndo:(UndoAction *)action
{
	action.group = _groupingStack.count ? [_groupingStack.lastObject integerValue] : self.runLoopCounter;

	[self willChangeValueForKey:@"canUndo"];
	[self willChangeValueForKey:@"canRedo"];
	
	if ( _isUndoing ) {
		[_redoStack addObject:action];
	} else if ( _isRedoing ) {
		[_undoStack addObject:action];
	} else {
		[_undoStack addObject:action];
		[_redoStack removeAllObjects];
	}

	[self didChangeValueForKey:@"canUndo"];
	[self didChangeValueForKey:@"canRedo"];

	[self postChangeNotification];
}

- (void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects
{
	assert(target);
	DbgAssert( [target respondsToSelector:selector] );

	UndoAction * action = [[UndoAction alloc] initWithTarget:target selector:selector objects:objects];
	[self registerUndo:action];
}

- (void)doComment:(NSDictionary *)comment
{
	[self registerUndoWithTarget:self selector:@selector(doComment:) objects:@[comment]];
	[_commentList addObject:comment];
}

- (void)registerUndoComment:(NSDictionary *)comment
{
	[self registerUndoWithTarget:self selector:@selector(doComment:) objects:@[comment]];
}

+(void)doActionGroupFromStack:(NSMutableArray *)stack
{
	NSInteger currentGroup = -1;
	
	while ( stack.count ) {
		UndoAction * action = stack.lastObject;
		assert(action.group);
		if ( currentGroup < 0 ) {
			currentGroup = action.group;
		} else if ( action.group != currentGroup )
			break;

		[stack removeLastObject];

//		DLog(@"-- Undo action: '%@' %@", action.selector, [action.target description] );
		[action performAction];
	}
}

-(NSDictionary *)undo
{
	_commentList = [NSMutableArray new];

	[self willChangeValueForKey:@"canUndo"];
	[self willChangeValueForKey:@"canRedo"];

	assert(!_isUndoing && !_isRedoing);
	_isUndoing = YES;
	[UndoManager doActionGroupFromStack:_undoStack];
	_isUndoing = NO;

	[self didChangeValueForKey:@"canUndo"];
	[self didChangeValueForKey:@"canRedo"];

	[self postChangeNotification];

	NSDictionary * comment = _commentList.count == 0 ? nil : _commentList.lastObject;
	return comment;
}

-(NSDictionary *)redo
{
	_commentList = [NSMutableArray new];

	[self willChangeValueForKey:@"canUndo"];
	[self willChangeValueForKey:@"canRedo"];

	assert(!_isUndoing && !_isRedoing);
	_isRedoing = YES;
	[UndoManager doActionGroupFromStack:_redoStack];
	_isRedoing = NO;

	[self didChangeValueForKey:@"canUndo"];
	[self didChangeValueForKey:@"canRedo"];

	[self postChangeNotification];
	
	NSDictionary * comment = _commentList.count == 0 ? nil: _commentList[0];
	return comment;
}

-(void)beginUndoGrouping
{
	NSNumber * group = _groupingStack.count ? _groupingStack.lastObject : @(self.runLoopCounter);
	[_groupingStack addObject:group];
}
-(void)endUndoGrouping
{
	[_groupingStack removeLastObject];
}

-(NSSet *)objectRefs
{
	NSMutableSet * refs = [NSMutableSet new];
	for ( UndoAction * action in _undoStack ) {
		[refs addObject:action.target];
		[refs addObjectsFromArray:action.objects];
	}
	for ( UndoAction * action in _redoStack ) {
		[refs addObject:action.target];
		[refs addObjectsFromArray:action.objects];
	}
	return refs;
}


- (void)encodeWithCoder:(NSCoder *)coder
{
	if ( [coder allowsKeyedCoding] ) {
		[coder encodeObject:_undoStack forKey:@"undoStack"];
		[coder encodeObject:_redoStack forKey:@"redoStack"];
		[coder encodeInteger:_runLoopCounter forKey:@"runLoopCounter"];
	} else {
		[coder encodeObject:_undoStack];
		[coder encodeObject:_redoStack];
		[coder encodeBytes:&_runLoopCounter length:sizeof _runLoopCounter];
	}
}
- (id)initWithCoder:(NSCoder *)coder
{
	self = [self init];
	if ( [coder allowsKeyedCoding] ) {
		_undoStack = [coder decodeObjectForKey:@"undoStack"];
		_redoStack = [coder decodeObjectForKey:@"redoStack"];
		_runLoopCounter = [coder decodeIntegerForKey:@"runLoopCounter"];
	} else {
		NSUInteger len;
		_undoStack = [coder decodeObject];
		_redoStack = [coder decodeObject];
		_runLoopCounter = *(NSInteger *)[coder decodeBytesWithReturnedLength:&len];
	}
    return self;
}

@end
