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

@interface OsmNoteComment : NSObject
@property (readonly,nonatomic)	NSString	*	date;
@property (readonly,nonatomic)	NSString	*	action;
@property (readonly,nonatomic)	NSString	*	text;
@property (readonly,nonatomic)	NSString	*	user;
@end


@interface OsmNote : NSObject
@property (readonly,nonatomic)	double				lat;
@property (readonly,nonatomic)	double				lon;
@property (readonly,nonatomic)	NSInteger			ident;
@property (readonly,nonatomic)	NSString		*	created;
@property (readonly,nonatomic)	NSString		*	status;
@property (readonly,nonatomic)	NSMutableArray	*	comments;

-(instancetype)initWithLat:(double)lat lon:(double)lon;
@end



@interface Notes : NSObject
@property (strong,nonatomic)	NSMutableArray	*	list;
@property (weak,nonatomic)		OsmMapData		*	mapData;

-(void)updateForRegion:(OSMRect)bbox completion:(void(^)(void))completion;

//-(OsmNote *)createNoteWithLat:(double)lat Lon:(double)lon comment:(NSString *)comment;
-(void)updateNote:(OsmNote *)note close:(BOOL)close comment:(NSString *)comment completion:(void(^)(OsmNote * newNote, NSString * errorMessage))completion;

@end
