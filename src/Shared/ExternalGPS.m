//
//  ExternalGPS.m
//  Go Map!!
//
//  Created by Bryce Cogswell on 11/19/16.
//  Copyright © 2016 Bryce Cogswell. All rights reserved.
//

#import <CoreLocation/CoreLocation.h>

//#import "AppDelegate.h"
#import "ExternalGPS.h"
#import "DLog.h"
#import "MapView.h"

@implementation ExternalGPS

-(id)init
{
	self = [super init];
	if ( self ) {

		_readData = [NSMutableData new];
		_writeData = [NSMutableData new];

		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(accessoryDidConnect:)
													 name:EAAccessoryDidConnectNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(accessoryDidDisconnect:)
													 name:EAAccessoryDidDisconnectNotification
												   object:nil];
		self.accessoryManager = [EAAccessoryManager sharedAccessoryManager];
		[self.accessoryManager registerForLocalNotifications];

		DLog( @"GPS = %@\n", self.accessoryManager.connectedAccessories );
		for ( EAAccessory * acc in self.accessoryManager.connectedAccessories ) {
			[self connectAccessory:acc];
		}
	}
	return self;
}




-(BOOL)connectAccessory:(EAAccessory *)accessory
{
	if ( _session ) {
		// disconnect previous session
		[_session.inputStream close];
		[_session.outputStream close];
		_session = nil;
	}

	BOOL isGPS = NO;
	NSString * protocol = nil;
	for ( protocol in accessory.protocolStrings ) {
		if ( [protocol isEqualToString:@"com.dualav.xgps150"] ) {
			isGPS = YES;
			break;
		}
	}
	if ( !isGPS )
		return NO;

	EASession * session = [[EASession alloc] initWithAccessory:accessory forProtocol:protocol];
	session.inputStream.delegate = self;
	[session.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[session.inputStream open];
	session.outputStream.delegate = self;
	[session.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[session.outputStream open];

	_session = session;

	return YES;
}

-(void)accessoryDidConnect:(NSNotification *)notification
{
	EAAccessory * connectedAccessory = [[notification userInfo] objectForKey:EAAccessoryKey];
	[self connectAccessory:connectedAccessory];
}

-(void)accessoryDidDisconnect:(NSNotification *)notification
{
	[_session.inputStream close];
	[_session.outputStream close];
	_session = nil;
}


// http://aprs.gids.nl/nmea/#allgp
// http://www.gpsinformation.org/dale/nmea.htm
-(void)processNMEA:(NSMutableData *)data
{
	while ( data.length > 8 ) {

		const char * str = data.bytes;

		if ( str[0] == '@' ) {
			// skip to \0
			NSInteger pos = 1;
			while ( pos < data.length && str[pos] ) {
				++pos;
			}
			if ( pos >= data.length )
				return;
			[data replaceBytesInRange:NSMakeRange(0,pos+1) withBytes:nil length:0];
			continue;
		}

		if ( str[0] == 'C' ) {
			// skip to \n
			NSInteger pos = 1;
			while ( pos < data.length && str[pos] != '\n' ) {
				++pos;
			}
			if ( pos >= data.length )
				return;
			[data replaceBytesInRange:NSMakeRange(0,pos+1) withBytes:nil length:0];
			continue;
		}

		if ( str[0] == '\0' ) {
			// end of block
			[data replaceBytesInRange:NSMakeRange(0,1) withBytes:nil length:0];
			continue;
		}

		// scan for \r\n
		NSInteger pos = 1;
		while ( pos < data.length && str[pos] != '\n' ) {
			++pos;
		}
		if ( pos >= data.length )
			return;
		NSString * line = [[NSString alloc] initWithBytes:str length:pos+1 encoding:NSUTF8StringEncoding];
//		DLog(@"%@",line);
		[data replaceBytesInRange:NSMakeRange(0,pos+1) withBytes:nil length:0];

		if ( [line hasPrefix:@"PGLL"] ) {
			// lat/lon data
			NSScanner * scanner = [[NSScanner alloc] initWithString:line];
			NSString * lat = nil;
			NSString * lon = nil;
			NSString * NS = nil;
			NSString * EW = nil;
			NSString * time = nil;
			int checksum = -1;
			[scanner scanString:@"PGLL" intoString:nil];
			[scanner scanString:@"," intoString:nil];

			[scanner scanUpToString:@"," intoString:&lat];
			[scanner scanString:@"," intoString:nil];
			[scanner scanUpToString:@"," intoString:&NS];
			[scanner scanString:@"," intoString:nil];

			[scanner scanUpToString:@"," intoString:&lon];
			[scanner scanString:@"," intoString:nil];
			[scanner scanUpToString:@"," intoString:&EW];
			[scanner scanString:@"," intoString:nil];

			[scanner scanUpToString:@"," intoString:&time];
			[scanner scanString:@"," intoString:nil];

			[scanner scanUpToString:@"*" intoString:nil];	// skip void/active marker
			[scanner scanString:@"*" intoString:nil];

			[scanner scanInt:&checksum];


			NSInteger dot = [lat rangeOfString:@"."].location;
			double dLat = [[lat substringToIndex:dot-2] doubleValue] + [[lat substringFromIndex:dot-2] doubleValue]/60.0;
			if ( [NS isEqualToString:@"S"])
				dLat = -dLat;

			dot = [lon rangeOfString:@"."].location;
			double dLon = [[lon substringToIndex:dot-2] doubleValue] + [[lon substringFromIndex:dot-2] doubleValue]/60.0;
			if ( [EW isEqualToString:@"W"] )
				dLon = -dLon;

#if TARGET_OS_IPHONE
			CLLocation * loc = [[CLLocation alloc] initWithLatitude:dLat longitude:dLon];
			DLog(@"lat/lon = %@", loc);
			AppDelegate * appDelegate = AppDelegate.shared;
			[appDelegate.mapView locationUpdatedTo:loc];
#endif
		} else if ( [line hasPrefix:@"PGSV"] ) {
			// satelite info, one line per satelite
		} else if ( [line hasPrefix:@"PGSA"] ) {
			// summary satelite info
		} else if ( [line hasPrefix:@"PRMC"] ) {
			// recommended minimum GPS data
		} else if ( [line hasPrefix:@"PVTG"] ) {
			// velocity data
		} else if ( [line hasPrefix:@"PGGA"] ) {
			// fix information
		} else if ( [line hasPrefix:@"PZDA"] ) {
			// date & time
		}
	}
}

-(void)updateReadData
{
	const NSInteger BufferSize = 128;
	u_int8_t buffer[ BufferSize ] = { 0 };

	while ( _session.inputStream.hasBytesAvailable ) {
		NSInteger bytesRead = [_session.inputStream read:buffer maxLength:BufferSize];
		[_readData appendBytes:buffer length:bytesRead];

		[self processNMEA:_readData];
	}
}

-(void)writeData
{
	while ( _session.outputStream.hasSpaceAvailable && _writeData.length > 0 ) {
		NSInteger bytesWritten = [_session.outputStream write:_writeData.bytes maxLength:_writeData.length];
		if ( bytesWritten == -1 ) {
			// error
			return;
		} else if ( bytesWritten > 0 ) {
			[_writeData replaceBytesInRange:NSMakeRange(0,bytesWritten) withBytes:nil length:0];
		}
	}
}


#pragma mark NSStream delegate methods

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
	switch ( eventCode ) {
		case NSStreamEventNone:
			break;
		case NSStreamEventOpenCompleted:
			break;
		case NSStreamEventHasBytesAvailable:
			// Read Data
			[self updateReadData];
			break;
		case NSStreamEventHasSpaceAvailable:
			// Write Data
			[self writeData];
			break;
		case NSStreamEventErrorOccurred:
			break;
		case NSStreamEventEndEncountered:
			break;
		default:
			break;
	}
}
@end
