//
//  CustomSegmentedControl.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/31/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

final class CustomSegmentedControl: UIControl {
	private let stackView = UIStackView()

	public var controls: [UIView] {
		get {
			return stackView.arrangedSubviews
		}
		set {
			configure(with: newValue)
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		setupStackView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupStackView()
	}

	private func setupStackView() {
		stackView.axis = .horizontal
		stackView.alignment = .center
		stackView.isLayoutMarginsRelativeArrangement = true
		stackView.distribution = .fill
		stackView.translatesAutoresizingMaskIntoConstraints = false

		addSubview(stackView)

		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
			stackView.topAnchor.constraint(equalTo: topAnchor),
			stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
	}

	private func configure(with controls: [UIView]) {
		stackView.arrangedSubviews.forEach {
			stackView.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}

		for control in controls {
			stackView.addArrangedSubview(control)
		}
	}
}
