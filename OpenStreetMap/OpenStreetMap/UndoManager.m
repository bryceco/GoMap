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


@implementation UndoAction

- (void)encodeWithCoder:(NSCoder *)coder
{
	if ( [coder allowsKeyedCoding] ) {
		[coder encodeObject:_target		forKey:@"target"];
		[coder encodeObject:_selector	forKey:@"selector"];
		[coder encodeObject:_objects	forKey:@"objects"];
		[coder encodeInteger:_group		forKey:@"group"];
	} else {
		[coder encodeObject:_target];
		[coder encodeObject:_selector];
		[coder encodeObject:_objects];
		[coder encodeBytes:&_group length:sizeof _group];
	}
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if ( [coder allowsKeyedCoding] ) {
		_target		= [coder decodeObjectForKey:@"target"];
		_selector	= [coder decodeObjectForKey:@"selector"];
		_objects	= [coder decodeObjectForKey:@"objects"];
		_group		= [coder decodeIntegerForKey:@"group"];
	} else {
		_target		= [coder decodeObject];
		_selector	= [coder decodeObject];
		_objects	= [coder decodeObject];
		_group		= *(NSInteger *)[coder decodeBytesWithReturnedLength:NULL];
	}
    return self;
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
	
	if ( _invocation ) {
		[_invocation invoke];
		return;
	}
	
	// unknown action type
	assert(NO);
}

@end


@interface UndoProxy : NSProxy
{
	id				_target;
	UndoManager	*	_undoManager;
}
+ (UndoProxy *)undoProxyWithTarget:(id)target manager:(UndoManager *)manager;
@end
@implementation UndoProxy
- (id)initWithTarget:(id)aTarget manager:(UndoManager *)manager
{
	_target = aTarget;
	_undoManager = manager;
	return self;
}
+ (UndoProxy *)undoProxyWithTarget:(id)target manager:(UndoManager *)manager
{
	return [[UndoProxy alloc] initWithTarget:target manager:manager];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	return [_target methodSignatureForSelector:selector];
}
- (void)forwardInvocation:(NSInvocation *)invocation
{
	[invocation setTarget:_target];
	UndoAction * action = [[UndoAction alloc] init];
	action.target		= _target;
	action.invocation	= invocation;
	[_undoManager registerUndo:action];
}
@end


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
	}
	return self;
}

-(BOOL) canUndo
{
	return _undoStack.count > 0;
}
-(BOOL) canRedo
{
	return _redoStack.count > 0;
}

-(void)removeMostRecentRedo
{
	assert( _redoStack.count );

	NSInteger group = ((UndoAction *)_redoStack.lastObject).group;
	while ( _redoStack.count && ((UndoAction *)_redoStack.lastObject).group == group ) {
		[_redoStack removeLastObject];
	}

	for ( UndoManagerChangeCallback callback in _observerList ) {
		callback();
	}
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

	for ( UndoManagerChangeCallback callback in _observerList ) {
		callback();
	}
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

	for ( UndoManagerChangeCallback callback in _observerList ) {
		callback();
	}
}

- (void)registerUndoWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects
{
	assert(target);
	UndoAction * action = [[UndoAction alloc] init];
	action.target = target;
	action.selector = NSStringFromSelector(selector);
	action.objects = objects;
	assert( action.selector );
	[self registerUndo:action];
}

- (void)doComment:(NSString *)comment location:(NSData *)location
{
	[self registerUndoWithTarget:self selector:@selector(doComment:location:) objects:@[comment,location]];
	[_commentList addObject:@[comment,location]];
}

- (void)registerUndoComment:(NSString *)comment
{
	NSData * location = self.locationCallback();
	[self registerUndoWithTarget:self selector:@selector(doComment:location:) objects:@[comment,location]];
}

-(id)registerUndoWithInvocationTarget:(id)target
{
	return [UndoProxy undoProxyWithTarget:target manager:self];
}

+(void)doActionGroupFromStack:(NSMutableArray *)stack
{
	NSInteger currentGroup = -1;
	
	while ( stack.count ) {
		UndoAction * action = stack.lastObject;
		assert(action.group);
		if ( currentGroup < 0 ) {
			currentGroup = action.group;
			DLog(@"undo group %d",(int32_t)currentGroup);
		} else if ( action.group != currentGroup )
			break;

		[stack removeLastObject];

//		DLog(@"-- Undo action: '%@' %@", action.selector, [action.target description] );
		[action performAction];
	}
}

-(void)undo
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

	for ( UndoManagerChangeCallback callback in _observerList ) {
		callback();
	}
	if ( self.commentCallback ) {
		self.commentCallback( YES, _commentList );
	}
}

-(void)redo
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

	for ( UndoManagerChangeCallback callback in _observerList ) {
		callback();
	}
	if ( self.commentCallback ) {
		self.commentCallback( NO, _commentList );
	}
}

-(void)beginUndoGrouping
{
	NSNumber * group = _groupingStack.count ? _groupingStack.lastObject : @(self.runLoopCounter);
	DLog(@"begin undo group %@",group);
	[_groupingStack addObject:group];
}
-(void)endUndoGrouping
{
	DLog(@"end undo group %@",[_groupingStack lastObject]);
	[_groupingStack removeLastObject];
}

-(void)addChangeCallback:(UndoManagerChangeCallback)callback
{
	if ( _observerList == nil ) {
		_observerList = [NSMutableArray arrayWithObject:callback];
	} else {
		[_observerList addObject:callback];
	}
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
		_undoStack = [coder decodeObject];
		_redoStack = [coder decodeObject];
		_runLoopCounter = *(NSInteger *)[coder decodeBytesWithReturnedLength:NULL];
	}
    return self;
}

-(void)dealloc
{
	CFRunLoopRemoveObserver( CFRunLoopGetMain(), _runLoopObserver, kCFRunLoopCommonModes );
}

@end
