//
//  LayerProperties.h
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "VectorMath.h"


NS_ASSUME_NONNULL_BEGIN

@interface LayerProperties : NSObject
{
@public
	OSMPoint		position;
	double			lineWidth;
	CATransform3D	transform;
	CGPoint			offset;
	BOOL			is3D;
	BOOL			isDirectional;
}
@end

@protocol LayerPropertiesProviding

@property (readonly) LayerProperties * properties;

@end

@interface CALayerWithProperties : CALayer <LayerPropertiesProviding>
@end

@interface CAShapeLayerWithProperties : CAShapeLayer <LayerPropertiesProviding>
@end

@interface CATextLayerWithProperties : CATextLayer <LayerPropertiesProviding>
@end

NS_ASSUME_NONNULL_END
