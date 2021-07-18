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

	private var viewModel: MeasureDirectionViewModel! = nil
	private var disposal = Disposal()
	private var callback: ((String?) -> Void)! = nil

	@IBOutlet var valueLabel: UILabel!
	@IBOutlet var oldValueLabel: UILabel!
	@IBOutlet var primaryActionButton: UIButton!
	@IBOutlet var cancelButton: UIButton!

	// MARK: Initializer

	class func instantiate(key: String, value: String?, setValue: @escaping (String?) -> Void) -> DirectionViewController
	{
		let sb = UIStoryboard(name: "DirectionViewController", bundle: nil)
		let vc = sb.instantiateViewController(withIdentifier: "DirectionViewController") as! DirectionViewController
		vc.viewModel = MeasureDirectionViewModel(key: key, value: value)
		vc.callback = setValue
		vc.viewModel.delegate = vc
		return vc
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

		viewModel.valueLabelText.observe { [weak self] text, _ in
			guard let self = self else { return }

			self.valueLabel.text = text
		}.add(to: &disposal)

		viewModel.oldValueLabelText.observe { [weak self] text, _ in
			guard let self = self else { return }

			self.oldValueLabel.text = text
		}.add(to: &disposal)

		viewModel.isPrimaryActionButtonHidden.observe { [weak self] isHidden, _ in
			guard let self = self else { return }

			self.primaryActionButton.isHidden = isHidden
		}.add(to: &disposal)

		viewModel.dismissButtonTitle.observe { [weak self] title, _ in
			guard let self = self else { return }

			self.cancelButton.setTitle(title, for: .normal)
		}.add(to: &disposal)
	}
}

extension DirectionViewController: MeasureDirectionViewModelDelegate {
	func didFinishUpdatingTag(key _: String, value: String) {
		callback(value)
		if navigationController?.popViewController(animated: true) == nil {
			dismiss(animated: true, completion: nil)
		}
	}
}
