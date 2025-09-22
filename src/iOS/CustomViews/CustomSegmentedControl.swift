//
//  CustomSegmentedControl.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/31/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

final class CustomSegmentedControl: UIStackView {
	public var controls: [UIView] {
		get {
			return arrangedSubviews
		}
		set {
			configure(with: newValue)
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		setupStackView()
	}

	required init(coder: NSCoder) {
		super.init(coder: coder)
		setupStackView()
	}

	private func setupStackView() {
		axis = .horizontal
		alignment = .center
		isLayoutMarginsRelativeArrangement = true
		distribution = .fill
		translatesAutoresizingMaskIntoConstraints = false

		isLayoutMarginsRelativeArrangement = true
		layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
	}

	private func configure(with controls: [UIView]) {
		for arrangedSubview in arrangedSubviews {
			removeArrangedSubview(arrangedSubview)
			arrangedSubview.removeFromSuperview()
		}

		for control in controls {
			addArrangedSubview(control)
		}

		invalidateIntrinsicContentSize()
	}
}
