//
//  Notes.h
//  Go Map!!
//
//  Created by Bryce on 8/31/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"

@class OsmMapData;
@class OsmBaseObject;


@interface OsmNoteComment : NSObject
@property (readonly,nonatomic)	NSString	*	date;
@property (readonly,nonatomic)	NSString	*	action;
@property (readonly,nonatomic)	NSString	*	text;
@property (readonly,nonatomic)	NSString	*	user;
@end


@interface OsmNote : NSObject
@property (readonly,nonatomic)	double				lat;
@property (readonly,nonatomic)	double				lon;
@property (readonly,nonatomic)	NSNumber		*	ident;
@property (readonly,nonatomic)	NSString		*	created;
@property (readonly,nonatomic)	NSString		*	status;
@property (readonly,nonatomic)	NSMutableArray	*	comments;
@property (readonly,nonatomic)	BOOL				isFixme;

-(instancetype)initWithLat:(double)lat lon:(double)lon;
@end



@interface OsmNotesDatabase : NSObject
{
	NSOperationQueue	*	_workQueue;
}
@property (strong,nonatomic)	NSMutableDictionary	*	dict;
@property (weak,nonatomic)		OsmMapData			*	mapData;

-(void)updateRegion:(OSMRect)bbox withDelay:(CGFloat)delay fixmeData:(OsmMapData *)mapData completion:(void(^)(void))completion;
-(void)updateNote:(OsmNote *)note close:(BOOL)close comment:(NSString *)comment completion:(void(^)(OsmNote * newNote, NSString * errorMessage))completion;
-(void)reset;
@end
