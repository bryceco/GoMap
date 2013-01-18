//
//  BingMapsGeometry.h
//  OpenStreetMap
//
//  Created by Bryce on 9/26/12.
//  Copyright (c) 2012 Bryce. All rights reserved.
//

#ifndef OpenStreetMap_BingMaps_h
#define OpenStreetMap_BingMaps_h

static const double EarthRadius = 6378137;
static const double MinLatitude = -85.05112878;
static const double MaxLatitude = 85.05112878;
static const double MinLongitude = -180;
static const double MaxLongitude = 180;


/// <summary>
/// Clips a number to the specified minimum and maximum values.
/// </summary>
/// <param name="n">The number to clip.</param>
/// <param name="minValue">Minimum allowable value.</param>
/// <param name="maxValue">Maximum allowable value.</param>
/// <returns>The clipped value.</returns>
static double Clip(double n, double minValue, double maxValue)
{
	return MIN(MAX(n, minValue), maxValue);
}



/// <summary>
/// Determines the map width and height (in pixels) at a specified level
/// of detail.
/// </summary>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <returns>The map width and height in pixels.</returns>
static NSUInteger MapSize(NSInteger levelOfDetail)
{
	return (NSUInteger) 256 << levelOfDetail;
}



/// <summary>
/// Determines the ground resolution (in meters per pixel) at a specified
/// latitude and level of detail.
/// </summary>
/// <param name="latitude">Latitude (in degrees) at which to measure the
/// ground resolution.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <returns>The ground resolution, in meters per pixel.</returns>
static double GroundResolution(double latitude, NSInteger levelOfDetail)
{
	latitude = Clip(latitude, MinLatitude, MaxLatitude);
	return cos(latitude * M_PI / 180) * 2 * M_PI * EarthRadius / MapSize(levelOfDetail);
}

static int MinimumLevelOfDetail(double latitude, double metersPerPixel)
{
	double res = GroundResolution(latitude, 0);
	int levelOfDetail = (int)ceil( log2( res / metersPerPixel ) );
	return levelOfDetail;
}




/// <summary>
/// Converts a point from latitude/longitude WGS-84 coordinates (in degrees)
/// into pixel XY coordinates at a specified level of detail.
/// </summary>
/// <param name="latitude">Latitude of the point, in degrees.</param>
/// <param name="longitude">Longitude of the point, in degrees.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <param name="pixelX">Output parameter receiving the X coordinate in pixels.</param>
/// <param name="pixelY">Output parameter receiving the Y coordinate in pixels.</param>
static void LatLongToPixelXY(double latitude, double longitude, NSInteger levelOfDetail, NSInteger * pixelX, NSInteger * pixelY)
{
	latitude = Clip(latitude, MinLatitude, MaxLatitude);
	longitude = Clip(longitude, MinLongitude, MaxLongitude);

	double x = (longitude + 180) / 360;
	double sinLatitude = sin(latitude * M_PI / 180);
	double y = 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * M_PI);

	NSUInteger mapSize = MapSize(levelOfDetail);
	*pixelX = (int) Clip(x * mapSize + 0.5, 0, mapSize - 1);
	*pixelY = (int) Clip(y * mapSize + 0.5, 0, mapSize - 1);
}



/// <summary>
/// Converts a pixel from pixel XY coordinates at a specified level of detail
/// into latitude/longitude WGS-84 coordinates (in degrees).
/// </summary>
/// <param name="pixelX">X coordinate of the point, in pixels.</param>
/// <param name="pixelY">Y coordinates of the point, in pixels.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <param name="latitude">Output parameter receiving the latitude in degrees.</param>
/// <param name="longitude">Output parameter receiving the longitude in degrees.</param>
static void PixelXYToLatLong(int pixelX, int pixelY, int levelOfDetail, double * latitude, double * longitude)
{
	double mapSize = MapSize(levelOfDetail);
	double x = (Clip(pixelX, 0, mapSize - 1) / mapSize) - 0.5;
	double y = 0.5 - (Clip(pixelY, 0, mapSize - 1) / mapSize);

	*latitude = 90 - 360 * atan(exp(-y * 2 * M_PI)) / M_PI;
	*longitude = 360 * x;
}



/// <summary>
/// Converts pixel XY coordinates into tile XY coordinates of the tile containing
/// the specified pixel.
/// </summary>
/// <param name="pixelX">Pixel X coordinate.</param>
/// <param name="pixelY">Pixel Y coordinate.</param>
/// <param name="tileX">Output parameter receiving the tile X coordinate.</param>
/// <param name="tileY">Output parameter receiving the tile Y coordinate.</param>
static void PixelXYToTileXY(long pixelX, long pixelY, long * tileX, long * tileY)
{
	*tileX = pixelX / 256;
	*tileY = pixelY / 256;
}



/// <summary>
/// Converts tile XY coordinates into pixel XY coordinates of the upper-left pixel
/// of the specified tile.
/// </summary>
/// <param name="tileX">Tile X coordinate.</param>
/// <param name="tileY">Tile Y coordinate.</param>
/// <param name="pixelX">Output parameter receiving the pixel X coordinate.</param>
/// <param name="pixelY">Output parameter receiving the pixel Y coordinate.</param>
static void TileXYToPixelXY(int tileX, int tileY, int * pixelX, int * pixelY)
{
	*pixelX = tileX * 256;
	*pixelY = tileY * 256;
}



/// <summary>
/// Converts tile XY coordinates into a QuadKey at a specified level of detail.
/// </summary>
/// <param name="tileX">Tile X coordinate.</param>
/// <param name="tileY">Tile Y coordinate.</param>
/// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
/// to 23 (highest detail).</param>
/// <returns>A string containing the QuadKey.</returns>
static NSString * TileXYToQuadKey(long tileX, long tileY, long levelOfDetail)
{
	NSMutableString * quadKey = [NSMutableString string];
	for (long i = levelOfDetail; i > 0; i--)
	{
		char digit = '0';
		int mask = 1 << (i - 1);
		if ((tileX & mask) != 0)
		{
			digit++;
		}
		if ((tileY & mask) != 0)
		{
			digit++;
			digit++;
		}
		[quadKey appendFormat:@"%c",digit];
	}
	return quadKey;
}


static NSString * TileXYToQuadKey2(long tileX, long tileY, int levelOfDetail)
{
	NSMutableString * quadKey = [NSMutableString stringWithCapacity:levelOfDetail];
	for (int i = levelOfDetail; i > 0; i--)
	{
		char digit = '0';
		int mask = 1 << (i - 1);
		if ((tileX & mask) != 0)
		{
			digit++;
		}
		if ((tileY & mask) != 0)
		{
			digit++;
			digit++;
		}
		[quadKey appendFormat:@"%c",digit];
	}
	return quadKey;
}




/// <summary>
/// Converts a QuadKey into tile XY coordinates.
/// </summary>
/// <param name="quadKey">QuadKey of the tile.</param>
/// <param name="tileX">Output parameter receiving the tile X coordinate.</param>
/// <param name="tileY">Output parameter receiving the tile Y coordinate.</param>
/// <param name="levelOfDetail">Output parameter receiving the level of detail.</param>
static void QuadKeyToTileXY(NSString * quadKey, int * tileX, int * tileY, int * levelOfDetail)
{
	*tileX = *tileY = 0;
	*levelOfDetail = (int)quadKey.length;
	
	for (int i = *levelOfDetail; i > 0; i--) {
		int mask = 1 << (i - 1);
		switch ( [quadKey characterAtIndex:*levelOfDetail - i] )  {
			case '0':
				break;

			case '1':
				*tileX |= mask;
				break;

			case '2':
				*tileY |= mask;
				break;

			case '3':
				*tileX |= mask;
				*tileY |= mask;
				break;

			default:
				assert(NO);
		}
	}
}


#endif
