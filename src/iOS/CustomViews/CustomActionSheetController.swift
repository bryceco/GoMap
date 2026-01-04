//
//  CustomActionSheetController.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 8/23/25.
//  Copyright © 2025 Bryce Cogswell. All rights reserved.
//

import UIKit

class CustomActionSheetController: UIViewController {
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
			headersAndButtonsStack.topAnchor.constraint(equalTo: contentView.topAnchor),
			headersAndButtonsStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			headersAndButtonsStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			headersAndButtonsStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
		])
		alertStack.addArrangedSubview(contentView)

		// Add main actions
		actions.filter { !$0.isCancel }.forEach { action in
			let button = ButtonClosure(type: .system)
			button.translatesAutoresizingMaskIntoConstraints = false

			// We use our own controls for title/icon:
			button.setTitle(nil, for: .normal)
			button.setImage(nil, for: .normal)

			// Icon container with fixed width so titles align
			let iconContainer = UIView()
			iconContainer.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				iconContainer.widthAnchor.constraint(equalToConstant: 44)
			])

			let iconView = UIImageView(image: action.image!.withRenderingMode(.alwaysTemplate))
			iconView.contentMode = .scaleAspectFit
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.tintColor = .link

			iconContainer.addSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
				iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
				iconView.heightAnchor.constraint(equalToConstant: 30),
				iconView.widthAnchor.constraint(equalToConstant: 32)
			])

			// Title label we control
			let titleLabel = UILabel()
			titleLabel.text = action.title
			titleLabel.font = UIFont.preferredFont(forTextStyle: .callout)
			titleLabel.textColor = .link
			titleLabel.translatesAutoresizingMaskIntoConstraints = false

			// Horizontal stack: [iconContainer][titleLabel]
			let stack = UIStackView(arrangedSubviews: [iconContainer, titleLabel])
			stack.axis = .horizontal
			stack.spacing = 8
			stack.alignment = .center
			stack.translatesAutoresizingMaskIntoConstraints = false

			button.addSubview(stack)
			NSLayoutConstraint.activate([
				stack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 8),
				stack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
				stack.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
				stack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -8),
				button.heightAnchor.constraint(equalToConstant: buttonHeight)
			])

#if targetEnvironment(macCatalyst)
			if #available(macCatalyst 15.0, *) {
				button.preferredBehavioralStyle = .pad
			}
#endif
			button.backgroundColor = .systemGroupedBackground
			button.layer.cornerRadius = cornerRadius
			button.clipsToBounds = true

			button.onTap = { [weak self] _ in
				self?.dismiss(animated: true)
				action.handler?()
			}

			buttonsStack.addArrangedSubview(button)

			let separator = UIView()
			separator.backgroundColor = UIColor.systemGray4
			separator.translatesAutoresizingMaskIntoConstraints = false
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
			cancelButton.imageView?.contentMode = .scaleAspectFit
			cancelButton.contentHorizontalAlignment = .center

			cancelButton.backgroundColor = .systemBackground
			cancelButton.layer.cornerRadius = cornerRadius
#if targetEnvironment(macCatalyst)
			if #available(macCatalyst 15.0, *) {
				cancelButton.preferredBehavioralStyle = .pad
			}
#else
			// these don't play well with setting .pad style on Mac
			cancelButton.setTitleColor(.link, for: .normal)
			cancelButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .callout).bold()
#endif

			cancelButton.onTap = { [weak self] _ in
				self?.dismiss(animated: true)
				cancel.handler?()
			}

			alertStack.addArrangedSubview(cancelButton)

			cancelButton.sizeToFit()
			cancelButton.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				cancelButton.heightAnchor.constraint(equalToConstant: buttonHeight)
			])
		}
	}

#if targetEnvironment(macCatalyst)
	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		if presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
			dismiss(animated: true)
			return
		}
		super.pressesBegan(presses, with: event)
	}
#endif
}
