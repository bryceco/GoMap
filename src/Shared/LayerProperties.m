//
//  LayerProperties.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "LayerProperties.h"

@implementation LayerProperties
-(instancetype)init
{
	if ( self = [super init] ) {
		transform = CATransform3DIdentity;
	}
	return self;
}
@end

@implementation CALayerWithProperties
@synthesize properties = _properties;
-(instancetype)init
{
	if ( self = [super init] ) {
		_properties = [LayerProperties new];
	}
	return self;
}

@end

@implementation CAShapeLayerWithProperties
@synthesize properties = _properties;
-(instancetype)init
{
	if ( self = [super init] ) {
		_properties = [LayerProperties new];
	}
	return self;
}
@end

@implementation CATextLayerWithProperties
@synthesize properties = _properties;
-(instancetype)init
{
	if ( self = [super init] ) {
		_properties = [LayerProperties new];
	}
	return self;
}
@end

