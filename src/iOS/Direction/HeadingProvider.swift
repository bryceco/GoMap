//
//  HeadingProvider.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
import CoreLocation

protocol HeadingProviderDelegate: class {
    func headingProviderDidUpdateHeading(_ heading: CLHeading)
}

protocol HeadingProviding: AnyObject {
    var delegate: HeadingProviderDelegate? { get set }
    
    /// Flag whether this object is able to provide compass-related headings.
    var isHeadingAvailable: Bool { get }
    
    /// Starts the generation of updates that report the user’s current heading.
    func startUpdatingHeading()
    
    /// Stops the generation of heading updates.
    func stopUpdatingHeading()
}
