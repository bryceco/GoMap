//
//  CustomAlertController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/23/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomAlertController: UIViewController {
	private struct Action {
		let title: String
		let image: UIImage?
		let isCancel: Bool
		let handler: (() -> Void)?
	}

	private let titleText: String?
	private let messageText: String?
	private var actions: [Action] = []

	init(title: String?, message: String?) {
		titleText = title
		messageText = message
		super.init(nibName: nil, bundle: nil)
		modalPresentationStyle = .overFullScreen
		modalTransitionStyle = .crossDissolve
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func addAction(title: String, image: UIImage?, isCancel: Bool = false, handler: (() -> Void)? = nil) {
		let action = Action(title: title, image: image, isCancel: isCancel, handler: handler)
		actions.append(action)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		// dim the background screen
		view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

		// capture taps outside the alert to dismiss
		let dismissTapView = UIView()
		dismissTapView.translatesAutoresizingMaskIntoConstraints = false
		view.insertSubview(dismissTapView, at: 0) // behind everything
		NSLayoutConstraint.activate([
			dismissTapView.topAnchor.constraint(equalTo: view.topAnchor),
			dismissTapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			dismissTapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			dismissTapView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
		])
		let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissOnBackgroundTap))
		dismissTapView.addGestureRecognizer(tapGesture)

		// set up everything else
		setupAlertView()
	}

	@objc private func dismissOnBackgroundTap() {
		dismiss(animated: true)
	}

	private func setupAlertView() {
		let buttonHeight = 55.0
		let cornerRadius = 12.0
		let alertStack = UIStackView()
		alertStack.axis = .vertical
		alertStack.spacing = 8 // distance between buttons and cancel button
		alertStack.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(alertStack)

		if traitCollection.horizontalSizeClass == .compact {
			// iPhone
			NSLayoutConstraint.activate([
				alertStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40),
				alertStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
				alertStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
			])
		} else {
			// iPad
			NSLayoutConstraint.activate([
				alertStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
				alertStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
				alertStack.widthAnchor.constraint(equalToConstant: 320)
			])
		}
		// Main content view
		let contentView = UIView()
		contentView.backgroundColor = .systemBackground
		contentView.layer.cornerRadius = cornerRadius // should match corner radius of Cancel button
		contentView.translatesAutoresizingMaskIntoConstraints = false

		var headerViews: [UIView] = []
		if let titleText {
			let titleLabel = UILabel()
			titleLabel.text = titleText
			titleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
			titleLabel.textAlignment = .center
			titleLabel.textColor = .systemGray
			headerViews.append(titleLabel)
		}

		if let messageText {
			let messageLabel = UILabel()
			messageLabel.text = messageText
			messageLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
			messageLabel.textAlignment = .center
			messageLabel.numberOfLines = 0
			headerViews.append(messageLabel)
		}

		let buttonsStack = UIStackView()
		buttonsStack.axis = .vertical
		buttonsStack.spacing = 0
		buttonsStack.translatesAutoresizingMaskIntoConstraints = false

		let headersAndButtonsStack = UIStackView(arrangedSubviews: headerViews + [buttonsStack])
		headersAndButtonsStack.axis = .vertical
		headersAndButtonsStack.spacing = 2
		headersAndButtonsStack.translatesAutoresizingMaskIntoConstraints = false

		contentView.addSubview(headersAndButtonsStack)
		NSLayoutConstraint.activate([
			headersAndButtonsStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0),
			headersAndButtonsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -0),
			headersAndButtonsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
			headersAndButtonsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -0)
		])
		alertStack.addArrangedSubview(contentView)

		// Add main actions
		actions.filter { !$0.isCancel }.forEach { action in
			let button = ButtonClosure(type: .system)
			button.setTitle(action.title, for: .normal)
			button.setImage(action.image, for: .normal)
			button.tintColor = .link
			button.backgroundColor = .systemGroupedBackground

			button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout)
			button.imageView?.contentMode = .scaleAspectFit
			button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

			button.contentHorizontalAlignment = .leading
			button.layer.cornerRadius = cornerRadius
			button.imageView!.translatesAutoresizingMaskIntoConstraints = false
			button.titleLabel!.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				button.titleLabel!.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 60),
				button.heightAnchor.constraint(equalToConstant: buttonHeight)
			])

			button.onTap = { [weak self] _ in
				self?.dismiss(animated: true)
				action.handler?()
			}
			buttonsStack.addArrangedSubview(button)

			let separator = UIView()
			separator.backgroundColor = UIColor.systemGray4
			separator.heightAnchor.constraint(equalToConstant: 1.0).isActive = true
			buttonsStack.addArrangedSubview(separator)
		}
		// remove the last separator line
		if let lastView = buttonsStack.arrangedSubviews.last {
			buttonsStack.removeArrangedSubview(lastView)
			lastView.removeFromSuperview()
		}

		// Cancel button with gap
		for cancel in actions.filter({ $0.isCancel }) {
			let cancelButton = ButtonClosure(type: .system)
			cancelButton.setTitle(cancel.title, for: .normal)
			cancelButton.setImage(cancel.image, for: .normal)
			cancelButton.tintColor = .link
			cancelButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout).bold()
			cancelButton.imageView?.contentMode = .scaleAspectFit
			cancelButton.contentHorizontalAlignment = .center
			cancelButton.semanticContentAttribute = .forceLeftToRight
			cancelButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -8,
			                                            bottom: 0, right: 8)
			cancelButton.backgroundColor = .systemBackground
			cancelButton.layer.cornerRadius = cornerRadius
			cancelButton.onTap = { [weak self] _ in
				self?.dismiss(animated: true)
				cancel.handler?()
			}

			alertStack.addArrangedSubview(cancelButton)

			cancelButton.sizeToFit()
			NSLayoutConstraint.activate([
				cancelButton.heightAnchor.constraint(equalToConstant: buttonHeight)
			])
		}
		/*
		 alertStack.backgroundColor = .red
		 buttonsStack.backgroundColor = .green
		 contentView.backgroundColor = .yellow
		 headersAndButtonsStack.backgroundColor = .blue
		 */
	}
}
