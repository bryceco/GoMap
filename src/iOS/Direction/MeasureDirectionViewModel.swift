//
//  MeasureDirectionViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import Foundation
import CoreLocation

@objc protocol MeasureDirectionViewModelDelegate: class {
    func dismiss(_ direction: String?)
}

class MeasureDirectionViewModel: NSObject, HeadingProviderDelegate {
    
    // MARK: Public properties
    
    weak var delegate: MeasureDirectionViewModelDelegate?
    var valueLabelText = Observable<String>("...")
    var oldValueLabelText = Observable<String?>(nil)
    var isPrimaryActionButtonHidden = Observable<Bool>(false)
    var dismissButtonTitle = Observable<String>("Cancel")
    
    // MARK: Private properties
    
    private let headingProvider: HeadingProviding
    private var mostRecentHeading: CLHeading?
    
    // MARK: Initializer
    
    init(headingProvider: HeadingProviding = LocationManagerHeadingProvider.shared, oldValue: String? = nil) {
        self.headingProvider = headingProvider
        
        super.init()
        
        headingProvider.delegate = self
        
        guard headingProvider.isHeadingAvailable else {
            valueLabelText.value = "🤷‍♂️"
            oldValueLabelText.value = "This device is not able to provide heading data."
            dismissButtonTitle.value = "Back"
            isPrimaryActionButtonHidden.value = true
            
            return
        }
        
        if let oldValue = oldValue {
            oldValueLabelText.value = "Old value: \(oldValue)"
        }
    }
    
    // MARK: Public methods
    
    func viewDidAppear() {
        headingProvider.startUpdatingHeading()
    }
    
    func viewDidDisappear() {
        headingProvider.stopUpdatingHeading()
    }
    
    func didTapPrimaryActionButton() {
        let direction: String?
        if let heading = mostRecentHeading {
            direction = "\(Int(heading.trueHeading))"
        } else {
            direction = nil
        }
        
        delegate?.dismiss(direction)
    }
    
    // MARK: HeadingProviderDelegate
    
    func headingProviderDidUpdateHeading(_ heading: CLHeading) {
        mostRecentHeading = heading
        
        valueLabelText.value = "\(Int(heading.trueHeading))"
    }

}
