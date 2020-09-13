//
//  ErrorTableViewCell.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 13.09.20.
//  Copyright © 2020 Bryce. All rights reserved.
//

import UIKit

class ErrorTableViewCell: UITableViewCell {
    // MARK: Private properties

    @IBOutlet private var stackView: UIStackView!

    // MARK: Lifecycle

    override func prepareForReuse() {
        super.prepareForReuse()

        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            NSLayoutConstraint.deactivate($0.constraints)
            $0.removeFromSuperview()
        }
    }

    // MARK: Public methods

    func update(errors: [String]) {
        errors.forEach { error in
            let label = UILabel()
            label.numberOfLines = 0
            label.text = error

            stackView.addArrangedSubview(label)
        }
    }
}
