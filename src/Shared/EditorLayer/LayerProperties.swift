//
//  LayerProperties.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/18/20.
//  Copyright © 2020 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

final class LayerProperties {
	public var transform3D: CATransform3D = CATransform3DIdentity
	public var position = OSMPoint.zero
	public var offset = CGPoint.zero
	public var lineWidth: CGFloat = 0.0
	public var is3D = false
	public var isDirectional = false

	// Build a transform matrix that we can add to a CAShapeLayer to correctly
	// transform the map-point values stored in its CGPath to screen points.
	//
	// CGPath points are relative to the 'position' anchor, multiplied by PATH_SCALING
	func layerTransformFor(mapTransform: MapTransform) -> CGAffineTransform {
		assert(!is3D)

		// Start with the mapTransform
		var t = mapTransform.transform.cgAffineTransform()

		// Add in the anchor position so points are no longer anchor-relative
		t = t.translatedBy(x: position.x, y: position.y)

		// Undo the PATH_SCALING factor
		t = t.scaledBy(x: CGFloat(1.0 / PATH_SCALING), y: CGFloat(1.0 / PATH_SCALING))

		// Finally subtract out the anchor, since it may be different than the layer's origin
		t.tx -= position.x
		t.ty -= position.y

		return t
	}

	func layerTransform3D(mapTransform: MapTransform, pixelsPerMeter: Double) -> CATransform3D? {
		if is3D, mapTransform.birdsEye() == nil {
			return nil
		}

		// Start with the mapTransform
		var t = CATransform3DMakeAffineTransform(mapTransform.transform.cgAffineTransform())

		// Add in the anchor position so points are no longer anchor-relative
		t = CATransform3DTranslate(t, position.x, position.y, 0.0)

		// Undo the PATH_SCALING factor
		t = CATransform3DScale(t, CGFloat(1.0 / PATH_SCALING), CGFloat(1.0 / PATH_SCALING), CGFloat(pixelsPerMeter))

		// Finally subtract out the anchor, since it may be different than the layer's origin
		t.m41 -= position.x
		t.m42 -= position.y

		// Apply the 3D transform to it
		t = CATransform3DConcat(transform3D, t)

		return t
	}
}

protocol LayerPropertiesProviding: AnyObject {
	var properties: LayerProperties { get }
}

class CALayerWithProperties: CALayer, LayerPropertiesProviding {
	var properties = LayerProperties()
}

final class CAShapeLayerWithProperties: CAShapeLayer, LayerPropertiesProviding {
	var properties = LayerProperties()
}

final class CATextLayerWithProperties: CATextLayer, LayerPropertiesProviding {
	var properties = LayerProperties()
}
