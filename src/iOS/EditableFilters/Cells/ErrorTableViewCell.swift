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

    override func awakeFromNib() {
        super.awakeFromNib()

        selectionStyle = .none
    }

    // MARK: Public methods

    func update(errors: [String]) {
        // Make sure to remove any errors that were previously displayed.
        removeErrorLabels()

        errors.forEach { error in
            let label = UILabel()
            label.numberOfLines = 0
            label.text = error

            stackView.addArrangedSubview(label)
        }
    }

    // MARK: Private methods

    private func removeErrorLabels() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            NSLayoutConstraint.deactivate($0.constraints)
            $0.removeFromSuperview()
        }
    }
}
