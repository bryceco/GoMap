//
//  UndoAction.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/16/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

#import "UndoAction.h"

@implementation UndoAction

+(BOOL)supportsSecureCoding
{
	return true;
}

-(instancetype)initWithTarget:(id)target selector:(SEL)selector objects:(NSArray *)objects
{
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
	[coder encodeObject:_target		forKey:@"target"];
	[coder encodeObject:_selector  	forKey:@"selector"];
	[coder encodeObject:_objects   	forKey:@"objects"];
	[coder encodeInteger:_group 	forKey:@"group"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	_target		= [coder decodeObjectForKey:@"target"];
	_selector	= [coder decodeObjectForKey:@"selector"];
	_objects	= [coder decodeObjectForKey:@"objects"];
	_group		= [coder decodeIntegerForKey:@"group"];
	assert( _target && _selector && _objects );
	return self;
}

-(NSString *)description
{
	return [NSString stringWithFormat:@"UndoAction %ld: %@ %@",
			(long)_group,
			NSStringFromClass([_target class]),
			_selector];
}

-(void)performAction
{
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
}

@end
