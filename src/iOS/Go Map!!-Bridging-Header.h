//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "EditorMapLayer.h"
#import "LayerProperties.h"
#import "OsmMapData.h"
#import "OsmMember.h"
#import "OsmNode.h"
#import "OsmRelation.h"
#import "OsmWay.h"
#import "PathUtil.h"
#import "RenderInfo.h"
#import "VectorMath.h"
#import "MercatorTileLayer.h"
#import "GpxLayer.h"
#import "MapView.h"
#import "OsmNotesDatabase.h"
#import "BingMapsGeometry.h"
#import "DLog.h"
#import "SpeechBalloonView.h"
#import "PersistentWebCache.h"
#import "OsmMapData+Edit.h"
#import "ExternalGPS.h"
#import "DDXML.h"
#import "DisplayLink.h"
#import "OsmBaseObject.h"
#import "aes.h"

UIImage * IconScaledForDisplay(UIImage *icon);
UIImage * ImageScaledToSize( UIImage * image, CGFloat iconSize);
typedef void (^    PushPinViewDragCallback)(UIGestureRecognizerState state, CGFloat dx, CGFloat dy, UIGestureRecognizer * gesture );



// MARK: PathUtil.swift
//typedef void (^ApplyPathCallback)(CGPathElementType type, CGPoint * points);
//static void InvokeBlockAlongPathCallback2( void * info, const CGPathElement * element )
//{
//    ApplyPathCallback block = (__bridge ApplyPathCallback)info;
//    block( element->type, element->points );
//}
//void CGPathApplyBlockEx( CGPathRef path, ApplyPathCallback block )
//{
//    CGPathApply(path, (__bridge void *)block, InvokeBlockAlongPathCallback2);
//}
//



// MARK: BingMapsGeometry.swift
//static const double EarthRadius = 6378137;
//static const double MinLatitude = -85.05112878;
//static const double MaxLatitude = 85.05112878;
//static const double MinLongitude = -180;
//static const double MaxLongitude = 180;
//
///// <summary>
///// Clips a number to the specified minimum and maximum values.
///// </summary>
///// <param name="n">The number to clip.</param>
///// <param name="minValue">Minimum allowable value.</param>
///// <param name="maxValue">Maximum allowable value.</param>
///// <returns>The clipped value.</returns>
//static double Clip(double n, double minValue, double maxValue)
//{
//    return MIN(MAX(n, minValue), maxValue);
//}
//
///// <summary>
///// Determines the map width and height (in pixels) at a specified level
///// of detail.
///// </summary>
///// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
///// to 23 (highest detail).</param>
///// <returns>The map width and height in pixels.</returns>
//static NSUInteger MapSize(NSInteger levelOfDetail)
//{
//    return (NSUInteger) 256 << levelOfDetail;
//}
//
///// <summary>
///// Determines the ground resolution (in meters per pixel) at a specified
///// latitude and level of detail.
///// </summary>
///// <param name="latitude">Latitude (in degrees) at which to measure the
///// ground resolution.</param>
///// <param name="levelOfDetail">Level of detail, from 1 (lowest detail)
///// to 23 (highest detail).</param>
///// <returns>The ground resolution, in meters per pixel.</returns>
//static double GroundResolution(double latitude, NSInteger levelOfDetail)
//{
//    latitude = Clip(latitude, MinLatitude, MaxLatitude);
//    return cos(latitude * M_PI / 180) * 2 * M_PI * EarthRadius / MapSize(levelOfDetail);
//}
//
//inline static double MetersPerDegree( double latitude )
//{
//    return cos(latitude * M_PI / 180) * 2 * M_PI * 6378137 / 360;
//}
//
//inline static int MinimumLevelOfDetail(double latitude, double metersPerPixel)
//{
//    double res = GroundResolution(latitude, 0);
//    int levelOfDetail = (int)ceil( log2( res / metersPerPixel ) );
//    return levelOfDetail;
//}
//
//
//inline static double MetersPerDegreeLatitude( double latitude )
//{
//    latitude *= M_PI / 180;
//    return 111132.954 - 559.822 * cos( 2 * latitude ) + 1.175 * cos( 4 * latitude );
//}
//inline static double MetersPerDegreeLongitude( double latitude )
//{
//    latitude *= M_PI / 180;
//    return 111132.954 * cos ( latitude );
//}
//



//MARK: GpxLayer.swift
//#define USER_DEFAULTS_GPX_EXPIRATIION_KEY         @"GpxTrackExpirationDays"
//#define USER_DEFAULTS_GPX_BACKGROUND_TRACKING     @"GpxTrackBackgroundTracking"
//
