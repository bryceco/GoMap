//
//  HeadingProvider.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import Foundation

protocol HeadingProviderDelegate: AnyObject {
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

class LocationManagerHeadingProvider: NSObject, HeadingProviding {
    // MARK: Public properties

    static let shared = LocationManagerHeadingProvider()

    // MARK: Private properties

    private let locationManager: CLLocationManager

    // MARK: Initializer

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager

        super.init()

        locationManager.delegate = self
    }

    // MARK: HeadingProviding

    weak var delegate: HeadingProviderDelegate?

    var isHeadingAvailable: Bool {
        return CLLocationManager.headingAvailable()
    }

    func startUpdatingHeading() {
        locationManager.startUpdatingHeading()
    }

    func stopUpdatingHeading() {
        locationManager.stopUpdatingHeading()
    }
}

extension LocationManagerHeadingProvider: CLLocationManagerDelegate {
    func locationManager(_: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        delegate?.headingProviderDidUpdateHeading(newHeading)
    }
}
