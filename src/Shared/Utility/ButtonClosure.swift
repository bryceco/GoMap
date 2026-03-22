//
//  ButtonClosure.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 7/31/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class ButtonClosure: UIButton {
	var onTap: ((UIButton) -> Void)?

	override init(frame: CGRect) {
		super.init(frame: frame)
		addTarget(self, action: #selector(trigger), for: .touchUpInside)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		addTarget(self, action: #selector(trigger), for: .touchUpInside)
	}

	@objc private func trigger() {
		onTap?(self)
	}
}
