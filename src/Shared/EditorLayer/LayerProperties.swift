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
	public var transform: CATransform3D = CATransform3DIdentity
	public var position = OSMPoint.zero
	public var offset = CGPoint.zero
	public var lineWidth: CGFloat = 0.0
	public var is3D = false
	public var isDirectional = false
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
