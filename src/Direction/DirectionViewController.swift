//
//  DirectionViewController.swift
//  Go Map!!
//
//  Created by Wolfgang Timme on 4/2/19.
//  Copyright © 2019 Bryce Cogswell. All rights reserved.
//

import UIKit

class DirectionViewController: UIViewController {
	// MARK: Private properties

	private let viewModel: MeasureDirectionViewModel
	private let onSetValue: (String) -> Void

	@IBOutlet var valueLabel: UILabel!
	@IBOutlet var oldValueLabel: UILabel!
	@IBOutlet var primaryActionButton: UIButton!
	@IBOutlet var cancelButton: UIButton!

	// MARK: Initializer

	init(key: String, value: String?, setValue: @escaping (String) -> Void) {
		viewModel = MeasureDirectionViewModel(key: key, value: value)
		onSetValue = setValue

		super.init(nibName: nil, bundle: nil)

		viewModel.delegate = self
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: View Lifecycle

	override func viewDidLoad() {
		super.viewDidLoad()

		title = NSLocalizedString("Measure Direction", comment: "")

		bindToViewModel()

		cancelButton.addTarget(self,
		                       action: #selector(cancel),
		                       for: .touchUpInside)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Hide the "Close" button if this view controller was part of a bigger `UINavigationController` stack.
		if let navigationController = navigationController {
			cancelButton.isHidden = navigationController.viewControllers.count > 1
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		viewModel.viewDidAppear()
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidAppear(animated)

		viewModel.viewDidDisappear()
	}

	// MARK: Private methods

	@IBAction private func didTapPrimaryActionButton() {
		viewModel.didTapPrimaryActionButton()
	}

	@objc private func cancel() {
		dismiss(animated: true)
	}

	private func bindToViewModel() {
		primaryActionButton.setTitle(viewModel.primaryActionButtonTitle, for: .normal)

		viewModel.onUpdate = { [weak self] in
			self?.updateFromViewModel()
		}
		updateFromViewModel()
	}

	private func updateFromViewModel() {
		valueLabel.text = viewModel.valueLabelText
		oldValueLabel.text = viewModel.oldValueLabelText
		primaryActionButton.isHidden = viewModel.isPrimaryActionButtonHidden
		cancelButton.setTitle(viewModel.dismissButtonTitle, for: .normal)
	}
}

extension DirectionViewController: MeasureDirectionViewModelDelegate {
	func didFinishUpdatingTag(key _: String, value: String) {
		onSetValue(value)
		if navigationController?.popViewController(animated: true) == nil {
			dismiss(animated: true, completion: nil)
		}
	}
}
