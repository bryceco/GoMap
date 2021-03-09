//
//  OsmMember.h
//  Go Map!!
//
//  Created by Wolfgang Timme on 1/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#include <Foundation/Foundation.h>

@interface OsmMember : NSObject <NSCoding>
{
    NSString *    _type;    // way, node, or relation: to help identify ref
    id            _ref;
    NSString *    _role;
}
@property (readonly,nonatomic)    NSString *    type;
@property (readonly,nonatomic)    id            ref;
@property (readonly,nonatomic)    NSString *    role;

-(id)initWithType:(NSString *)type ref:(NSNumber *)ref role:(NSString *)role;
-(id)initWithRef:(OsmBaseObject *)ref role:(NSString *)role;
-(void)resolveRefToObject:(OsmBaseObject *)object;

-(BOOL)isNode;
-(BOOL)isWay;
-(BOOL)isRelation;
@end
