//
//  MeasureDirectionViewModel.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import CoreLocation
import Foundation

protocol MeasureDirectionViewModelDelegate: AnyObject {
	func didFinishUpdatingTag(key: String, value: String)
}

class MeasureDirectionViewModel: HeadingProviderDelegate {
	// MARK: Public properties

	weak var delegate: MeasureDirectionViewModelDelegate?
	var onUpdate: (() -> Void)?
	var valueLabelText: String = "..." { didSet { onUpdate?() } }
	var oldValueLabelText: String? { didSet { onUpdate?() } }
	let primaryActionButtonTitle: String
	var isPrimaryActionButtonHidden: Bool = true { didSet { onUpdate?() } }
	var dismissButtonTitle: String = NSLocalizedString("Cancel", comment: "") { didSet { onUpdate?() } }

	// MARK: Private properties

	private let headingProvider: HeadingProviding
	private let key: String
	private let oldValue: String?
	private var mostRecentHeading: CLHeading? {
		didSet {
			if mostRecentHeading != nil {
				// We have a heading that the user could apply. Show the primary action button.
				isPrimaryActionButtonHidden = false
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

		primaryActionButtonTitle = String(format: NSLocalizedString("Update '%@' tag",
		                                                            comment: "Update the named tag value (e.g. foo=*)"),
		                                  key)

		headingProvider.delegate = self

		guard headingProvider.isHeadingAvailable else {
			valueLabelText = "🤷‍♂️"
			oldValueLabelText = NSLocalizedString("This device is not able to provide heading data.",
			                                      comment: "")
			dismissButtonTitle = NSLocalizedString("Back", comment: "back button")
			return
		}

		if let oldValue = value, !oldValue.isEmpty {
			oldValueLabelText = String(format: NSLocalizedString("Old value: %@",
			                                                           comment: "previous tag value"),
			                                 oldValue)
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

		valueLabelText = "\(Int(heading.trueHeading))"
	}
}
