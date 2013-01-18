//
//  MapCSS.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 11/11/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import "MapCSS.h"
#import "MapCssLex.h"
#import "OsmObjects.h"

#define yylex			MapCSS_lex
#define yytext			MapCSS_text
#define yyin			MapCSS_in
#define yylex_destroy	MapCSS_lex_destroy
#define yylineno		MapCSS_lineno

extern int		yylex();
extern char	*	yytext;
extern int		yylineno;
extern FILE *	yyin;
extern int		yylex_destroy(void);


static int token;


@implementation MapCssCondition
-(BOOL)matchTags:(OsmBaseObject *)object
{
	NSString * value = [object.tags valueForKey:self.tag];
	if ( value == nil && [self.tag isEqualToString:@"way_area"] && object.isWay ) {
		double area = [(OsmWay *)object wayArea];
		value = [@(area) stringValue];
	}

	if ( self.relation == nil ) {
		assert( self.value == nil );
		return value != nil;
	} else if ( [self.relation isEqualToString:@"?"] ) {
		assert( self.value == nil );
		return [value isEqualToString:@"yes"] || [value isEqualToString:@"true"] || [value isEqualToString:@"1"];
	} else if ( [self.relation isEqualToString:@"!?"] ) {
		assert( self.value == nil );
		return !([value isEqualToString:@"yes"] || [value isEqualToString:@"true"] || [value isEqualToString:@"1"]);
	} else if ( [self.relation isEqualToString:@"!"] ) {
		assert( self.value == nil );
		return value == nil || [value isEqualToString:@"no"] || [value isEqualToString:@"false"] || [value isEqualToString:@"0"];
	} else if ( [self.relation isEqualToString:@"="] ) {
		return [value isEqualToString:self.value];
	} else if ( [self.relation isEqualToString:@"!="] ) {
		return ![value isEqualToString:self.value];
	} else if ( [self.relation isEqualToString:@">="] ) {
		return value.doubleValue >= self.value.doubleValue;
	} else if ( [self.relation isEqualToString:@">"] ) {
		return value.doubleValue > self.value.doubleValue;
	} else if ( [self.relation isEqualToString:@"<="] ) {
		return value.doubleValue <= self.value.doubleValue;
	} else if ( [self.relation isEqualToString:@"<"] ) {
		return value.doubleValue < self.value.doubleValue;
	} else if ( [self.relation isEqualToString:@"=~"] ) {
		NSError *error = nil;
		NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:self.value options:0 error:&error];
		assert(re);
		return [re numberOfMatchesInString:value options:NSMatchingAnchored range:NSMakeRange(0, self.value.length)] > 0;
	} else {
		assert(NO);
	}
	return NO;
}
@end

@implementation MapCssSelector
-(BOOL)matchObject:(OsmBaseObject *)object zoom:(NSInteger)zoom
{
	// type
	if ( [self.type isEqualToString:@"way"] ) {
		if ( !object.isWay )
			return NO;
	} else if ( [self.type isEqualToString:@"area"] ) {
		if ( !object.isWay )
			return NO;
		if ( ![(OsmWay *)object isArea] )
			return NO;
	} else if ( [self.type isEqualToString:@"node"] ) {
		if ( !object.isNode )
			return NO;
	} else if ( [self.type isEqualToString:@"line"] ) {
		if ( !object.isWay )
			return NO;
		if ( [(OsmWay *)object isArea] )
			return NO;
	} else if ( [self.type isEqualToString:@"relation"] ) {
		if ( !object.isRelation )
			return NO;
	} else if ( [self.type isEqualToString:@"*"] ) {
		// okay
	} else if ( [self.type isEqualToString:@"meta"] ) {
		return NO;
	} else if ( [self.type isEqualToString:@"canvas"] ) {
		return NO;
	} else {
		assert(NO);
	}

	// zoom
	if ( self.zoom ) {
		int zLow = 0, zHigh = 0;
		char dash = 0;
		sscanf( self.zoom.UTF8String, "z%d%c%d", &zLow, &dash, &zHigh );
		if ( zoom < zLow )
			return NO;
		if ( dash == '-' ) {
			if ( zHigh && zoom > zHigh )
				return NO;
		} else {
			if ( zoom > zLow )
				return NO;
		}
	}

	// conditions
	for ( MapCssCondition * condition in self.conditions ) {
		if ( ![condition matchTags:object] )
			return NO;
	}

	if ( self.pseudoTag ) {
		// tagged, hasTags, selected, hover, area, closed
		if ( [self.pseudoTag isEqualToString:@"closed"] ) {
			if ( !(object.isWay && ((OsmWay *)object).isClosed) )
				return NO;
		} else if ( [self.pseudoTag isEqualToString:@"hasTags"] ) {
			if ( object.tags.count == 0 )
				return NO;
		} else {
			assert(NO);
		}
	}

	if ( self.contains ) {
		// FIXME: this is backward, it needs to be used to match the node rather than the way
		assert( object.isWay );
		OsmWay * way = (id)object;
		BOOL contains = NO;
		for ( OsmNode * node in way.nodes ) {
			contains = [self.contains matchObject:node zoom:zoom];
			if ( contains )
				break;
		}
		if ( !contains )
			return NO;
	}

#if 0
	if ( self.layerID ) {
		assert( [self.layerID isEqualToString:@"*"] );
		if ( [self.layerID isEqualToString:@"*"] ) {
			// okay
		}
	}
#endif

	return YES;
}
@end

@implementation MapCssRule
-(NSSet *)matchObject:(OsmBaseObject *)object zoom:(NSInteger)zoom
{
	NSMutableSet * subparts = nil;
	for ( MapCssSelector * selector in self.selectors ) {
		if ( [selector matchObject:object zoom:zoom] ) {
			if ( subparts == nil ) {
				subparts = [NSMutableSet setWithObject:selector.subpart];
			} else {
				[subparts addObject:selector.subpart];
			}
		}
	}
	return subparts;
}
@end



@implementation MapCSS

#define ASSERT_PARSE(x,msg) if ( !(x) ) @throw msg; else (void)0


+(id)sharedInstance
{
	static dispatch_once_t onceToken = 0;
	static MapCSS * _sharedInstance = nil;
	dispatch_once( &onceToken, ^{
		_sharedInstance = [MapCSS new];
		NSError * error = nil;
		[_sharedInstance parse:&error];
		assert(error == nil);
	});
	return _sharedInstance;
}


-(NSDictionary *)parseProperties
{
	BOOL haveExit = NO;
	ASSERT_PARSE( token == '{', @"{" );
	NSMutableDictionary * dict = [NSMutableDictionary new];
	token = yylex();
	while ( token == MAPCSS_IDENT ) {
		NSString * property = @(yytext);
		token = yylex();
		if ( token == ';' ) {
			ASSERT_PARSE( [property isEqualToString:@"exit"], @"exit");
			[dict setObject:[NSNull null] forKey:property];
			haveExit = YES;
			token = yylex();
			continue;
		}
		ASSERT_PARSE( token == ':', @":" );
		token = yylex();
		ASSERT_PARSE( token == MAPCSS_IDENT || token == MAPCSS_COLOR || token == MAPCSS_FLOAT || token == MAPCSS_QUOTE, @"value" );
		NSString * value = @(yytext);
		token = yylex();
		while ( token == ',' ) {
			token = yylex();
			ASSERT_PARSE( token == MAPCSS_IDENT || token == MAPCSS_COLOR || token == MAPCSS_FLOAT || token == MAPCSS_QUOTE, @"value" );
			NSString * val = @(yytext);
			value = [value stringByAppendingFormat:@",%@",val];
			token = yylex();
		}
		ASSERT_PARSE( token == ';', @";" );
		token = yylex();
		if ( !haveExit ) {
			[dict setObject:value forKey:property];
		}
	}
	ASSERT_PARSE( token == '}', @"}" );
	token = yylex();
	return dict;
}

-(MapCssSelector *)parseSelector
{
	ASSERT_PARSE( token == MAPCSS_IDENT, @"identifier" );
	MapCssSelector * selector = [MapCssSelector new];
	selector.type = @(yytext);

	token = yylex();
	if ( token == '|' ) {
		token = yylex();
		ASSERT_PARSE( token == MAPCSS_IDENT && yytext[0] == 'z', @"zoom factor" );
		selector.zoom = @(yytext);
		token = yylex();
	}
	while ( token == '[' ) {
		MapCssCondition * condition = [MapCssCondition new];
		token = yylex();
		if ( token == '!') {
			condition.relation = @"!";
			token = yylex();
		}
		ASSERT_PARSE( token == MAPCSS_IDENT, @"identifier" );
		condition.tag = @(yytext);
		token = yylex();
		while ( token == ':' ) {
			// addr:housenumber
			token = yylex();
			ASSERT_PARSE( token == MAPCSS_IDENT, @"identifier" );
			condition.tag = [condition.tag stringByAppendingFormat:@":%s",yytext];
			token = yylex();
		}
		if ( token == MAPCSS_COMPARISON ) {
			NSString * operator = @(yytext);
			condition.relation = condition.relation ? [condition.relation stringByAppendingString:operator] : operator;
			token = yylex();
			ASSERT_PARSE( token == MAPCSS_IDENT || token == MAPCSS_FLOAT, @"value" );
			condition.value = @(yytext);
			token = yylex();
		}
		if ( token == '?' ) {
			condition.relation = condition.relation ? [condition.relation stringByAppendingString:@"?"] : @"?";
			token = yylex();
		}
		ASSERT_PARSE( token == ']', @"]" );
		token = yylex();
		
		if ( selector.conditions == nil )
			selector.conditions = [NSMutableArray arrayWithObject:condition];
		else
			[selector.conditions addObject:condition];
	}
	if ( token == ':' ) {
		token = yylex();
		if ( token == MAPCSS_IDENT ) {
			selector.pseudoTag = @(yytext);
			token = yylex();
		}
	}
	if ( token == ':' ) {
		token = yylex();
		if ( token == MAPCSS_IDENT ) {
			selector.subpart = @(yytext);
			token = yylex();
		}
	}
	if ( selector.subpart == nil )
		selector.subpart = @"default";

	if ( token == MAPCSS_COMPARISON && yytext[0] == '>' && yytext[1] == 0 ) {
		token = yylex();
		MapCssSelector * other = [self parseSelector];
		assert(other);
		selector.contains = other;
	}

	return selector;
}

-(NSArray *)parseSelectors
{
	MapCssSelector * selector = [self parseSelector];
	NSMutableArray * a = [NSMutableArray arrayWithObject:selector];
	while ( token == ',' ) {
		token = yylex();
		selector = [self parseSelector];
		[a addObject:selector];
	}
	return a;
}

-(MapCssRule *)parseRule
{
	NSArray * selectors = [self parseSelectors];
	NSDictionary * properties = [self parseProperties];

	MapCssRule * rule = [MapCssRule new];
	rule.selectors = selectors;
	rule.properties = properties;
	return rule;
}

-(NSArray *)parseDocument
{
	token = yylex();
	NSMutableArray * a = [NSMutableArray array];
	while ( token ) {
		MapCssRule * rule = [self parseRule];
		[a addObject:rule];
	}
	return a;
}

-(BOOL)parse:(NSError **)error
{
	NSString * path = [[NSBundle mainBundle] pathForResource:@"mapnik" ofType:@"mapcss"];
	@try {
		yylex_destroy();
		yyin = fopen( path.UTF8String, "r" );
		NSArray * ruleList = [self parseDocument];
		self.rules = ruleList;
	}
	@catch ( NSString * expected ) {
		expected = [NSString stringWithFormat:@"MapCSS parse error: expected '%@' at line %d, found '%s'", expected, yylineno, yytext];
		*error = [NSError errorWithDomain:@"MapCSSParser" code:200 userInfo:@{ NSLocalizedDescriptionKey : expected}];
		self.rules = nil;
	}
	@finally {
		fclose(yyin);
		yyin = NULL;
	}
	return self.rules != nil;
}

-(NSDictionary *)matchObject:(OsmBaseObject *)object zoom:(NSInteger)zoom
{
	NSMutableDictionary * subpartDict = nil;

	for ( MapCssRule * rule in self.rules ) {
		NSSet * subparts = [rule matchObject:object zoom:zoom];
		if ( subparts ) {
			BOOL haveExit = NO;
			if ( subpartDict == nil ) {
				subpartDict = [NSMutableDictionary new];
			}
			for ( NSString * subpart in subparts ) {
				NSMutableDictionary * propertyDict = [subpartDict objectForKey:subpart];
				if ( propertyDict == nil ) {
					propertyDict = [rule.properties mutableCopy];
					[subpartDict setObject:propertyDict forKey:subpart];
				} else {
					[propertyDict addEntriesFromDictionary:rule.properties];
				}
				haveExit = [propertyDict valueForKey:@"exit"] != nil;
			}
			if ( haveExit )
				break;
		}
	}
	return subpartDict;
}

@end
