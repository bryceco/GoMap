//
//  CustomSegmentedControl.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/31/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

final class CustomSegmentedControl: UIControl {
	public let effectView: UIVisualEffectView
	private let stackView = UIStackView()

	public var controls: [UIControl] {
		get { stackView.arrangedSubviews as! [UIControl] }
		set { configure(with: newValue) }
	}

	override init(frame: CGRect) {
		effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
		super.init(frame: frame)
		setupViewHierarchy()
	}

	required init?(coder: NSCoder) {
		effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
		super.init(coder: coder)
		setupViewHierarchy()
	}

	private func setupViewHierarchy() {
		effectView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(effectView)

		NSLayoutConstraint.activate([
			effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
			effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
			effectView.topAnchor.constraint(equalTo: topAnchor),
			effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
		])

		stackView.axis = .horizontal
		stackView.isLayoutMarginsRelativeArrangement = true
		stackView.distribution = .fill
		stackView.translatesAutoresizingMaskIntoConstraints = false

		effectView.contentView.addSubview(stackView)
		NSLayoutConstraint.activate([
			stackView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
			stackView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
			stackView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
			stackView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor)
		])
	}

	private func configure(with controls: [UIControl]) {
		stackView.arrangedSubviews.forEach {
			stackView.removeArrangedSubview($0)
			$0.removeFromSuperview()
		}
		controls.forEach(stackView.addArrangedSubview)
	}
}
