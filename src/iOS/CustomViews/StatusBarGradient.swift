//
//  StatusBarGradient.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 9/26/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class StatusBarGradient: UIVisualEffectView {
	let gradientLayer = CAGradientLayer()

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		self.backgroundColor = .clear
		self.effect = UIBlurEffect(style: .regular)
	}

	override func layoutSubviews() {
		super.layoutSubviews()
		gradientLayer.frame = bounds

		if let insets = superview?.safeAreaInsets,
		   insets.top >= 40
		{
			// Set gradient so blurring is more pronounced towards the top
			gradientLayer.colors = [UIColor.black.withAlphaComponent(0.0).cgColor,
			                        UIColor.black.cgColor] // Clear at bottom, black at top
			gradientLayer.locations = [0.5, 1.0] // Gradual transition
			gradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0) // Start at bottom
			gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0) // End at top
			self.layer.mask = gradientLayer
		}
	}
}
