//
//  TristateButton.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/3/21.
//  Copyright © 2021 Bryce Cogswell. All rights reserved.
//

import Foundation
import UIKit

class TristateButton: UISegmentedControl {
	var onSelect: ((String?) -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
	}

	init(withLeftText leftText: String, rightText: String) {
		super.init(items: [leftText, "-", rightText])
		apportionsSegmentWidthsByContent = true
		setEnabled(true, forSegmentAt: 1)
		addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
	}

	func setSelection(forString value: String) {
		preconditionFailure("This method must be overridden")
	}

	func stringForSelection() -> String? {
		preconditionFailure("This method must be overridden")
	}

	@objc private func valueChanged(_ sender: Any?) {
		if let onSelect = onSelect {
			onSelect(stringForSelection())
		}
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
}

class TristateYesNoButton: TristateButton {
	required init() {
		super.init(withLeftText: PresetsDatabase.shared.noForLocale,
				   rightText: PresetsDatabase.shared.yesForLocale)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func stringForSelection() -> String? {
		return ["no", nil, "yes"][selectedSegmentIndex]
	}

	override func setSelection(forString value: String) {
		if OsmTags.isOsmBooleanFalse(value) {
			super.selectedSegmentIndex = 0
		} else if OsmTags.isOsmBooleanTrue(value) {
			super.selectedSegmentIndex = 2
		} else {
			super.selectedSegmentIndex = 1
		}
	}
}

class TristateKmhMphButton: TristateButton {
	
	required init() {
		super.init(withLeftText: NSLocalizedString("km/h", comment: "kilometers per hour speed"),
				   rightText: NSLocalizedString("mph", comment: "miles per hour speed"))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func stringForSelection() -> String? {
		return ["km/h", nil, "mph"][selectedSegmentIndex]
	}

	// input is a value like "55 mph"
	override func setSelection(forString value: String) {
		let text: String
		if let index = value.firstIndex(where: {!($0.isNumber || $0 == "." || $0 == " ")}) {
			text = String(value.suffix(from: index))
		} else {
			text = ""
		}

		if text == "km/h" {
			super.selectedSegmentIndex = 0
		} else if text == "mph" {
			super.selectedSegmentIndex = 2
		} else {
			super.selectedSegmentIndex = 1
		}
	}
}
