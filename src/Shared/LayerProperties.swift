//
//  LayerProperties.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 5/18/20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import Foundation

@objcMembers
final class LayerProperties: NSObject {
    public var transform: CATransform3D = CATransform3D()
    public var position: OSMPoint = OSMPoint()
    public var offset = CGPoint.zero
	public var lineWidth: CGFloat = 0.0
    public var is3D = false
    public var isDirectional = false

    override init() {
        super.init()
            transform = CATransform3DIdentity
    }
}

@objc protocol LayerPropertiesProviding: AnyObject {
    var properties: LayerProperties { get }
}

@objcMembers
class CALayerWithProperties: CALayer, LayerPropertiesProviding {
    var properties: LayerProperties
    
    override init() {
		properties = LayerProperties()
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
		properties = LayerProperties()
        super.init(coder: aDecoder)
    }
}

@objcMembers
class CAShapeLayerWithProperties: CAShapeLayer, LayerPropertiesProviding {
    var properties: LayerProperties
    
    override init() {
		properties = LayerProperties()
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
		properties = LayerProperties()
        super.init(coder: aDecoder)
    }
}

@objcMembers
class CATextLayerWithProperties: CATextLayer, LayerPropertiesProviding {
    var properties: LayerProperties
    
    override init() {
		properties = LayerProperties()
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
		properties = LayerProperties()
        super.init(coder: aDecoder)
    }
}
