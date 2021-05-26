//
//  MeasureDirectionViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce. All rights reserved.
//

import CoreLocation
import Foundation

protocol MeasureDirectionViewModelDelegate: AnyObject {
	func didFinishUpdatingTag(key: String, value: String)
}

class MeasureDirectionViewModel: HeadingProviderDelegate {
    // MARK: Public properties

    weak var delegate: MeasureDirectionViewModelDelegate?
    var valueLabelText = Observable<String>("...")
    var oldValueLabelText = Observable<String?>(nil)
    let primaryActionButtonTitle: String
    var isPrimaryActionButtonHidden = Observable<Bool>(true)
    var dismissButtonTitle = Observable<String>("Cancel")

    // MARK: Private properties

    private let headingProvider: HeadingProviding
    private let key: String
    private let oldValue: String?
    private var mostRecentHeading: CLHeading? {
        didSet {
            if mostRecentHeading != nil {
                // We have a heading that the user could apply. Show the primary action button.
                isPrimaryActionButtonHidden.value = false
            }
        }
    }

    // MARK: Initializer

    init(headingProvider: HeadingProviding = LocationManagerHeadingProvider.shared,
         key: String,
         value: String? = nil)
    {
        self.headingProvider = headingProvider
        self.key = key
        oldValue = value

        primaryActionButtonTitle = String(format: "Update '%@' tag", key)

        headingProvider.delegate = self

        guard headingProvider.isHeadingAvailable else {
            valueLabelText.value = "🤷‍♂️"
            oldValueLabelText.value = "This device is not able to provide heading data."
            dismissButtonTitle.value = "Back"

            return
        }

        if let oldValue = value, !oldValue.isEmpty {
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
        let value: String
        if let heading = mostRecentHeading {
            value = "\(Int(heading.trueHeading))"
        } else if oldValue == nil {
            return
        } else {
            value = oldValue!
        }

        delegate?.didFinishUpdatingTag(key: key, value: value)
    }

    // MARK: HeadingProviderDelegate

    func headingProviderDidUpdateHeading(_ heading: CLHeading) {
        mostRecentHeading = heading

        valueLabelText.value = "\(Int(heading.trueHeading))"
    }
}
