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
		// Generate haptic feedback
		let feedback = UIImpactFeedbackGenerator(style: .light)
		feedback.impactOccurred()
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

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
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

class KmhMphToggle: UISegmentedControl {
	var onSelect: ((String?) -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
	}

	init() {
		super.init(items: [NSLocalizedString("km/h", comment: "kilometers per hour speed"),
		                   NSLocalizedString("mph", comment: "miles per hour speed")])
		apportionsSegmentWidthsByContent = true
		setEnabled(true, forSegmentAt: 0)
		addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
	}

	@objc private func valueChanged(_ sender: Any?) {
		if let onSelect = onSelect {
			onSelect(stringForSelection())
		}
		// Generate haptic feedback
		let feedback = UIImpactFeedbackGenerator(style: .light)
		feedback.impactOccurred()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	func stringForSelection() -> String? {
		return [nil, "mph"][selectedSegmentIndex]
	}

	// input is a value like "55 mph"
	func setSelection(forString value: String) {
		var text = String(value.compactMap {
			$0.isNumber || $0 == "." ? nil : $0
		})
		text = text.trimmingCharacters(in: .whitespacesAndNewlines)

		switch text {
		case "":
			super.selectedSegmentIndex = 0
		case "mph":
			super.selectedSegmentIndex = 1
		default:
			break
		}
	}
}

class CulvertToggle: UISegmentedControl {
	var onSelect: ((String?) -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
	}

	init() {
		super.init(items: [NSLocalizedString("no", comment: ""),
		                   NSLocalizedString("yes", comment: "")])
		apportionsSegmentWidthsByContent = true
		setEnabled(true, forSegmentAt: 0)
		addTarget(self, action: #selector(valueChanged(_:)), for: .valueChanged)
	}

	@objc private func valueChanged(_ sender: Any?) {
		if let onSelect = onSelect {
			onSelect(stringForSelection())
		}
		// Generate haptic feedback
		let feedback = UIImpactFeedbackGenerator(style: .light)
		feedback.impactOccurred()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	func stringForSelection() -> String? {
		return [nil, "culvert"][selectedSegmentIndex]
	}

	// input is a value like "55 mph"
	func setSelection(forString value: String) {
		let text: String
		if let index = value.firstIndex(where: { !($0.isNumber || $0 == ".") }) {
			text = String(value.suffix(from: index)).trimmingCharacters(in: .whitespacesAndNewlines)
		} else {
			text = ""
		}

		switch text {
		case "":
			super.selectedSegmentIndex = 0
		case "yes", "culvert":
			super.selectedSegmentIndex = 1
		default:
			break
		}
	}
}
