//
//  ExifGeolocation.mm
//  PhotoShare
//
//  Created by Bryce Cogswell on 7/21/21.
//  Copyright © 2021 Bryce. All rights reserved.
//

#import "ExifGeolocation.h"
#import "easyexif/exif.h"

@implementation ExifGeolocation

+(CLLocation *)locationForImage:(NSData *)data
{
	easyexif::EXIFInfo result;

	if ( result.parseFrom((unsigned char *)data.bytes, (unsigned int)data.length) != 0 ) {
		return nil;
	}
	if ( result.GeoLocation.Latitude == 0.0 && result.GeoLocation.Longitude == 0.0 ) {
		return nil;
	}
	CLLocation * loc = [[CLLocation alloc] initWithLatitude:result.GeoLocation.Latitude
												  longitude:result.GeoLocation.Longitude];
	return loc;
}

@end
