//
//  Notes.m
//  Go Map!!
//
//  Created by Bryce on 8/31/14.
//  Copyright (c) 2014 Bryce. All rights reserved.
//

#if TARGET_OS_IPHONE
#import "DDXML.h"
#endif

#import "DownloadThreadPool.h"
#import "Notes.h"
#import "OsmMapData.h"

@implementation OsmNoteComment
-(instancetype)initWithXml:(NSXMLElement *)noteElement
{
	self = [super init];
	if ( self ) {
		for ( NSXMLElement * child in noteElement.children ) {
			if ( [child.name isEqualToString:@"date"] ) {
				_date = child.stringValue;
			} else if ( [child.name isEqualToString:@"user"] ) {
				_user = child.stringValue;
			} else if ( [child.name isEqualToString:@"action"] ) {
				_action = child.stringValue;
			} else if ( [child.name isEqualToString:@"text"] ) {
				_text = child.stringValue;
			}
		}
	}
	return self;
}
-(NSString *)description
{
	return [NSString stringWithFormat:@"%@ %@ %@: %@",_date,_user?:@"",_action,_text];
}
@end


@implementation OsmNote
-(instancetype)initWithXml:(NSXMLElement *)noteElement
{
	self = [super init];
	if ( self ) {
		_lat	= [noteElement attributeForName:@"lat"].stringValue.doubleValue;
		_lon	= [noteElement attributeForName:@"lon"].stringValue.doubleValue;
		for ( NSXMLElement * child in noteElement.children ) {
			if ( [child.name isEqualToString:@"id"] ) {
				_ident = child.stringValue.integerValue;
			} else if ( [child.name isEqualToString:@"date_created"] ) {
				_created = child.stringValue;
			} else if ( [child.name isEqualToString:@"status"] ) {
				_status = child.stringValue;
			} else if ( [child.name isEqualToString:@"comments"] ) {
				_comments = [NSMutableArray new];
				for ( NSXMLElement * commentElement in child.children ) {
					OsmNoteComment * comment = [[OsmNoteComment alloc] initWithXml:commentElement];
					if ( comment ) {
						[_comments addObject:comment];
					}
				}
			}
		}
	}
	return self;
}
-(NSString *)description
{
	NSMutableString * text = [NSMutableString stringWithFormat:@"Note %ld - %@:\n", (long)_ident,_status];
	for ( OsmNoteComment * comment in _comments ) {
		[text appendString:[NSString stringWithFormat:@"  %@\n",comment.description]];
	}
	return text;
}
@end


@implementation Notes

-(instancetype)init
{
	self = [super init];
	if ( self ) {
		_list = [NSMutableArray new];
	}
	return self;
}

-(void)updateForRegion:(OSMRect)box completion:(void(^)(void))completion
{
	NSString * url = [OSM_API_URL stringByAppendingFormat:@"api/0.6/notes?closed=0&bbox=%f,%f,%f,%f", box.origin.x, box.origin.y, box.origin.x+box.size.width, box.origin.y+box.size.height];
	[[DownloadThreadPool osmPool] dataForUrl:url completeOnMain:YES completion:^(NSData *data, NSError *error) {
		if ( data && error == nil ) {
			NSString * xmlText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			NSXMLDocument * xmlDoc = [[NSXMLDocument alloc] initWithXMLString:xmlText options:0 error:&error];
			NSString * text = [xmlDoc XMLStringWithOptions:(DDXMLNodePrettyPrint | DDXMLNodeCompactEmptyElement)];
			NSLog( @"%@", text);

			for ( NSXMLElement * noteElement in [xmlDoc.rootElement nodesForXPath:@"./note" error:nil] ) {
				OsmNote * note = [[OsmNote alloc] initWithXml:noteElement];
				if ( note ) {
					[_list addObject:note];
				}
			}
		}
		NSLog(@"Notes:\n%@",self);
		completion();
	}];
}

-(NSArray *)notesInRegion:(OSMRect)box
{
	return nil;
}

-(NSString *)description
{
	NSMutableString * text = [NSMutableString new];
	for ( OsmNote * note in _list ) {
		[text appendString:[note description]];
	}
	return text;;
}

@end
