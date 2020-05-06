//
//  OsmMember.m
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import "OsmMember.h"

@implementation OsmMember

-(NSString *)description
{
    return [NSString stringWithFormat:@"%@ role=%@; type=%@;ref=%@;", [super description], _role, _type, _ref ];
}
-(id)initWithType:(NSString *)type ref:(NSNumber *)ref role:(NSString *)role
{
    self = [super init];
    if ( self ) {
        _type = type;
        _ref = ref;
        _role = role;
    }
    return self;
}
-(id)initWithRef:(OsmBaseObject *)ref role:(NSString *)role
{
    self = [super init];
    if ( self ) {
        _ref = ref;
        _role = role;
        if ( ref.isNode )
            _type = @"node";
        else if ( ref.isWay )
            _type = @"way";
        else if ( ref.isRelation )
            _type = @"relation";
        else {
            _type = nil;
        }
    }
    return self;
}

-(void)resolveRefToObject:(OsmBaseObject *)object
{
    assert( [_ref isKindOfClass:[NSNumber class]] || [_ref isKindOfClass:[OsmBaseObject class]] );
    assert( [object isKindOfClass:[NSNumber class]] || (object.isNode && self.isNode) || (object.isWay && self.isWay) || (object.isRelation && self.isRelation) );
    _ref = object;
}


-(BOOL)isNode
{
    return [_type isEqualToString:@"node"];
}
-(BOOL)isWay
{
    return [_type isEqualToString:@"way"];
}
-(BOOL)isRelation
{
    return [_type isEqualToString:@"relation"];
}

-(void)encodeWithCoder:(NSCoder *)coder
{
    OsmBaseObject * o = _ref;
    NSNumber * ref = [_ref isKindOfClass:[OsmBaseObject class]] ? o.ident : _ref;
    [coder encodeObject:_type    forKey:@"type"];
    [coder encodeObject:ref        forKey:@"ref"];
    [coder encodeObject:_role    forKey:@"role"];
}
-(id)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if ( self ) {
        _type    = [coder decodeObjectForKey:@"type"];
        _ref    = [coder decodeObjectForKey:@"ref"];
        _role    = [coder decodeObjectForKey:@"role"];
    }
    return self;
}

@end
