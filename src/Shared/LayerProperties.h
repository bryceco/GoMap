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
	BOOL			is3D;
	BOOL			isDirectional;
}
@end

@interface CALayerWithProperties : CALayer
@property (readonly) LayerProperties * properties;
@end

@interface CAShapeLayerWithProperties : CAShapeLayer
@property (readonly) LayerProperties * properties;
@end

@interface CATextLayerWithProperties : CATextLayer
@property (readonly) LayerProperties * properties;
@end

NS_ASSUME_NONNULL_END
