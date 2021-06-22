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

	func stringForSelection() -> String? {
		return ["no", nil, "yes"][selectedSegmentIndex]
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
	}

	init() {
		super.init(items: [PresetsDatabase.shared.noForLocale, "-", PresetsDatabase.shared.yesForLocale])
		apportionsSegmentWidthsByContent = true
		setEnabled(true, forSegmentAt: 1)
		addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
	}

	@objc private func valueChanged(_ sender: Any?) {
		if let onSelect = onSelect {
			onSelect(stringForSelection())
		}
	}

	func setSelection(forString value: String) {
		if OsmTags.isOsmBooleanFalse(value) {
			super.selectedSegmentIndex = 0
		} else if OsmTags.isOsmBooleanTrue(value) {
			super.selectedSegmentIndex = 2
		} else {
			super.selectedSegmentIndex = 1
		}
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
}
