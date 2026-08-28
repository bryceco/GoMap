//
//  HUDLabel.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 6/28/26.
//  Copyright © 2026 Bryce Cogswell. All rights reserved.
//

import UIKit

/// A UIView wrapping a UILabel that adds content insets.
public final class HUDLabel: UIView {

	private let label: UILabel = {
		let l = UILabel()
		l.translatesAutoresizingMaskIntoConstraints = false
		l.numberOfLines = 0
		return l
	}()

	public var contentInsets: UIEdgeInsets = .zero {
		didSet {
			topConstraint.constant = contentInsets.top
			leadingConstraint.constant = contentInsets.left
			bottomConstraint.constant = -contentInsets.bottom
			trailingConstraint.constant = -contentInsets.right
		}
	}

	// Forwarded UILabel properties
	public var text: String? {
		get { label.text }
		set { label.text = newValue }
	}

	public var attributedText: NSAttributedString? {
		get { label.attributedText }
		set { label.attributedText = newValue }
	}

	public var font: UIFont! {
		get { label.font }
		set { label.font = newValue }
	}

	public var textColor: UIColor! {
		get { label.textColor }
		set { label.textColor = newValue }
	}

	public var textAlignment: NSTextAlignment {
		get { label.textAlignment }
		set { label.textAlignment = newValue }
	}

	public var numberOfLines: Int {
		get { label.numberOfLines }
		set { label.numberOfLines = newValue }
	}

	public var adjustsFontForContentSizeCategory: Bool {
		get { label.adjustsFontForContentSizeCategory }
		set { label.adjustsFontForContentSizeCategory = newValue }
	}

	private var topConstraint: NSLayoutConstraint!
	private var leadingConstraint: NSLayoutConstraint!
	private var bottomConstraint: NSLayoutConstraint!
	private var trailingConstraint: NSLayoutConstraint!

	override public init(frame: CGRect) {
		super.init(frame: frame)
		setup()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	private func setup() {
		addSubview(label)
		topConstraint = label.topAnchor.constraint(equalTo: topAnchor)
		leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor)
		bottomConstraint = label.bottomAnchor.constraint(equalTo: bottomAnchor)
		trailingConstraint = label.trailingAnchor.constraint(equalTo: trailingAnchor)
		NSLayoutConstraint.activate([topConstraint, leadingConstraint, bottomConstraint, trailingConstraint])
	}
}
